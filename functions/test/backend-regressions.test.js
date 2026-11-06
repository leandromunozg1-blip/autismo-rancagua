'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {MemoryFirestore} = require('./helpers/memory-firestore');
const {createTreasuryService} = require('../src/service');
const D = require('../src/domain');

function legacyFixture(payment) {
  const db = new MemoryFirestore({
    'tesoreria_apoderados/padre': {apoderado_uid: 'padre'},
    'tesoreria_apoderados/beneficiario-b': {apoderado_uid: 'padre'},
    'tesoreria_movimientos/cargo-a': {apoderado_id: 'padre', tipo: 'cargo_mensual', periodo: '2026-12', monto: 5000},
    'tesoreria_movimientos/cargo-b': {apoderado_id: 'beneficiario-b', tipo: 'cargo_mensual', periodo: '2026-12', monto: 5000},
    'tesoreria_pagos/historico': {uid: 'padre', estado: 'aprobado', monto: 1000, periodo: '2026-12', ...payment},
  });
  const service = createTreasuryService({db, now: () => new Date('2026-11-20T12:00:00Z')});
  return {db, service};
}
const request = cuentaId => ({auth: {uid: 'padre'}, data: {cuentaId}});

test('referencias legacy de otro beneficiario prevalecen sobre uid coincidente con ID de cuenta', async () => {
  for (const field of ['apoderado_id', 'beneficiario_id', 'rut_usuario']) {
    const {service} = legacyFixture({[field]: 'beneficiario-b'});
    const a = await service.consultar(request('padre'));
    const b = await service.consultar(request('beneficiario-b'));
    assert.equal(a.resumen.pagos, 0, field);
    assert.equal(a.resumen.deuda, 5000, field);
    assert.equal(b.resumen.pagos, 1000, field);
    assert.equal(b.resumen.deuda, 4000, field);
  }
});

test('UID de apoderado con varias cuentas no imputa pago aunque una cuenta use ese UID como ID', async () => {
  const {service} = legacyFixture();
  for (const id of ['padre', 'beneficiario-b']) {
    const result = await service.consultar(request(id));
    assert.equal(result.resumen.pagos, 0, id);
    assert.equal(result.resumen.deuda, 5000, id);
    assert.equal(result.resumen.deudaNoConciliada, true, id);
  }
});

test('UID legacy inequívoco conserva el pago cuando solo existe una cuenta del apoderado', async () => {
  const {db, service} = legacyFixture();
  db.docs.delete('tesoreria_apoderados/beneficiario-b');
  const result = await service.consultar(request('padre'));
  assert.equal(result.resumen.pagos, 1000);
  assert.equal(result.resumen.deuda, 4000);
  assert.equal(result.resumen.deudaNoConciliada, false);
});

test('pendiente_revision V58 exige imagen existente antes de aprobar, igual que pendiente', async () => {
  const db = new MemoryFirestore({
    'usuarios/tesorero': {rol: 'tesoreria'},
    'tesoreria_apoderados/beneficiario': {apoderado_uid: 'padre'},
    'tesoreria_movimientos/cargo': {apoderado_id: 'beneficiario', tipo: 'cargo_mensual', periodo: '2026-12', monto: 5000},
    'comprobantes_pago/restaurado': {version: 58, uid: 'padre', estado: 'pendiente_revision', monto: 1000,
      cuenta_id: 'beneficiario', cargo_id: 'tesoreria_movimientos/cargo', solicitud_id: 'abcdefghijklmnop',
      storage_path: 'comprobantes_v58/padre/abcdefghijklmnop.jpg', storage_generation: '7', imagen_huella: 'huella'},
    'tesoreria_comprobantes_huellas_v58/huella': {comprobante_id: 'restaurado', estado: 'pendiente'},
  });
  const bucket = {file: () => ({getMetadata: async () => { throw Object.assign(new Error('missing'), {code: 404}); }})};
  const service = createTreasuryService({db, bucket});
  await assert.rejects(service.revisarComprobante({auth: {uid: 'tesorero'}, data: {
    comprobanteId: 'restaurado', decision: 'aprobado',
  }}), {code: 'failed-precondition'});
  assert.equal(db.data('comprobantes_pago/restaurado').estado, 'pendiente_revision');
  assert.equal(db.paths('tesoreria_pagos').length, 0);
});

test('vencimientos con fechas imposibles bloquean cobro automático sin normalizar el día', () => {
  for (const date of ['2026-02-31', '2026-13-01', '2026-11-00']) {
    assert.equal(D.dateString(date), null, date);
    const book = D.calcularLibro({movimientos: [{id: 'cargo', data: {
      tipo: 'cargo_mensual', periodo: '2026-12', monto: 5000, vence_el: date,
    }}], ahora: new Date('2026-12-01T12:00:00Z')});
    assert.equal(book.resumen.deudaNoConciliada, true, date);
    assert.equal(book.cargos[0].vence_el, null, date);
    assert.equal(book.resumen.saldoVencido, 0, date);
  }
  assert.equal(D.dateString('2028-02-29'), '2028-02-29');
  assert.equal(D.dateString('2026-02-28'), '2026-02-28');
});
