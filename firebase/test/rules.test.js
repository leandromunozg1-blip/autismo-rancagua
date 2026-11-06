'use strict';

const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, updateDoc, deleteDoc, collection, query, where,
  getDocs, Timestamp, serverTimestamp, deleteField,
} = require('firebase/firestore');
const {ref, uploadBytes, getBytes, deleteObject, updateMetadata} = require('firebase/storage');

const PROJECT = 'demo-autismo-rancagua-v58';
const FILE = '0123456789abcdefghij.png';
const IMAGE = new Uint8Array([137,80,78,71,13,10,26,10,0]);
let env;

before(async () => {
  // Refuse to run against anything other than local emulators; no fallback to prod.
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127[.]0[.]0[.]1|localhost):\d+$/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST || '', /^(127[.]0[.]0[.]1|localhost):\d+$/);
  const fragment = fs.readFileSync(path.join(__dirname, '../tesoreria.firestore.rules.fragment'), 'utf8');
  const firestoreRules = fs.readFileSync(path.join(__dirname, '../emulator.firestore.rules'), 'utf8');
  const storageFragment = fs.readFileSync(path.join(__dirname, '../tesoreria.storage.rules.fragment'), 'utf8');
  const storageRules = fs.readFileSync(path.join(__dirname, '../emulator.storage.rules'), 'utf8');
  assert.ok(firestoreRules.includes(fragment), 'Firestore fixture must test current fragment');
  assert.ok(storageRules.includes(storageFragment), 'Storage fixture must test current fragment');
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: firestoreRules},
    storage: {rules: storageRules},
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'usuarios/padre-a'), {rol: 'apoderado', activo: true, email: 'a@example.test'}),
      setDoc(doc(db, 'usuarios/padre-b'), {rol: 'apoderado', activo: true}),
      setDoc(doc(db, 'usuarios/tesorero'), {rol: 'tesoreria', activo: true}),
      setDoc(doc(db, 'usuarios/tesorero-inactivo'), {rol: 'tesoreria', activo: false}),
      setDoc(doc(db, 'usuarios/admin'), {rol: 'admin_general', activo: true}),
      setDoc(doc(db, 'usuarios/multirrol'), {rol: 'coordinacion', roles: ['coordinacion', 'tesoreria']}),
      setDoc(doc(db, 'usuarios/coordinador'), {rol: 'coordinacion', activo: true}),
      setDoc(doc(db, 'usuarios/rol-malformado'), {rol: 'apoderado', roles: 'tesoreria', activo: true}),
      setDoc(doc(db, 'comprobantes_pago/recibo-a'), {uid: 'padre-a', estado: 'pendiente', monto: 1000}),
      setDoc(doc(db, 'comprobantes_pago/recibo-b'), {uid: 'padre-b', estado: 'pendiente', monto: 2000}),
      setDoc(doc(db, 'avisos_apoderados/aviso-a'), {
        apoderado_id: 'padre-a', titulo: 'Pago', mensaje: 'Mensaje', leido: false, aceptado: false,
        fecha: Timestamp.fromMillis(1000),
      }),
      setDoc(doc(db, 'tesoreria_apoderados/cuenta-a'), {
        apoderado_uid: 'padre-a', cuota_mensual: 5000, monto_deuda: 5000,
        aviso_activo: false, mensaje_aviso: '',
      }),
      setDoc(doc(db, 'tesoreria_movimientos/cargo-a'), {apoderado_id: 'cuenta-a', monto: 5000}),
      setDoc(doc(db, 'tesoreria_pagos/pago-a'), {apoderado_id: 'cuenta-a', monto: 1000}),
      setDoc(doc(db, 'tesoreria_notificaciones/recibo-a'), {comprobante_id: 'recibo-a', estado: 'pendiente'}),
      setDoc(doc(db, 'tesoreria_comprobantes_huellas_v58/hash-a'), {comprobante_id: 'recibo-a', estado: 'pendiente'}),
      setDoc(doc(db, 'tesoreria_procesos_v58/job-a'), {cuenta_id: 'cuenta-a', estado: 'completado'}),
      setDoc(doc(db, 'configuracion_tesoreria/automatizacion_v58'), {habilitada: false}),
    ]);
  });
});

after(async () => { if (env) await env.cleanup(); });

function db(uid) { return uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore(); }
function storage(uid) { return uid ? env.authenticatedContext(uid).storage() : env.unauthenticatedContext().storage(); }

