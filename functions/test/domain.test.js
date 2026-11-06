'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const D = require('../src/domain');

const row = (id, data) => ({id, data});
const monthly = (id, mes, monto = 10000, more = {}) => row(id, {tipo: 'cargo_mensual', periodo: mes, monto, estado: 'pendiente', ...more});
const payment = (id, monto, cargo_id, more = {}) => row(id, {tipo: 'pago', monto, cargo_id, estado: 'aprobado', ...more});
const calc = changes => D.calcularLibro({cuentaId: 'beneficiario-1', ahora: new Date('2026-11-01T12:00:00Z'), ...changes});

test('Calendario Chile usa fecha local incluso cerca de medianoche UTC', () => {
  assert.deepEqual(D.calendar('2026-11-20T02:30:00Z'), {fecha: '2026-11-19', mes: '2026-11', dia: 19, generar: null, recordar: null, cobrar: null});
  assert.equal(D.calendar('2026-11-20T12:00:00Z').generar, '2026-12');
  assert.equal(D.calendar('2026-11-20T12:00:00Z').recordar, '2026-12');
});
test('Generación catch-up sigue disponible desde el 20 hasta el último día', () => {
  assert.equal(D.calendar('2026-11-19T12:00:00Z').generar, null);
  assert.equal(D.calendar('2026-11-21T12:00:00Z').generar, '2026-12');
  assert.equal(D.calendar('2026-11-30T12:00:00Z').recordar, '2026-12');
  assert.equal(D.calendar('2026-12-01T12:00:00Z').generar, null);
  assert.equal(D.calendar('2026-12-01T12:00:00Z').cobrar, '2026-12');
  assert.equal(D.calendar('2026-12-02T12:00:00Z').cobrar, null);
});
test('Año nuevo, febrero bisiesto y reglas DST de America/Santiago', () => {
  assert.equal(D.nextPeriod('2026-12'), '2027-01');
  assert.equal(D.previousPeriod('2027-01'), '2026-12');
  assert.equal(D.lastDay('2024-02'), '2024-02-29');
  assert.equal(D.lastDay('2025-02'), '2025-02-28');
  // Winter UTC-4 and summer UTC-3; no hardcoded offset.
  assert.equal(D.chileDate('2026-07-20T03:30:00Z'), '2026-07-19');
  assert.equal(D.chileDate('2026-12-20T03:30:00Z'), '2026-12-20');
  assert.equal(D.chileDate('2026-04-05T03:30:00Z'), '2026-04-04');
  assert.equal(D.chileDate('2026-09-06T04:30:00Z'), '2026-09-06');
});
test('IDs determinísticos separan cuentas/períodos y reintentos', () => {
  assert.equal(D.chargeId('c1', '2026-12'), D.chargeId('c1', '2026-12'));
  assert.notEqual(D.chargeId('c1', '2026-12'), D.chargeId('c2', '2026-12'));
  assert.notEqual(D.chargeId('c1', '2026-12'), D.chargeId('c1', '2027-01'));
  assert.notEqual(D.receiptId('u1', 'request'), D.receiptId('u2', 'request'));
});
test('Sin cargos explícitos no inventa mensualidades ni apertura de deuda', () => {
  const book = calc({cuenta: {cuota_mensual: 5000, fecha_creacion: '2020-01-01', monto_deuda: 20000}});
  assert.equal(book.cargos.length, 0);
  assert.equal(book.resumen.cargos, 0);
  assert.equal(book.resumen.deudaNoConciliada, true);
  assert.match(book.advertencias.join(' '), /deuda histórica/);
});
test('Libro suma solo meses explícitos, incluyendo cargo futuro emitido el día 20', () => {
  const book = calc({movimientos: [monthly('enero', '2026-01', 5000), monthly('noviembre', '2026-11', 10000), monthly('diciembre', '2026-12', 12000)]});
  assert.equal(book.resumen.cargos, 27000);
  assert.equal(book.resumen.saldoVencido, 15000);
  assert.equal(book.resumen.cuotasMorosas, 2);
  assert.equal(book.resumen.periodos.length, 3);
});
test('Cache histórico discrepante con cargos explícitos bloquea y no crea apertura', () => {
  const book = calc({cuenta: {monto_deuda: 20000}, movimientos: [monthly('nov', '2026-11', 10000)]});
  assert.equal(book.resumen.cargos, 10000);
  assert.equal(book.resumen.deudaNoConciliada, true);
  assert.match(book.advertencias.join(' '), /saldo histórico de la ficha difiere/);
  const agreed = calc({cuenta: {monto_deuda: 10000}, movimientos: [monthly('nov', '2026-11', 10000)]});
  assert.deepEqual(agreed.bloqueos, []);
});
test('Pago aprobado y abonos parciales descuentan el cargo correcto', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11')], pagos: [payment('p1', 2500, 'tesoreria_movimientos/nov'), payment('p2', 1500, 'tesoreria_movimientos/nov')]});
  assert.equal(book.resumen.pagos, 4000);
  assert.equal(book.resumen.deuda, 6000);
  assert.equal(book.resumen.saldoVencido, 6000);
  assert.equal(book.cargos[0].pagado, 4000);
  assert.equal(book.cargos[0].saldo, 6000);
  assert.deepEqual(book.bloqueos, []);
});
test('Pagos iguales con identidades distintas se mantienen; movimientos no ocultan otros pagos', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11'), payment('mov1', 2000, 'tesoreria_movimientos/nov')],
    pagos: [payment('p1', 2000, 'tesoreria_movimientos/nov'), payment('p2', 2000, 'tesoreria_movimientos/nov')]});
  assert.equal(book.pagos.length, 3);
  assert.equal(book.resumen.pagos, 6000);
  assert.equal(book.resumen.deuda, 4000);
});
test('Mismo docId sin referencia en colecciones distintas no pierde pagos independientes', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11'), payment('abc', 2000, 'tesoreria_movimientos/nov')],
    pagos: [payment('abc', 2000, 'tesoreria_movimientos/nov')]});
  assert.equal(book.resumen.pagos, 4000);
});
test('Representaciones de mismo comprobante se cuentan una vez por identidad', () => {
  const more = {comprobante_id: 'r1'};
  const book = calc({movimientos: [monthly('nov', '2026-11'), payment('pago_comprobante_r1', 3000, 'tesoreria_movimientos/nov', more)],
    pagos: [payment('aleatorio', 3000, 'tesoreria_movimientos/nov', more)],
    comprobantes: [payment('r1', 3000, 'tesoreria_movimientos/nov')]});
  assert.equal(book.resumen.pagos, 3000);
  assert.equal(book.pagos.length, 1);
  assert.equal(book.pagos[0].fuentes.length, 3);
});
test('Referencias explícitas pago_id enlazan espejos sin comprobante', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11'), payment('mov', 3000, 'tesoreria_movimientos/nov', {pago_id: 'tesoreria_pagos/pago'})],
    pagos: [payment('pago', 3000, 'tesoreria_movimientos/nov')]});
  assert.equal(book.resumen.pagos, 3000);
});
test('Duplicados contradictorios bloquean mutación; no suman ambas representaciones', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11'), payment('m', 5000, 'tesoreria_movimientos/nov', {comprobante_id: 'r1'})],
    pagos: [payment('p', 2000, 'tesoreria_movimientos/nov', {comprobante_id: 'r1'})]});
  assert.equal(book.resumen.pagos, 2000);
  assert.match(book.bloqueos.join(' '), /incompatibles/);
});
test('Legado con período explícito se imputa solo si existe mensualidad única', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11')], pagos: [row('p1', {monto: 2500, mes: '2026-11', estado: 'aprobado'})]});
  assert.equal(book.cargos[0].saldo, 7500);
  assert.deepEqual(book.bloqueos, []);
});
test('Fecha de aprobación no se usa para adivinar período de la obligación', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11')], pagos: [row('p1', {monto: 2500, fecha: '2026-11-01T12:00:00Z', estado: 'aprobado'})]});
  assert.equal(book.cargos[0].saldo, 10000);
  assert.equal(book.resumen.pagosNoImputados, 2500);
  assert.equal(book.resumen.deudaNoConciliada, true);
});
test('No condona ni oculta mensualidades duplicadas; bloquea imputación ambigua', () => {
  const book = calc({movimientos: [monthly('nov1', '2026-11'), monthly('nov2', '2026-11')], pagos: [row('p1', {monto: 2500, mes: '2026-11', estado: 'aprobado'})]});
  assert.equal(book.resumen.cargos, 20000);
  assert.equal(book.resumen.pagosNoImputados, 2500);
  assert.match(book.bloqueos.join(' '), /más de una mensualidad/);
});
test('Eventos descuentan abonos parciales por evento_id inequívoco sin alterar mensualidad', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11')],
    eventos: [row('e1', {evento_id: 'actividad', monto: 5000, vencimiento: '2026-10-30', monto_pagado: 2000, estado: 'parcial'})],
    pagos: [row('p1', {tipo: 'evento', evento_id: 'actividad', monto: 2000, estado: 'aprobado'})]});
  assert.equal(book.resumen.cargos, 15000);
  assert.equal(book.resumen.pagos, 2000);
  assert.equal(book.cargos.find(c => c.tipo === 'evento').saldo, 3000);
  assert.equal(book.cargos.find(c => c.tipo === 'cargo_mensual').saldo, 10000);
});
test('Cargo de evento sin vencimiento admite abono explícito y no forma saldo vencido', () => {
  const book = calc({eventos: [row('evento', {monto: 5000, estado: 'pendiente'})],
    pagos: [payment('pago-evento', 2000, 'tesoreria_evento_cargos/evento')]});
  assert.deepEqual(book.bloqueos, []);
  assert.equal(book.cargos[0].sin_vencimiento, true);
  assert.equal(book.cargos[0].saldo, 3000);
  assert.equal(book.resumen.deuda, 3000);
  assert.equal(book.resumen.saldoVencido, 0);
});
test('fecha_limite de evento V57 se respeta como vencimiento explícito', () => {
  const book = calc({eventos: [row('evento', {monto: 5000, estado: 'pendiente', fecha_limite: '2026-10-31'})]});
  assert.equal(book.cargos[0].vence_el, '2026-10-31');
  assert.equal(book.resumen.saldoVencido, 5000);
});
test('Crédito no imputado y abono registrado no se suman como dos pagos ciertos', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11', 10000, {monto_pagado: 3000})],
    pagos: [row('p1', {monto: 3000, estado: 'aprobado'})]});
  assert.equal(book.resumen.pagos, 3000);
  assert.equal(book.resumen.pagosNoImputados, 3000);
  assert.equal(book.resumen.abonosRegistradosSinAsiento, 3000);
  assert.equal(book.resumen.deudaNoConciliada, true);
});
test('Créditos históricos no se pierden al cruzar meses ni al exceder un cargo', () => {
  const book = calc({movimientos: [monthly('ene', '2026-01', 5000), monthly('feb', '2026-02', 5000)],
    pagos: [payment('p1', 12000, 'tesoreria_movimientos/ene')]});
  assert.equal(book.resumen.pagos, 12000);
  assert.equal(book.resumen.credito, 2000);
  assert.equal(book.resumen.periodos[0].saldo, -7000);
  assert.equal(book.resumen.periodos[1].saldo, -2000);
  assert.equal(book.resumen.deudaNoConciliada, true);
});
test('Pagos pendientes/rechazados y cargos anulados no afectan libro', () => {
  const book = calc({movimientos: [monthly('nov', '2026-11'), monthly('anulado', '2026-10', 10000, {estado: 'anulado'})],
    pagos: [payment('p1', 3000, 'tesoreria_movimientos/nov', {estado: 'rechazado'})],
    comprobantes: [payment('r1', 2000, 'tesoreria_movimientos/nov', {estado: 'pendiente'})]});
  assert.equal(book.resumen.cargos, 10000);
  assert.equal(book.resumen.pagos, 0);
});
test('ACL no usa emails ni RUT de apoderado, y cuota cero no adquiere default', () => {
  assert.equal(D.owns({email: 'u@example.com', rut_apoderado: '11-1'}, 'auth-uid'), false);
  assert.equal(D.owns({apoderados_uids_autorizados: ['auth-uid']}, 'auth-uid'), true);
  assert.equal(D.owns({uid: 'auth-uid'}, 'auth-uid'), true);
  assert.equal(D.isActive({activo: false, estado_terapias: 'activo'}), false);
  assert.equal(D.isActive({estado_terapias: 'activo'}), true);
  assert.equal(D.isActive({}), false);
  assert.equal(D.money(0), 0);
  assert.equal(D.money(-10), null);
  assert.equal(D.money('5.000'), 5000);
  assert.equal(D.money('1.50'), null);
});
