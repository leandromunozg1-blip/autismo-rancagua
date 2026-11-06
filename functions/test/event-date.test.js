'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {MemoryFirestore} = require('./helpers/memory-firestore');
const {createTreasuryService} = require('../src/service');

test('Evento explícito sin vencimiento puede abonarse y nunca genera cobranza automática', async () => {
  const path = 'tesoreria_evento_cargos/actividad';
  const db = new MemoryFirestore({
    'usuarios/tesorero': {rol: 'tesoreria'},
    'tesoreria_apoderados/beneficiario': {apoderado_uid: 'padre', estado_terapias: 'activo'},
    [path]: {apoderado_id: 'beneficiario', monto: 5000, estado: 'pendiente', evento_id: 'evento-2026'},
  });
  const bucket = {file: () => ({getMetadata: async () => [{size: '100', contentType: 'image/jpeg', generation: '3', md5Hash: 'dGVzdC1pbWFnZQ=='}]})};
  const service = createTreasuryService({db, bucket, now: () => new Date('2026-12-01T12:00:00Z')});
  const request = {auth: {uid: 'padre'}, data: {cuentaId: 'beneficiario', cargoId: path, monto: 1500,
    solicitudId: 'event-without-date', storagePath: 'comprobantes_v58/padre/event-without-date.jpg'}};
  const receipt = await service.enviarComprobante(request);
  await service.revisarComprobante({auth: {uid: 'tesorero'}, data: {comprobanteId: receipt.comprobanteId, decision: 'aprobado'}});
  const book = await service.consultar({auth: {uid: 'padre'}, data: {cuentaId: 'beneficiario'}});
  assert.equal(book.cargos[0].sin_vencimiento, true);
  assert.equal(book.cargos[0].pagado, 1500);
  assert.equal(book.cargos[0].saldo, 3500);
  assert.equal(book.resumen.saldoVencido, 0);
  assert.deepEqual(book.advertencias, []);
  assert.equal(db.data(path).estado, 'abono');
  const before = db.paths('avisos_apoderados').length;
  const outcome = await service.avisarCuenta('beneficiario', 'aviso_cobranza', '2026-12-01', '2026-12', new Date('2026-12-01T12:00:00Z'));
  assert.equal(outcome.estado, 'sin_saldo');
  assert.equal(db.paths('avisos_apoderados').length, before);
});