test('recibos: propietario consulta los suyos; otro padre y público no pueden leer/listar', async () => {
  await assertSucceeds(getDoc(doc(db('padre-a'), 'comprobantes_pago/recibo-a')));
  await assertFails(getDoc(doc(db('padre-b'), 'comprobantes_pago/recibo-a')));
  await assertFails(getDoc(doc(db(), 'comprobantes_pago/recibo-a')));
  const own = await assertSucceeds(getDocs(query(collection(db('padre-a'), 'comprobantes_pago'), where('uid', '==', 'padre-a'))));
  assert.equal(own.size, 1);
  await assertFails(getDocs(collection(db('padre-a'), 'comprobantes_pago')));
  await assertFails(getDocs(collection(db(), 'comprobantes_pago')));
});

test('Tesorería/admin/multirrol ven pendientes; tesorero desactivado no', async () => {
  for (const uid of ['tesorero', 'admin', 'multirrol']) {
    const result = await assertSucceeds(getDocs(query(collection(db(uid), 'comprobantes_pago'), where('estado', '==', 'pendiente'))));
    assert.equal(result.size, 2);
    await assertSucceeds(getDoc(doc(db(uid), 'tesoreria_notificaciones/recibo-a')));
  }
  await assertFails(getDoc(doc(db('tesorero-inactivo'), 'comprobantes_pago/recibo-a')));
  await assertFails(getDoc(doc(db('padre-a'), 'tesoreria_notificaciones/recibo-a')));
});

test('roles: Coordinación, correos especiales y claims cliente no conceden Tesorería', async () => {
  for (const uid of ['coordinador', 'rol-malformado', 'sin-perfil']) {
    await assertFails(getDoc(doc(db(uid), 'comprobantes_pago/recibo-a')));
    await assertFails(getDoc(doc(db(uid), 'tesoreria_apoderados/cuenta-a')));
  }
  const forged = env.authenticatedContext('padre-b', {
    email: 'admin@autismorancagua.cl', rol: 'admin_general', roles: ['tesoreria'],
  }).firestore();
  await assertFails(getDoc(doc(forged, 'comprobantes_pago/recibo-a')));
  await assertFails(getDoc(doc(forged, 'tesoreria_notificaciones/recibo-a')));
});

test('recibos: ningún cliente puede crear, aprobar, rechazar, cambiar propietario o borrar', async () => {
  for (const uid of ['padre-a', 'tesorero', 'admin']) {
    await assertFails(setDoc(doc(db(uid), 'comprobantes_pago/nuevo'), {uid, estado: 'pendiente', monto: 1}));
    for (const change of [{estado: 'aprobado'}, {estado: 'rechazado'}, {uid: 'padre-b'}, {monto: -10}, {extra: 'x'.repeat(100000)}]) {
      await assertFails(updateDoc(doc(db(uid), 'comprobantes_pago/recibo-a'), change));
    }
    await assertFails(deleteDoc(doc(db(uid), 'comprobantes_pago/recibo-a')));
  }
});

test('asientos/pagos/notificaciones: cliente no puede fabricar ni repetir descuentos', async () => {
  for (const collectionName of ['tesoreria_movimientos', 'tesoreria_pagos', 'tesoreria_notificaciones', 'tesoreria_auditoria']) {
    for (const uid of ['padre-a', 'tesorero']) {
      await assertFails(setDoc(doc(db(uid), collectionName, 'falso'), {monto: 99999999, uid}));
    }
  }
  await assertSucceeds(getDoc(doc(db('tesorero'), 'tesoreria_pagos/pago-a')));
  await assertFails(getDoc(doc(db('padre-b'), 'tesoreria_pagos/pago-a')));
});

test('huellas: ningún cliente lee, falsifica, actualiza ni libera reservas de imagen', async () => {
  for (const uid of ['padre-a', 'tesorero', 'admin']) {
    await assertFails(getDoc(doc(db(uid), 'tesoreria_comprobantes_huellas_v58/hash-a')));
    await assertFails(setDoc(doc(db(uid), 'tesoreria_comprobantes_huellas_v58/falso'), {comprobante_id: 'recibo-a', estado: 'rechazado'}));
    await assertFails(updateDoc(doc(db(uid), 'tesoreria_comprobantes_huellas_v58/hash-a'), {estado: 'rechazado'}));
    await assertFails(deleteDoc(doc(db(uid), 'tesoreria_comprobantes_huellas_v58/hash-a')));
  }
});

