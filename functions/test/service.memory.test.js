'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createTreasuryService} = require('../src/service');
const D = require('../src/domain');
const {MemoryFirestore} = require('./helpers/memory-firestore');

const CUENTA = 'beneficiario-a';
const CARGO = 'tesoreria_movimientos/cargo-a';
const parent = data => ({auth: {uid: 'padre', token: {email: 'padre@example.test'}}, data});
const staff = data => ({auth: {uid: 'tesorero', token: {email: 'tesorero@example.test'}}, data});
function fixture(extra = {}, clock = '2026-11-20T12:00:00Z', sameImage = false) {
  const db = new MemoryFirestore({
    'usuarios/tesorero': {rol: 'tesoreria', activo: true},
    'usuarios/padre': {rol: 'apoderado'},
    [`tesoreria_apoderados/${CUENTA}`]: {apoderado_uid: 'padre', nombre: 'Beneficiario A', cuota_mensual: 5000, estado_terapias: 'activo'},
    [CARGO]: {apoderado_id: CUENTA, tipo: 'cargo_mensual', periodo: '2026-12', monto: 5000, estado: 'pendiente', vence_el: '2026-11-30'},
    ...extra,
  });
  const bucket = {file: path => ({getMetadata: async () => [{size: '100', contentType: path.endsWith('.jpg') ? 'image/jpeg' : 'image/png', generation: '7', md5Hash: Buffer.from(sameImage ? 'identical-image-bytes' : path).toString('base64')}]})};
  const auth = {getUser: async () => { throw Object.assign(new Error(), {code: 'auth/user-not-found'}); }};
  return {db, bucket, service: createTreasuryService({db, bucket, auth, now: () => new Date(clock)})};
}
function envio(monto = 1500, suffix = 'abcdefghijklmnop') {
  return {cuentaId: CUENTA, cargoId: CARGO, monto, solicitudId: suffix,
    storagePath: `comprobantes_v58/padre/${suffix}.jpg`, observacion: 'Abono parcial'};
}
async function send(service, monto, suffix) { return (await service.enviarComprobante(parent(envio(monto, suffix)))).comprobanteId; }
function aprobar(service, id) { return service.revisarComprobante(staff({comprobanteId: id, decision: 'aprobado'})); }

// These exercise the service with its actual authorization/accounting logic.
// Transactions in the test double serialize and roll back; real Firestore
// contention/storage/Rules must additionally pass the provided emulator suites.
test('consulta sin autenticar o cuenta ajena falla; consulta propia no escribe', async () => {
  const {service, db} = fixture(); const before = [...db.docs.entries()];
  await assert.rejects(service.consultar({data: {}}), {code: 'unauthenticated'});
  await assert.rejects(service.consultar({auth: {uid: 'otro'}, data: {cuentaId: CUENTA}}), {code: 'permission-denied'});
  assert.equal((await service.consultar(parent({}))).cuentas[0].id, CUENTA);
  assert.equal((await service.consultar(parent({cuentaId: CUENTA}))).resumen.deuda, 5000);
  assert.deepEqual([...db.docs.entries()], before);
});

test('enviar y repetir solicitud crea un único pendiente/aviso, sin descontar saldo', async () => {
  const {service, db} = fixture();
  const [a, b] = await Promise.all([send(service, 1500), send(service, 1500)]);
  assert.equal(a, b);
  assert.equal(db.paths('comprobantes_pago').length, 1);
  assert.equal(db.paths('tesoreria_notificaciones').length, 1);
  assert.equal(db.paths('tesoreria_pagos').length, 0);
  assert.equal((await service.consultar(parent({cuentaId: CUENTA}))).resumen.deuda, 5000);
  await assert.rejects(service.enviarComprobante(parent(envio(2000))), {code: 'already-exists'});
});

