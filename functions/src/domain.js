'use strict';

const {createHash} = require('node:crypto');

const TIME_ZONE = 'America/Santiago';
const FINAL_PAID = new Set(['aprobado', 'pagado', 'confirmado']);
const VOID = new Set(['anulado', 'anulada', 'rechazado', 'rechazada', 'eliminado', 'eliminada']);

function text(value) { return typeof value === 'string' ? value.trim() : ''; }
function money(value) {
  if (typeof value === 'number') return Number.isSafeInteger(value) && value >= 0 ? value : null;
  if (typeof value !== 'string') return null;
  const s = value.trim().replace(/^\$\s*/, '');
  if (!/^\d+$/.test(s) && !/^\d{1,3}(\.\d{3})+$/.test(s)) return null;
  const n = Number(s.replaceAll('.', ''));
  return Number.isSafeInteger(n) ? n : null;
}
function period(value) {
  const m = /^(20\d{2})[-_/](0?[1-9]|1[0-2])$/.exec(text(value));
  return m ? `${m[1]}-${m[2].padStart(2, '0')}` : null;
}
function chileDate(instant) {
  const date = instant instanceof Date ? instant : new Date(instant);
  if (!Number.isFinite(date.getTime())) throw new Error('Fecha de ejecución inválida.');
  const values = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(date).filter(p => p.type !== 'literal').map(p => [p.type, p.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
function nextPeriod(p) {
  if (!period(p)) throw new Error('Período inválido.');
  const [y, m] = p.split('-').map(Number);
  return `${m === 12 ? y + 1 : y}-${String(m === 12 ? 1 : m + 1).padStart(2, '0')}`;
}
function previousPeriod(p) {
  const [y, m] = p.split('-').map(Number);
  return `${m === 1 ? y - 1 : y}-${String(m === 1 ? 12 : m - 1).padStart(2, '0')}`;
}
function lastDay(p) {
  const [y, m] = p.split('-').map(Number);
  return `${p}-${new Date(Date.UTC(y, m, 0)).getUTCDate()}`;
}
function calendar(scheduleTime) {
  const fecha = chileDate(scheduleTime);
  const mes = fecha.slice(0, 7), dia = Number(fecha.slice(8));
  return {fecha, mes, dia, generar: dia >= 20 ? nextPeriod(mes) : null,
    recordar: dia >= 20 ? nextPeriod(mes) : null, cobrar: dia === 1 ? mes : null};
}
function digest(...parts) {
  return createHash('sha256').update(JSON.stringify(parts)).digest('hex');
}
function chargeId(cuentaId, mes) { return `mensual_v58_${digest(cuentaId, mes)}`; }
function paymentId(comprobanteId) { return `pago_comprobante_${comprobanteId}`; }
function receiptId(uid, solicitudId) { return `v58_${digest(uid, solicitudId)}`; }
function estado(d) { return text(d.estado).toLowerCase(); }
function explicitPeriod(d) { return period(d.periodo ?? d.mes ?? d.mes_cobro ?? d.periodo_cobro); }
function dateValue(v) {
  if (v && typeof v.toDate === 'function') return v.toDate();
  if (v instanceof Date) return Number.isFinite(v.getTime()) ? v : null;
  if (typeof v === 'string' || typeof v === 'number') {
    const d = new Date(v); if (Number.isFinite(d.getTime())) return d;
  }
  return null;
}
function dateString(v) {
  const civil = text(v);
  if (/^20\d{2}-\d{2}-\d{2}$/.test(civil)) {
    const date = new Date(`${civil}T12:00:00Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === civil ? civil : null;
  }
  const d = dateValue(v); return d ? chileDate(d) : null;
}
function isIngreso(d) {
  const s = text(d.tipo || d.concepto).toLowerCase();
  return /pago|abono|ingreso/.test(s);
}
function isMonthly(d) {
  const s = text(d.tipo || d.concepto).toLowerCase();
  return s === 'cargo_mensual' || s.includes('mensualidad');
}
function ownerUids(d) {
  return [...new Set([d.apoderado_uid, d.uid_apoderado,
    ...(Array.isArray(d.apoderados_uids_autorizados) ? d.apoderados_uids_autorizados : [])]
    .filter(v => typeof v === 'string' && v.trim()).map(v => v.trim()))];
}
function owns(d, uid) { return ownerUids(d).includes(uid) || text(d.uid) === uid; }
function isActive(d) {
  if (d.activo === false || ['inactivo', 'inactiva', 'eliminado', 'eliminada', 'retirado', 'retirada', 'suspendido', 'suspendida'].includes(estado(d))) return false;
  return d.activo === true || estado(d) === 'activo' || estado(d) === 'activa' || ['activo', 'activa'].includes(text(d.estado_terapias).toLowerCase());
}
function normalizePath(value, collections) {
  const p = text(value).split('/');
  return p.length === 2 && collections.includes(p[0]) && p[1] ? p.join('/') : null;
}
function recordPath(record, collection) { return record.id.includes('/') ? record.id : `${collection}/${record.id}`; }
function paymentKey(record, collection) {
  const d = record.data;
  const reference = text(d.comprobante_id || d.comprobanteId);
  if (reference) return `comprobante:${reference.replace(/^comprobantes_pago\//, '')}`;
  if (collection === 'comprobantes_pago') return `comprobante:${record.id.split('/').at(-1)}`;
  if (collection === 'tesoreria_comprobantes') return `comprobante:${recordPath(record, collection)}`;
  const id = (text(d.pago_id) || record.id.split('/').at(-1)).replace(/^tesoreria_pagos\//, '');
  if (id.startsWith('pago_comprobante_')) return `comprobante:${id.slice('pago_comprobante_'.length)}`;
  if (d.pago_id) return `asiento:${id.replace(/^tesoreria_pagos\//, '')}`;
  return collection === 'tesoreria_pagos' ? `asiento:${id}` : `registro:${recordPath(record, collection)}`;
}

/** Pure read-only reconciliation. No implicit months, amounts, aliases by email or writes. */
function calcularLibro({cuentaId, cuenta = {}, movimientos = [], pagos = [], comprobantes = [], eventos = [], ahora = new Date()}) {
  const advertencias = [], bloqueos = [];
  const warn = (s, block = true) => { if (!advertencias.includes(s)) advertencias.push(s); if (block && !bloqueos.includes(s)) bloqueos.push(s); };
  const cargos = [], paths = new Set();
  const addCharge = (record, collection) => {
    const d = record.data;
    if (VOID.has(estado(d))) return;
    const id = recordPath(record, collection);
    if (paths.has(id)) return;
    paths.add(id);
    const monto = money(d.monto ?? d.valor ?? d.total);
    if (monto === null || monto <= 0) { warn(`Cargo ${id}: monto inválido; requiere conciliación.`); return; }
    const mensual = isMonthly(d);
    const periodo = explicitPeriod(d) || dateString(d.fecha ?? d.creado)?.slice(0, 7) || 'sin_periodo';
    if (mensual && !explicitPeriod(d)) warn(`Cargo mensual ${id}: falta período explícito.`);
    const recordedDue = d.vence_el ?? d.vencimiento ?? d.fecha_vencimiento ?? d.fecha_limite;
    const hasRecordedDue = recordedDue !== undefined && recordedDue !== null && recordedDue !== '';
    const parsedDue = dateString(recordedDue);
    if (hasRecordedDue && !parsedDue) warn(`Cargo ${id}: vencimiento inválido; requiere conciliación.`);
    const due = parsedDue || (!hasRecordedDue && mensual && explicitPeriod(d) ? lastDay(previousPeriod(explicitPeriod(d))) : null);
    const stored = d.monto_pagado ?? d.monto_abonado;
    const pagadoRegistrado = stored === undefined ? 0 : money(stored);
    if (pagadoRegistrado === null) warn(`Cargo ${id}: abono registrado inválido.`);
    cargos.push({id, periodo, concepto: text(d.concepto || d.evento_titulo || d.titulo || d.tipo) || 'Cargo registrado',
      monto, pagado: 0, saldo: monto, tipo: collection === 'tesoreria_evento_cargos' ? 'evento' : mensual ? 'cargo_mensual' : 'cargo',
      vence_el: due, sin_vencimiento: !due, fecha: dateValue(d.fecha ?? d.creado)?.toISOString() || null,
      evento_id: text(d.evento_id), pagadoRegistrado: pagadoRegistrado ?? 0, estadoOriginal: estado(d)});
  };
  for (const r of movimientos) if (!isIngreso(r.data)) addCharge(r, 'tesoreria_movimientos');
  for (const r of eventos) addCharge(r, 'tesoreria_evento_cargos');
  const mensuales = new Map();
  for (const c of cargos.filter(c => c.tipo === 'cargo_mensual')) {
    if (mensuales.has(c.periodo)) warn(`Hay más de una mensualidad explícita para ${c.periodo}; no se cobrará automáticamente hasta revisar.`);
    mensuales.set(c.periodo, c.id);
  }

  const groups = new Map();
  const addPayment = (record, collection) => {
    const d = record.data;
    // Legacy movimientos/tesoreria_pagos used no estado for approved postings.
    const approved = FINAL_PAID.has(estado(d)) || (!estado(d) && collection !== 'comprobantes_pago' && collection !== 'tesoreria_comprobantes');
    if (!approved || VOID.has(estado(d))) return;
    const monto = money(d.monto ?? d.monto_pagado);
    if (monto === null || monto <= 0) { warn(`Pago ${recordPath(record, collection)}: monto inválido.`); return; }
    const key = paymentKey(record, collection);
    const cargoId = normalizePath(d.cargo_id || d.cargoId, ['tesoreria_movimientos', 'tesoreria_evento_cargos']);
    if ((d.cargo_id || d.cargoId) && !cargoId) warn(`Pago ${recordPath(record, collection)}: referencia de cargo inválida.`);
    const value = {id: key, monto, cargo_id: cargoId, periodo: explicitPeriod(d) || dateString(d.fecha ?? d.fecha_aprobacion)?.slice(0, 7) || 'sin_periodo',
      comprobante_id: text(d.comprobante_id) || ((collection === 'comprobantes_pago' || collection === 'tesoreria_comprobantes') ? record.id.split('/').at(-1) : ''),
      fecha: dateValue(d.fecha ?? d.fecha_aprobacion)?.toISOString() || null,
      fecha_chile: dateString(d.fecha ?? d.fecha_aprobacion),
      cuenta_destino: text(d.cuenta_destino) || null, periodo_explicito: explicitPeriod(d), evento_id: text(d.evento_id),
      fuentes: [recordPath(record, collection)], tipo: text(d.tipo) || 'pago', estado: 'aprobado'};
    if (!groups.has(key)) { groups.set(key, value); return; }
    const first = groups.get(key);
    if (first.monto !== value.monto || (first.cargo_id && cargoId && first.cargo_id !== cargoId) ||
        (first.periodo_explicito && value.periodo_explicito && first.periodo_explicito !== value.periodo_explicito) ||
        (first.evento_id && value.evento_id && first.evento_id !== value.evento_id)) {
      warn(`Pago ${key}: representaciones incompatibles; requiere revisión sin alterar el histórico.`);
    }
    if (!first.cargo_id && cargoId) first.cargo_id = cargoId;
    if (!first.periodo_explicito && value.periodo_explicito) first.periodo_explicito = value.periodo_explicito;
    if (!first.evento_id && value.evento_id) first.evento_id = value.evento_id;
    if (!first.fecha && value.fecha) first.fecha = value.fecha;
    if (!first.fecha_chile && value.fecha_chile) first.fecha_chile = value.fecha_chile;
    if (!first.cuenta_destino && value.cuenta_destino) first.cuenta_destino = value.cuenta_destino;
    first.fuentes.push(...value.fuentes);
  };
  // Prefer the actual journal posting over its display/receipt representation.
  for (const r of pagos) addPayment(r, 'tesoreria_pagos');
  for (const r of movimientos) if (isIngreso(r.data)) addPayment(r, 'tesoreria_movimientos');
  for (const r of comprobantes) addPayment(r, r.collection || 'comprobantes_pago');

  const approved = [...groups.values()];
  const byPath = new Map(cargos.map(c => [c.id, c]));
  let noImputado = 0;
  for (const p of approved) {
    if (!p.cargo_id) {
      // Only explicit obligation metadata may resolve a legacy posting; never date/amount/email.
      const candidates = p.evento_id ? cargos.filter(c => c.tipo === 'evento' && c.evento_id === p.evento_id) :
        p.periodo_explicito && p.tipo !== 'evento' ? cargos.filter(c => c.tipo === 'cargo_mensual' && c.periodo === p.periodo_explicito) : [];
      if (candidates.length === 1) p.cargo_id = candidates[0].id;
    }
    const c = p.cargo_id ? byPath.get(p.cargo_id) : null;
    if (!c) {
      noImputado += p.monto;
      warn(`Pago ${p.id}: ${p.monto} CLP sin cargo identificable; se conserva como crédito no imputado.`);
    } else c.pagado += p.monto;
  }
  let abonosSinAsiento = 0;
  for (const c of cargos) {
    // A legacy event's stored abonos are independent evidence, never add both representations.
    if (c.pagadoRegistrado > c.pagado) {
      const missing = c.pagadoRegistrado - c.pagado;
      abonosSinAsiento += missing;
      c.pagado = c.pagadoRegistrado;
      c.abonoRegistradoSinAsiento = missing;
      warn(`Cargo ${c.id}: ${missing} CLP de abonos registrados sin asiento completo; no se suman como un segundo pago. Requiere conciliación.`);
    }
    if (c.pagado > c.monto) warn(`Cargo ${c.id}: pagos superiores al cargo; el crédito histórico se conserva.`);
    if (c.estadoOriginal === 'pagado' && c.pagado < c.monto) warn(`Cargo ${c.id}: figura pagado pero mantiene saldo.`);
    c.saldo = Math.max(0, c.monto - c.pagado);
    delete c.pagadoRegistrado; delete c.estadoOriginal;
  }
  const totalCargos = cargos.reduce((s, c) => s + c.monto, 0);
  const totalPagos = approved.reduce((s, p) => s + p.monto, 0);
  if (!cargos.length && (money(cuenta.monto_deuda) || 0) > 0) warn('Existe deuda histórica en la ficha sin cargos explícitos. No se ha convertido en mensualidades ni apertura ficticia.');
  if (cargos.length && cuenta.version_contable !== 58 && money(cuenta.monto_deuda) !== null &&
      money(cuenta.monto_deuda) !== Math.max(0, totalCargos - totalPagos)) warn('El saldo histórico de la ficha difiere del libro explícito. Debe conciliarse antes de reemplazarlo; no se ha creado una apertura ni borrado deuda.');
  if (Array.isArray(cuenta.advertencias_conciliacion_v58)) for (const w of cuenta.advertencias_conciliacion_v58) warn(text(w));
  const today = chileDate(ahora);
  const overdue = cargos.filter(c => c.saldo > 0 && c.vence_el && c.vence_el < today);
  const periods = new Map();
  for (const c of cargos) {
    if (!periods.has(c.periodo)) periods.set(c.periodo, {periodo: c.periodo, cargos: 0, pagos: 0});
    periods.get(c.periodo).cargos += c.monto;
  }
  for (const p of approved) {
    const per = byPath.get(p.cargo_id)?.periodo || p.periodo;
    if (!periods.has(per)) periods.set(per, {periodo: per, cargos: 0, pagos: 0});
    periods.get(per).pagos += p.monto;
  }
  let acumulado = 0;
  const periodos = [...periods.values()].sort((a, b) => a.periodo.localeCompare(b.periodo)).map(p => {
    const saldoMes = p.cargos - p.pagos;
    acumulado += saldoMes; // Keep advances/credit, never clamp at each period.
    return {...p, saldoMes, saldo: acumulado};
  });
  return {resumen: {cargos: totalCargos, pagos: totalPagos, deuda: Math.max(0, totalCargos - totalPagos),
    credito: Math.max(0, totalPagos - totalCargos), pagosNoImputados: noImputado,
    saldoVencido: overdue.reduce((s, c) => s + c.saldo, 0),
    abonosRegistradosSinAsiento: abonosSinAsiento, deudaNoConciliada: bloqueos.length > 0,
    cuotasMorosas: new Set(overdue.filter(c => c.tipo === 'cargo_mensual').map(c => c.periodo)).size,
    usaLibroMayor: cargos.length > 0 || approved.length > 0, periodos},
  cargos: cargos.sort((a, b) => a.periodo.localeCompare(b.periodo) || a.id.localeCompare(b.id)), pagos: approved,
  advertencias, bloqueos};
}

module.exports = {TIME_ZONE, text, money, period, chileDate, nextPeriod, previousPeriod, lastDay, calendar,
  digest, chargeId, paymentId, receiptId, estado, explicitPeriod, isIngreso, isMonthly, ownerUids, owns,
  isActive, normalizePath, calcularLibro, FINAL_PAID, dateString};