test('procesos/config: solo staff lee; ningún cliente habilita automatización ni altera resultados', async () => {
  for (const collectionPath of ['tesoreria_procesos_v58/job-a', 'configuracion_tesoreria/automatizacion_v58']) {
    await assertSucceeds(getDoc(doc(db('tesorero'), collectionPath)));
    await assertSucceeds(getDoc(doc(db('admin'), collectionPath)));
    await assertFails(getDoc(doc(db('padre-a'), collectionPath)));
    await assertFails(getDoc(doc(db(), collectionPath)));
    for (const uid of ['padre-a', 'tesorero', 'admin']) {
      await assertFails(setDoc(doc(db(uid), collectionPath), {habilitada: true}));
      await assertFails(updateDoc(doc(db(uid), collectionPath), {habilitada: true}));
      await assertFails(deleteDoc(doc(db(uid), collectionPath)));
    }
  }
  await env.withSecurityRulesDisabled(async context => {
    await deleteDoc(doc(context.firestore(), 'configuracion_tesoreria/automatizacion_v58'));
  });
  for (const uid of ['padre-a', 'tesorero', 'admin']) {
    await assertFails(setDoc(doc(db(uid), 'configuracion_tesoreria/automatizacion_v58'), {habilitada: true}));
    await assertFails(setDoc(doc(db(uid), 'tesoreria_procesos_v58/job-nuevo'), {estado: 'completado'}));
  }
});

test('auditoría manual V57: staff firma solo ingresos propios; no suplanta revisión V58', async () => {
  const valid = {
    accion: 'registrar_ingreso_institucional', detalle: 'Ingreso de reciclaje',
    usuario_uid: 'tesorero', usuario_email: '', fecha: serverTimestamp(),
    extra: {concepto: 'reciclaje', monto: 1000, detalle: 'Entrega', cuenta_destino: 'CUENTA CORRIENTE'},
  };
  await assertSucceeds(setDoc(doc(db('tesorero'), 'tesoreria_auditoria/manual'), valid));
  for (const changes of [
    {accion: 'aprobar_comprobante'}, {usuario_uid: 'admin'},
    {usuario_email: 'otra@example.test'}, {detalle: 'x'.repeat(2001)},
    {extra: {monto: -1}}, {extra: {monto: '1000'}}, {extra: {concepto: 'x'.repeat(121)}},
    {extra: {arbitrario: true}}, {fecha: Timestamp.fromMillis(0)},
  ]) await assertFails(setDoc(doc(db('tesorero'), 'tesoreria_auditoria/falso'), {...valid, ...changes}));
  await assertFails(setDoc(doc(db('padre-a'), 'tesoreria_auditoria/manual-padre'), {...valid, usuario_uid: 'padre-a'}));
  await assertFails(updateDoc(doc(db('tesorero'), 'tesoreria_auditoria/manual'), {detalle: 'reescrito'}));
  await assertFails(deleteDoc(doc(db('tesorero'), 'tesoreria_auditoria/manual')));
});

test('avisos: query por UID y actualización de lectura propia funcionan', async () => {
  const own = await assertSucceeds(getDocs(query(collection(db('padre-a'), 'avisos_apoderados'), where('apoderado_id', '==', 'padre-a'))));
  assert.equal(own.size, 1);
  await assertSucceeds(updateDoc(doc(db('padre-a'), 'avisos_apoderados/aviso-a'), {
    leido: true, aceptado: true, fecha_lectura: serverTimestamp(),
  }));
});

test('avisos: permite lectura y aceptación independientes sin exigir flags ajenos ni fecha nueva', async () => {
  const aviso = doc(db('padre-a'), 'avisos_apoderados/aviso-a');
  await assertSucceeds(updateDoc(aviso, {leido: true}));
  assert.equal((await getDoc(aviso)).data().aceptado, false);
  await assertSucceeds(updateDoc(aviso, {aceptado: true}));
  // Un timestamp de lectura anterior no bloquea la aceptación posterior.
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'avisos_apoderados/aviso-a'), {
      aceptado: false, fecha_lectura: Timestamp.fromMillis(1000),
    });
  });
  await assertSucceeds(updateDoc(aviso, {aceptado: true}));
  await assertFails(updateDoc(aviso, {leido: false}));
  await assertFails(updateDoc(aviso, {aceptado: false}));
});

