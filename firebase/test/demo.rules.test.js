'use strict';

const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, collection, updateDoc, query, where} = require('firebase/firestore');

const PROJECT = 'demo-autismo-rancagua-v58';
const LEGACY_READS = [
  'tesoreria_eventos', 'tesoreria_evento_cargos', 'tesoreria_ingresos_institucionales',
  'tesoreria_gestiones_cobranza', 'aseo_reemplazos', 'ar_asignaciones_mensuales',
];
let env;

before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127[.]0[.]0[.]1|localhost):\d+$/);
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: fs.readFileSync(path.join(__dirname, '../demo.firestore.rules'), 'utf8')},
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    const records = {
      'usuarios/padre-demo': {rol: 'apoderado', activo: true},
      'usuarios/otro-padre': {rol: 'apoderado', activo: true},
      'usuarios/staff-demo': {rol: 'tesoreria', activo: true},
      'usuarios/inactivo': {rol: 'tesoreria', activo: false},
      'tesoreria_apoderados/cuenta-demo': {apoderado_uid: 'padre-demo', cuota_mensual: 5000, monto_deuda: 5000},
      'comprobantes_pago/recibo-demo': {uid: 'padre-demo', estado: 'pendiente', monto: 1000},
      'tesoreria_notificaciones/recibo-demo': {comprobante_id: 'recibo-demo', estado: 'pendiente'},
      'configuracion_tesoreria/automatizacion_v58': {habilitada: false},
      'ar_beneficiarios/ficticio': {apoderado_uid: 'padre-demo', nombre: 'Beneficiario ficticio'},
    };
    for (const name of LEGACY_READS) records[`${name}/ficticio`] = {monto: 1000};
    await Promise.all(Object.entries(records).map(([name, value]) => setDoc(doc(db, name), value)));
  });
});
after(async () => { if (env) await env.cleanup(); });
const db = (uid, token) => uid ? env.authenticatedContext(uid, token).firestore() : env.unauthenticatedContext().firestore();

test('demo: login lee su perfil provisionado y no enumera ni edita roles', async () => {
  await assertSucceeds(getDoc(doc(db('padre-demo'), 'usuarios/padre-demo')));
  await assertSucceeds(getDoc(doc(db('staff-demo'), 'usuarios/staff-demo')));
  await assertFails(getDoc(doc(db('padre-demo'), 'usuarios/staff-demo')));
  await assertFails(getDocs(collection(db('staff-demo'), 'usuarios')));
  await assertFails(updateDoc(doc(db('padre-demo'), 'usuarios/padre-demo'), {rol: 'admin_general'}));
  await assertFails(setDoc(doc(db('sin-perfil'), 'usuarios/sin-perfil'), {rol: 'tesoreria'}));
});

test('demo: propietario ve sus comprobantes y ficha; staff ve bandeja; terceros no', async () => {
  await assertSucceeds(getDoc(doc(db('padre-demo'), 'tesoreria_apoderados/cuenta-demo')));
  await assertSucceeds(getDocs(query(collection(db('padre-demo'), 'comprobantes_pago'), where('uid', '==', 'padre-demo'))));
  await assertSucceeds(getDocs(collection(db('staff-demo'), 'comprobantes_pago')));
  await assertSucceeds(getDoc(doc(db('staff-demo'), 'tesoreria_notificaciones/recibo-demo')));
  for (const uid of ['otro-padre', 'inactivo', null]) {
    await assertFails(getDoc(doc(db(uid), 'tesoreria_apoderados/cuenta-demo')));
    await assertFails(getDoc(doc(db(uid), 'comprobantes_pago/recibo-demo')));
  }
});

test('demo: pestañas V57 tienen lectura staff acotada sin concesión a otros roles', async () => {
  for (const name of LEGACY_READS) {
    await assertSucceeds(getDocs(collection(db('staff-demo'), name)));
    await assertFails(getDocs(collection(db('padre-demo'), name)));
    await assertFails(getDoc(doc(db('inactivo'), name, 'ficticio')));
    await assertFails(getDoc(doc(db(), name, 'ficticio')));
    await assertFails(setDoc(doc(db('staff-demo'), name, 'nuevo'), {monto: 1}));
    await assertFails(updateDoc(doc(db('staff-demo'), name, 'ficticio'), {monto: 0}));
  }
});

test('demo: otros módulos no reciben permiso global sobre información personal', async () => {
  for (const uid of ['padre-demo', 'staff-demo']) {
    await assertFails(getDocs(collection(db(uid), 'ar_beneficiarios')));
    await assertFails(getDoc(doc(db(uid), 'ar_beneficiarios/ficticio')));
    await assertFails(setDoc(doc(db(uid), 'ar_bitacora_casa/nueva'), {mensaje: 'ficticio'}));
  }
});

test('demo: exige token del proyecto demo y roles del perfil, nunca email ni claim de rol', async () => {
  await assertFails(getDoc(doc(db('staff-demo', {aud: 'autismo-rancagua-real'}), 'comprobantes_pago/recibo-demo')));
  const forged = db('otro-padre', {email: 'admin@autismorancagua.cl', rol: 'tesoreria', roles: ['admin_general']});
  await assertFails(getDoc(doc(forged, 'tesoreria_notificaciones/recibo-demo')));
});

test('demo: ni staff ni propietario activan automatización o escriben aprobación/saldo/ACL', async () => {
  for (const uid of ['padre-demo', 'staff-demo']) {
    const firestore = db(uid);
    await assertFails(updateDoc(doc(firestore, 'configuracion_tesoreria/automatizacion_v58'), {habilitada: true}));
    await assertFails(updateDoc(doc(firestore, 'comprobantes_pago/recibo-demo'), {estado: 'aprobado'}));
    await assertFails(updateDoc(doc(firestore, 'tesoreria_apoderados/cuenta-demo'), {monto_deuda: 0}));
    await assertFails(updateDoc(doc(firestore, 'tesoreria_apoderados/cuenta-demo'), {apoderados_uids_autorizados: ['otro-padre']}));
  }
});