test('abono aprobado descuenta exactamente una vez en aprobaciones concurrentes y crea auditoría/aviso', async () => {
  const {service, db} = fixture(); const id = await send(service, 1500);
  await Promise.all([aprobar(service, id), aprobar(service, id)]);
  const result = await service.consultar(parent({cuentaId: CUENTA}));
  assert.equal(result.resumen.pagos, 1500);
  assert.equal(result.resumen.deuda, 3500);
  assert.equal(result.cargos[0].pagado, 1500);
  assert.equal(result.cargos[0].saldo, 3500);
  assert.equal(result.pagos.length, 1);
  assert.equal(db.paths('tesoreria_pagos').length, 1);
  assert.equal(db.paths('tesoreria_auditoria').length, 1);
  assert.equal(db.paths('avisos_apoderados').length, 1);
  assert.equal(db.data(CARGO).monto_pagado, 1500);
  assert.equal(db.data(`comprobantes_pago/${id}`).revisado_por_uid, 'tesorero');
  assert.equal(db.data(`tesoreria_apoderados/${CUENTA}`).monto_deuda, 3500);
  assert.equal(db.data(`tesoreria_notificaciones/comprobante_${id}`).resuelta, true);
});

test('dos abonos iguales de comprobantes distintos son dos pagos, no se deduplican por monto/mes', async () => {
  const {service} = fixture();
  const a = await send(service, 1500, 'abcdefghijklmnop');
  const b = await send(service, 1500, 'qrstuvwxyzABCDEF');
  await Promise.all([aprobar(service, a), aprobar(service, b)]);
  const result = await service.consultar(parent({cuentaId: CUENTA}));
  assert.equal(result.resumen.pagos, 3000);
  assert.equal(result.resumen.deuda, 2000);
  assert.equal(result.cargos[0].saldo, 2000);
});