test('avisos: merge, reemplazo y deleteField no permiten borrar flags, fecha o contenido', async () => {
  const aviso = doc(db('padre-a'), 'avisos_apoderados/aviso-a');
  for (const field of ['leido', 'aceptado', 'mensaje', 'apoderado_id']) {
    await assertFails(updateDoc(aviso, {[field]: deleteField(), fecha_lectura: serverTimestamp()}));
  }
  await assertFails(setDoc(aviso, {apoderado_id: 'padre-a', leido: true}));
  await assertFails(setDoc(aviso, {leido: true, apoderado_id: 'padre-b'}, {merge: true}));
  await assertSucceeds(updateDoc(aviso, {leido: true, fecha_lectura: serverTimestamp()}));
  await assertFails(updateDoc(aviso, {fecha_lectura: deleteField(), aceptado: true}));
});

test('avisos: propiedad, contenido, esquema y fecha de lectura están protegidos', async () => {
  await assertFails(getDoc(doc(db('padre-b'), 'avisos_apoderados/aviso-a')));
  await assertFails(updateDoc(doc(db('padre-b'), 'avisos_apoderados/aviso-a'), {leido: true}));
  for (const change of [
    {apoderado_id: 'padre-b'}, {mensaje: 'cambiar deuda'}, {leido: 'true'},
    {leido: false}, {aceptado: 1}, {extra: true},
    {fecha_lectura: 'ayer'}, {fecha_lectura: Timestamp.fromMillis(0)},
    {fecha_lectura: Timestamp.fromMillis(Date.now() + 3600000)},
  ]) await assertFails(updateDoc(doc(db('padre-a'), 'avisos_apoderados/aviso-a'), change));
  await assertFails(deleteDoc(doc(db('padre-a'), 'avisos_apoderados/aviso-a')));
  await assertFails(setDoc(doc(db('padre-a'), 'avisos_apoderados/nuevo'), {apoderado_id: 'padre-a', leido: true}));
});

test('ficha: Tesorería edita cuota/aviso pero no saldo ni vínculo; padre no edita deuda', async () => {
  await assertSucceeds(getDoc(doc(db('padre-a'), 'tesoreria_apoderados/cuenta-a')));
  await assertFails(getDoc(doc(db('padre-b'), 'tesoreria_apoderados/cuenta-a')));
  await assertSucceeds(updateDoc(doc(db('tesorero'), 'tesoreria_apoderados/cuenta-a'), {
    cuota_mensual: 6000, aviso_activo: true, mensaje_aviso: 'Pendiente', actualizado: serverTimestamp(),
  }));
  for (const change of [
    {monto_deuda: 0}, {apoderado_uid: 'padre-b'}, {apoderados_uids_autorizados: ['padre-b']},
    {cuota_mensual: -1}, {cuota_mensual: 1.5}, {cuota_mensual: '5000'},
    {mensaje_aviso: 'x'.repeat(2001)}, {aviso_activo: 'sí'}, {extra: true},
  ]) await assertFails(updateDoc(doc(db('tesorero'), 'tesoreria_apoderados/cuenta-a'), change));
  await assertFails(updateDoc(doc(db('padre-a'), 'tesoreria_apoderados/cuenta-a'), {monto_deuda: 0}));
});

test('ficha: propietario marca enterado sin cambiar aviso, saldo ni otro campo', async () => {
  const valid = {aviso_visto_por_apoderado: true, fecha_lectura_aviso: serverTimestamp()};
  await assertSucceeds(updateDoc(doc(db('padre-a'), 'tesoreria_apoderados/cuenta-a'), valid));
  await assertFails(updateDoc(doc(db('padre-b'), 'tesoreria_apoderados/cuenta-a'), valid));
  for (const changes of [
    {aviso_visto_por_apoderado: false}, {fecha_lectura_aviso: 'hoy'},
    {fecha_lectura_aviso: Timestamp.fromMillis(0)}, {monto_deuda: 0},
    {aviso_activo: false}, {mensaje_aviso: 'Borrado'}, {extra: true},
  ]) await assertFails(updateDoc(doc(db('padre-a'), 'tesoreria_apoderados/cuenta-a'), {...valid, ...changes}));
});

