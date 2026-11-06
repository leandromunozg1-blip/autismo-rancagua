'use strict';

// Creates fictitious demo records only, without deleting or replacing existing
// application records. Must NEVER be used with a live Firebase project.
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const D = require('../src/domain');
const PROJECT = 'demo-autismo-rancagua-v58';

function validateDemoEnvironment(env) {
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    assert.match(env[key] || '', /^(127[.]0[.]0[.]1|localhost):\d+$/,
      `${key} debe apuntar a un emulador local. Se aborta sin escribir.`);
  }
  for (const key of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
    if (env[key]) assert.equal(env[key], PROJECT, `${key} no es el proyecto DEMO.`);
  }
  if (env.FIREBASE_CONFIG) {
    let config;
    try { config = JSON.parse(env.FIREBASE_CONFIG); }
    catch { throw new Error('FIREBASE_CONFIG debe ser JSON DEMO explícito o estar ausente.'); }
    if (config.projectId) assert.equal(config.projectId, PROJECT, 'Configuración Firebase real no permitida.');
  }
}

async function seed() {
  validateDemoEnvironment(process.env);
  const demoPassword = process.env.V58_DEMO_PASSWORD;
  assert.ok(typeof demoPassword === 'string' && demoPassword.length >= 12,
    'Define V58_DEMO_PASSWORD localmente con al menos 12 caracteres. No se almacena en Git.');
  const app = initializeApp({projectId: PROJECT}, 'seed-v58-demo');
  const db = getFirestore(app), auth = getAuth(app);
  const now = new Date(), today = D.chileDate(now), periodo = today.slice(0, 7);
  const timestamp = Timestamp.fromDate(now);
  const users = [
    {uid: 'demo-v58-apoderado', email: 'apoderado.v58@example.test', nombre: 'Apoderado de pruebas V58', rol: 'apoderado'},
    {uid: 'demo-v58-tesoreria', email: 'tesoreria.v58@example.test', nombre: 'Tesorería de pruebas V58', rol: 'tesoreria'},
  ];
  async function createIfMissing(path, data) {
    const ref = db.doc(path);
    await db.runTransaction(async tx => {
      if ((await tx.get(ref)).exists) return;
      tx.create(ref, {...data, datos_ficticios_v58: true});
    });
  }
  try {
    for (const user of users) {
      try {
        const existing = await auth.getUser(user.uid);
        assert.equal(existing.email, user.email, 'UID DEMO existente con otro correo: no se modifica.');
      } catch (e) {
        if (e.code !== 'auth/user-not-found') throw e;
        await auth.createUser({uid: user.uid, email: user.email, password: demoPassword, emailVerified: true, displayName: user.nombre});
      }
      await createIfMissing(`usuarios/${user.uid}`, {...user, roles: [user.rol], activo: true});
    }
    await createIfMissing('tesoreria_apoderados/demo-v58-beneficiario', {
      uid: 'demo-v58-beneficiario', apoderado_uid: users[0].uid,
      apoderados_uids_autorizados: [users[0].uid], nombre: 'Beneficiario ficticio V58',
      nombre_usuario: 'Beneficiario ficticio V58', nombre_apoderado: users[0].nombre,
      email: users[0].email, cuota_mensual: 5000, estado_terapias: 'activo',
      monto_deuda: 13000, version_contable: 58, aviso_activo: false, mensaje_aviso: '',
    });
    await createIfMissing('tesoreria_movimientos/demo-v58-cuota', {
      cuenta_id: 'demo-v58-beneficiario', apoderado_id: 'demo-v58-beneficiario',
      tipo: 'cargo_mensual', concepto: 'Mensualidad ficticia de pruebas', mes: periodo, periodo,
      monto: 5000, monto_pagado: 0, saldo_pendiente: 5000, estado: 'pendiente',
      vence_el: D.lastDay(D.previousPeriod(periodo)), fecha: timestamp, version: 58,
    });
    await createIfMissing('tesoreria_evento_cargos/demo-v58-evento', {
      cuenta_id: 'demo-v58-beneficiario', apoderado_id: 'demo-v58-beneficiario',
      evento_id: 'demo-v58-actividad', evento_titulo: 'Actividad ficticia de pruebas',
      monto: 8000, monto_pagado: 0, saldo_pendiente: 8000, estado: 'pendiente',
      vence_el: today, fecha: timestamp,
    });
    // Enforce the user's prohibition: demo setup never enables scheduled charges.
    await db.doc('configuracion_tesoreria/automatizacion_v58').set({habilitada: false, datos_ficticios_v58: true});
    console.log('Datos ficticios preparados exclusivamente en', PROJECT);
    console.log('Apoderado: apoderado.v58@example.test');
    console.log('Tesorería: tesoreria.v58@example.test');
    console.log('Contraseña DEMO: la definida localmente en V58_DEMO_PASSWORD (no se muestra).');
    console.log('Automatización: DESACTIVADA. No se han borrado registros.');
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
}

module.exports = {validateDemoEnvironment};
if (require.main === module) seed().catch(error => { console.error(error.message); process.exitCode = 1; });