test('abonos competidores no sobrepagan: una aprobación falla sin alterar estado ni asiento', async () => {
  const {service, db} = fixture();
  const a = await send(service, 3500, 'abcdefghijklmnop');
  const b = await send(service, 3500, 'qrstuvwxyzABCDEF');
  const results = await Promise.allSettled([aprobar(service, a), aprobar(service, b)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.filter(r => r.status === 'rejected').length, 1);
  assert.equal(db.paths('tesoreria_pagos').length, 1);
  assert.equal(db.data(`comprobantes_pago/${b}`).estado, 'pendiente');
  assert.equal((await service.consultar(parent({cuentaId: CUENTA}))).resumen.deuda, 1500);
});

test('rechazar exige motivo, no descuenta y no puede aprobarse después', async () => {
  const {service, db} = fixture(); const id = await send(service, 1000);
  await assert.rejects(service.revisarComprobante(staff({comprobanteId: id, decision: 'rechazado', motivo: ''})), {code: 'invalid-argument'});
  await service.revisarComprobante(staff({comprobanteId: id, decision: 'rechazado', motivo: 'No figura el depósito en la cuenta bancaria.'}));
  assert.match(db.data(`comprobantes_pago/${id}`).motivo_rechazo, /depósito/);
  assert.equal(db.paths('tesoreria_pagos').length, 0);
  assert.equal(db.paths('avisos_apoderados').length, 1);
  await assert.rejects(aprobar(service, id), {code: 'failed-precondition'});
});

test('apoderado y tesorero desactivado no pueden revisar ni inventar cuenta ajena', async () => {
  const {service, db} = fixture(); const id = await send(service, 1000);
  await assert.rejects(service.revisarComprobante(parent({comprobanteId: id, decision: 'aprobado'})), {code: 'permission-denied'});
  await db.doc('usuarios/tesorero').update({activo: false});
  await assert.rejects(aprobar(service, id), {code: 'permission-denied'});
  await assert.rejects(service.enviarComprobante({auth: {uid: 'otro'}, data: envio()}), {code: 'permission-denied'});
  assert.equal(db.paths('tesoreria_pagos').length, 0);
});

test('aprobación histórica fallida queda pendiente; no se marca aprobada antes de contabilizar', async () => {
  const {service, db} = fixture({'comprobantes_pago/antiguo': {uid: 'sin-vinculo', monto: 1500, estado: 'pendiente'}});
  await assert.rejects(service.revisarComprobante(staff({comprobanteId: 'antiguo', decision: 'aprobado', cuentaId: CUENTA, cargoId: CARGO})), {code: 'failed-precondition'});
  assert.equal(db.data('comprobantes_pago/antiguo').estado, 'pendiente');
  assert.equal(db.paths('tesoreria_pagos').length, 0);
});

test('mensualidad día20 es idempotente, filtra inactivos y nunca aplica cuota por defecto', async () => {
  const {service, db} = fixture({
    'tesoreria_apoderados/beneficiario-b': {apoderado_uid: 'otro', cuota_mensual: 8000, activo: false},
    'tesoreria_apoderados/beneficiario-c': {apoderado_uid: 'otro', estado_terapias: 'activo'},
  });
  // Existing December charge is retained; January is a new explicit charge.
  const date = new Date('2026-12-20T12:00:00Z');
  await Promise.all([service.generarMensualidad(CUENTA, '2027-01', '2026-12-20', date), service.generarMensualidad(CUENTA, '2027-01', '2026-12-20', date)]);
  const path = `tesoreria_movimientos/${D.chargeId(CUENTA, '2027-01')}`;
  assert.equal(db.data(path).monto, 5000);
  assert.equal(db.data(path).vence_el, '2026-12-31');
  assert.equal(db.paths('tesoreria_movimientos').length, 2);
  await service.generarMensualidad('beneficiario-b', '2027-01', '2026-12-20', date);
  await service.generarMensualidad('beneficiario-c', '2027-01', '2026-12-20', date);
  assert.equal(db.paths('tesoreria_movimientos').length, 2);
});

test('día1 cobranza solo saldo restante aprobado, aviso idempotente y cero avisos si pagado', async () => {
  const {service, db} = fixture({}, '2026-12-01T12:00:00Z');
  const id = await send(service, 1500); await aprobar(service, id);
  await service.avisarCuenta(CUENTA, 'aviso_cobranza', '2026-12-01', '2026-12', new Date('2026-12-01T12:00:00Z'));
  await service.avisarCuenta(CUENTA, 'aviso_cobranza', '2026-12-01', '2026-12', new Date('2026-12-01T12:00:00Z'));
  const notices = db.paths('avisos_apoderados').map(p => db.data(p)).filter(x => x.tipo === 'aviso_cobranza');
  assert.equal(notices.length, 1); assert.equal(notices[0].monto_pendiente, 3500);
  const id2 = await send(service, 3500, 'qrstuvwxyzABCDEF'); await aprobar(service, id2);
  const response = await service.avisarCuenta(CUENTA, 'aviso_cobranza', '2027-01-01', '2027-01', new Date('2027-01-01T12:00:00Z'));
  assert.equal(response.estado, 'sin_saldo');
});

test('automatización apagada por defecto; activarla crea próximo mes y recordatorio una sola vez', async () => {
  const {service, db} = fixture();
  assert.equal((await service.procesarCalendario('2026-12-20T12:00:00Z')).estado, 'deshabilitado');
  await db.doc('configuracion_tesoreria/automatizacion_v58').set({habilitada: true});
  await service.procesarCalendario('2026-12-20T12:00:00Z');
  await service.procesarCalendario('2026-12-20T12:00:00Z');
  assert.equal(db.paths('tesoreria_movimientos').length, 2);
  const reminders = db.paths('avisos_apoderados').map(p => db.data(p)).filter(x => x.tipo === 'recordatorio_pago');
  assert.equal(reminders.length, 1);
  assert.equal(reminders[0].periodo, '2027-01');
});

test('misma imagen con otra solicitud no produce un segundo comprobante pendiente/aprobado', async () => {
  const {service, db} = fixture({}, '2026-11-20T12:00:00Z', true);
  const a = await send(service, 1500, 'abcdefghijklmnop');
  await assert.rejects(send(service, 1500, 'qrstuvwxyzABCDEF'));
  await aprobar(service, a);
  await assert.rejects(send(service, 1500, 'qrstuvwxyzABCDEF'));
  assert.equal(db.paths('comprobantes_pago').length, 1);
  assert.equal(db.paths('tesoreria_pagos').length, 1);
});

test('rechazo permite reenviar imagen sin reabrir el rechazado', async () => {
  const {service, db} = fixture({}, '2026-11-20T12:00:00Z', true);
  const a = await send(service, 1500, 'abcdefghijklmnop');
  await service.revisarComprobante(staff({comprobanteId: a, decision: 'rechazado', motivo: 'Documento incompleto.'}));
  const b = await send(service, 1500, 'qrstuvwxyzABCDEF');
  assert.notEqual(a, b);
  assert.equal(db.data(`comprobantes_pago/${a}`).estado, 'rechazado');
  await aprobar(service, b);
  assert.equal((await service.consultar(parent({cuentaId: CUENTA}))).resumen.deuda, 3500);
});

test('un archivo inexistente puede rechazarse, pero no aprobarse', async () => {
  const {service, bucket, db} = fixture(); const a = await send(service, 1500);
  bucket.file = () => ({getMetadata: async () => { throw Object.assign(new Error('missing'), {code: 404}); }});
  await assert.rejects(aprobar(service, a), {code: 'failed-precondition'});
  assert.equal(db.data(`comprobantes_pago/${a}`).estado, 'pendiente');
  await service.revisarComprobante(staff({comprobanteId: a, decision: 'rechazado', motivo: 'Archivo no disponible.'}));
  assert.equal(db.data(`comprobantes_pago/${a}`).estado, 'rechazado');
});

test('abono de evento no paga todo ni descuenta una mensualidad ajena', async () => {
  const eventPath = 'tesoreria_evento_cargos/evento-a';
  const {service, db} = fixture({[eventPath]: {apoderado_id: CUENTA, evento_id: 'evento', evento_titulo: 'Actividad', monto: 8000, monto_pagado: 0, estado: 'pendiente', vence_el: '2026-11-30'}});
  const id = (await service.enviarComprobante(parent({...envio(2000), cargoId: eventPath}))).comprobanteId;
  await aprobar(service, id);
  const book = await service.consultar(parent({cuentaId: CUENTA}));
  assert.equal(book.cargos.find(c => c.id === eventPath).saldo, 6000);
  assert.equal(book.cargos.find(c => c.id === CARGO).saldo, 5000);
  assert.equal(db.data(eventPath).monto_pagado, 2000);
  assert.equal(db.data(eventPath).estado, 'abono');
  assert.equal(book.resumen.deuda, 11000);
});

test('asiento previo en movimientos bloquea aplicar de nuevo un comprobante pendiente', async () => {
  const {service, db} = fixture({
    'comprobantes_pago/legado': {uid: 'padre', monto: 1000, estado: 'pendiente'},
    'tesoreria_movimientos/pago-preexistente': {apoderado_id: CUENTA, tipo: 'pago', estado: 'aprobado', monto: 1000, comprobante_id: 'legado', cargo_id: CARGO},
  });
  await assert.rejects(service.revisarComprobante(staff({comprobanteId: 'legado', decision: 'aprobado', cuentaId: CUENTA, cargoId: CARGO})), {code: 'failed-precondition'});
  assert.equal(db.data('comprobantes_pago/legado').estado, 'pendiente');
  assert.equal(db.paths('tesoreria_pagos').length, 0);
});

test('trigger de pendientes no duplica aviso ni reabre aviso resuelto', async () => {
  const {service, db} = fixture(); const id = await send(service, 1500);
  await Promise.all([service.notificarPendiente({id, data: db.data(`comprobantes_pago/${id}`)}), service.notificarPendiente({id, data: db.data(`comprobantes_pago/${id}`)})]);
  assert.equal(db.paths('tesoreria_notificaciones').length, 1);
  await aprobar(service, id);
  await service.notificarPendiente({id, data: {estado: 'pendiente'}});
  assert.equal(db.data(`tesoreria_notificaciones/comprobante_${id}`).resuelta, true);
});

test('día20 conserva cargo legado existente del mismo período sin duplicar', async () => {
  const {service, db} = fixture();
  const outcome = await service.generarMensualidad(CUENTA, '2026-12', '2026-11-20', new Date('2026-11-20T12:00:00Z'));
  assert.equal(outcome.estado, 'legado_existente');
  assert.equal(db.paths('tesoreria_movimientos').length, 1);
});

test('recordatorios hasta último día; después solo cobranza de saldo vencido', async () => {
  const {service, db} = fixture({'configuracion_tesoreria/automatizacion_v58': {habilitada: true}});
  await service.procesarCalendario('2026-11-19T12:00:00Z');
  assert.equal(db.paths('avisos_apoderados').length, 0);
  await service.procesarCalendario('2026-11-20T12:00:00Z');
  await service.procesarCalendario('2026-11-30T12:00:00Z');
  await service.procesarCalendario('2026-12-01T12:00:00Z');
  const notices = db.paths('avisos_apoderados').map(p => db.data(p));
  assert.equal(notices.filter(x => x.tipo === 'recordatorio_pago').length, 2);
  assert.equal(notices.filter(x => x.tipo === 'aviso_cobranza').length, 1);
});
