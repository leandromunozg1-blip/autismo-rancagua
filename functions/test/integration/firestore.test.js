'use strict';
// Requires a local demo Firestore emulator. Fails closed without it.
const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {createTreasuryService} = require('../../src/service');
const PROJECT = 'demo-autismo-rancagua-v58';
let app, db, service;
const asParent = data => ({auth: {uid: 'padre-emulator', token: {}}, data});
const asStaff = data => ({auth: {uid: 'tesorero-emulator', token: {email: 'test@example.test'}}, data});
const CARGO = 'tesoreria_movimientos/cargo-emulator';

before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127[.]0[.]0[.]1|localhost):\d+$/,
    'Refusing any connection outside local Firestore emulator');
  app = initializeApp({projectId: PROJECT}, 'tesoreria-integration-test');
  db = getFirestore(app);
  const bucket = {file: path => ({getMetadata: async () => [{size: '100', contentType: 'image/jpeg', generation: '1', md5Hash: Buffer.from(path).toString('base64')}]})};
  service = createTreasuryService({db, bucket, now: () => new Date('2026-12-01T12:00:00Z')});
});
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {method: 'DELETE'});
  assert.ok(response.ok);
  await Promise.all([
    db.doc('usuarios/tesorero-emulator').set({rol: 'tesoreria'}),
    db.doc('tesoreria_apoderados/beneficiario-emulator').set({apoderado_uid: 'padre-emulator', cuota_mensual: 5000, estado_terapias: 'activo'}),
    db.doc(CARGO).set({apoderado_id: 'beneficiario-emulator', tipo: 'cargo_mensual', periodo: '2026-12', monto: 5000, estado: 'pendiente'}),
  ]);
});
after(async () => { if (db) await db.terminate(); if (app) await deleteApp(app); });
async function receipt(solicitudId, monto) {
  return (await service.enviarComprobante(asParent({cuentaId: 'beneficiario-emulator', cargoId: CARGO,
    monto, solicitudId, storagePath: `comprobantes_v58/padre-emulator/${solicitudId}.jpg`}))).comprobanteId;
}
const approve = id => service.revisarComprobante(asStaff({comprobanteId: id, decision: 'aprobado'}));

test('Firestore real: carreras de aprobación del mismo comprobante producen un único asiento', async () => {
  const id = await receipt('abcdefghijklmnopqrst', 1500);
  await Promise.all([approve(id), approve(id)]);
  assert.equal((await db.collection('tesoreria_pagos').get()).size, 1);
  assert.equal((await db.doc(CARGO).get()).data().saldo_pendiente, 3500);
  const result = await service.consultar(asParent({cuentaId: 'beneficiario-emulator'}));
  assert.equal(result.resumen.deuda, 3500);
  assert.equal(result.resumen.saldoVencido, 3500);
});

test('Firestore real: cuentas serializan dos abonos competidores sin sobrepago', async () => {
  const a = await receipt('abcdefghijklmnopqrst', 3500);
  const b = await receipt('uvwxyzABCDEFGHIJKLMN', 3500);
  const results = await Promise.allSettled([approve(a), approve(b)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await db.collection('tesoreria_pagos').get()).size, 1);
  assert.equal((await db.doc(CARGO).get()).data().saldo_pendiente, 1500);
  const states = (await db.collection('comprobantes_pago').get()).docs.map(x => x.data().estado).sort();
  assert.deepEqual(states, ['aprobado', 'pendiente']);
});

test('Firestore real: revisión inválida revierte estado, pago y auditoría', async () => {
  await db.doc('comprobantes_pago/legacy').set({uid: 'otro', monto: 1000, estado: 'pendiente'});
  await assert.rejects(service.revisarComprobante(asStaff({comprobanteId: 'legacy', decision: 'aprobado', cuentaId: 'beneficiario-emulator', cargoId: CARGO})), {code: 'failed-precondition'});
  assert.equal((await db.doc('comprobantes_pago/legacy').get()).data().estado, 'pendiente');
  assert.equal((await db.collection('tesoreria_pagos').get()).size, 0);
  assert.equal((await db.collection('tesoreria_auditoria').get()).size, 0);
});