test('ficha: ACL válida da acceso solo a esa cuenta; propietario y staff no pueden ampliar vínculos', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'tesoreria_apoderados/cuenta-b'), {
      apoderado_uid: 'padre-b', apoderados_uids_autorizados: ['apoyo-autorizado'],
      cuota_mensual: 4000, monto_deuda: 4000,
    });
  });
  await assertSucceeds(getDoc(doc(db('apoyo-autorizado'), 'tesoreria_apoderados/cuenta-b')));
  await assertFails(getDoc(doc(db('apoyo-autorizado'), 'tesoreria_apoderados/cuenta-a')));
  await assertFails(getDocs(collection(db('apoyo-autorizado'), 'tesoreria_apoderados')));
  for (const uid of ['padre-b', 'apoyo-autorizado', 'tesorero', 'admin']) {
    const ficha = doc(db(uid), 'tesoreria_apoderados/cuenta-b');
    for (const change of [
      {apoderado_uid: 'padre-a'}, {uid_apoderado: 'padre-a'}, {uid: 'padre-a'},
      {apoderados_uids_autorizados: ['padre-a']}, {monto_deuda: 0},
      {apoderados_uids_autorizados: deleteField()},
    ]) await assertFails(updateDoc(ficha, change));
    await assertFails(setDoc(ficha, {cuota_mensual: 1}));
  }
});

test('roles: no hay autoescalamiento ni exposición de perfil ajeno', async () => {
  await assertSucceeds(getDoc(doc(db('padre-a'), 'usuarios/padre-a')));
  await assertFails(getDoc(doc(db('padre-b'), 'usuarios/padre-a')));
  await assertFails(updateDoc(doc(db('padre-a'), 'usuarios/padre-a'), {rol: 'tesoreria'}));
  await assertFails(updateDoc(doc(db('padre-a'), 'usuarios/padre-a'), {roles: ['admin_general']}));
  await assertFails(setDoc(doc(db('padre-a'), 'usuarios/nuevo-admin'), {rol: 'admin_general'}));
});

test('Storage: imagen propia create-only, lectura propia/Tesorería, privada a terceros', async () => {
  const ownRef = ref(storage('padre-a'), `comprobantes_v58/padre-a/${FILE}`);
  await assertSucceeds(uploadBytes(ownRef, IMAGE, {contentType: 'image/png'}));
  assert.equal((await assertSucceeds(getBytes(ownRef))).byteLength, IMAGE.byteLength);
  await assertSucceeds(getBytes(ref(storage('tesorero'), `comprobantes_v58/padre-a/${FILE}`)));
  await assertFails(getBytes(ref(storage('padre-b'), `comprobantes_v58/padre-a/${FILE}`)));
  await assertFails(getBytes(ref(storage(), `comprobantes_v58/padre-a/${FILE}`)));
  await assertFails(getBytes(ref(storage('tesorero-inactivo'), `comprobantes_v58/padre-a/${FILE}`)));
  await assertFails(uploadBytes(ownRef, IMAGE, {contentType: 'image/png'}));
  await assertFails(updateMetadata(ownRef, {contentType: 'image/jpeg'}));
  await assertFails(deleteObject(ownRef));
});

test('Storage: deniega propietario falso, ruta, MIME, extensión, cero bytes y exceso de tamaño', async () => {
  await assertFails(uploadBytes(ref(storage('padre-b'), `comprobantes_v58/padre-a/${FILE}`), IMAGE, {contentType: 'image/png'}));
  await assertFails(uploadBytes(ref(storage(), `comprobantes_v58/padre-a/${FILE}`), IMAGE, {contentType: 'image/png'}));
  for (const [name, bytes, type] of [
    ['short.png', IMAGE, 'image/png'],
    ['0123456789abcdefghij.svg', IMAGE, 'image/svg+xml'],
    ['0123456789abcdefghij.jpg', IMAGE, 'image/png'],
    [FILE, IMAGE, 'application/octet-stream'],
    [FILE, new Uint8Array(0), 'image/png'],
    [FILE, new Uint8Array(10 * 1024 * 1024 + 1), 'image/png'],
  ]) await assertFails(uploadBytes(ref(storage('padre-a'), `comprobantes_v58/padre-a/${name}`), bytes, {contentType: type}));
  await assertFails(uploadBytes(ref(storage('padre-a'), `comprobantes_v58/padre-a/nested/${FILE}`), IMAGE, {contentType: 'image/png'}));
});
