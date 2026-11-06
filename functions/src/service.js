'use strict';

const {FieldValue, FieldPath} = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');
const D = require('./domain');

const ACCOUNT = 'tesoreria_apoderados';
const MAX_IMAGE = 10 * 1024 * 1024;
const MIME = {'jpg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'};
const STAFF = new Set(['tesoreria', 'tesorero', 'admin_general', 'admin_asociacion', 'admin', 'administrador', 'administrador_asociacion', 'asociacion']);
const COLS = ['tesoreria_movimientos', 'tesoreria_pagos', 'comprobantes_pago', 'tesoreria_comprobantes', 'tesoreria_evento_cargos'];

function fail(code, message) { throw new HttpsError(code, message); }
function identifier(v, label) {
  if (typeof v !== 'string' || !v.trim() || v.length > 180 || v.includes('/') || v === '.' || v === '..') fail('invalid-argument', `${label} inválido.`);
  return v.trim();
}
function safeObject(d) {
  if (!d || typeof d !== 'object' || Array.isArray(d)) fail('invalid-argument', 'Solicitud inválida.');
  return d;
}
function requireAuth(request) {
  if (!request.auth?.uid) fail('unauthenticated', 'Inicia sesión para continuar.');
  return request.auth.uid;
}
function hasStaffRole(d = {}) {
  if (d.activo === false) return false;
  return [d.rol, ...(Array.isArray(d.roles) ? d.roles : [])].some(r => STAFF.has(D.text(r).toLowerCase()));
}
function serialize(value) {
  if (value === undefined) return null;
  if (value === null || typeof value !== 'object') return value;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, serialize(v)]));
}
function summaryAfterPayment(book, cargoId, monto, now) {
  const today = D.chileDate(now);
  const cargos = book.cargos.map(c => c.id === cargoId ? {...c, pagado: c.pagado + monto, saldo: c.saldo - monto} : c);
  const vencidos = cargos.filter(c => c.saldo > 0 && c.vence_el && c.vence_el < today);
  return {...book.resumen, pagos: book.resumen.pagos + monto,
    deuda: Math.max(0, book.resumen.deuda - monto),
    saldoVencido: vencidos.reduce((s, c) => s + c.saldo, 0),
    cuotasMorosas: new Set(vencidos.filter(c => c.tipo === 'cargo_mensual').map(c => c.periodo)).size};
}

/** Factory lets the emulator tests inject a demo project database and bucket. */
function createTreasuryService({db, bucket, auth, now = () => new Date()}) {
  if (!db) throw new Error('Firestore is required.');
  const stamp = () => FieldValue.serverTimestamp();
  const get = (reader, ref) => reader ? reader.get(ref) : ref.get();

  async function staff(uid, reader) {
    const s = await get(reader, db.collection('usuarios').doc(uid));
    return s.exists && hasStaffRole(s.data());
  }
  async function requireStaff(uid, reader) {
    if (!await staff(uid, reader)) fail('permission-denied', 'Solo Tesorería y administradores pueden revisar comprobantes.');
  }
  async function accountsForUid(uid, reader) {
    const result = new Map();
    for (const field of ['apoderado_uid', 'uid_apoderado', 'uid']) {
      const s = await get(reader, db.collection(ACCOUNT).where(field, '==', uid));
      s.docs.forEach(x => result.set(x.id, x));
    }
    const s = await get(reader, db.collection(ACCOUNT).where('apoderados_uids_autorizados', 'array-contains', uid));
    s.docs.forEach(x => result.set(x.id, x));
    return [...result.values()];
  }
  async function getAccount(cuentaId, uid, reader, allowStaff = true) {
    const s = await get(reader, db.collection(ACCOUNT).doc(cuentaId));
    if (!s.exists) fail('not-found', 'No existe la cuenta financiera.');
    if (!D.owns(s.data(), uid) && !(allowStaff && await staff(uid, reader))) fail('permission-denied', 'La cuenta no está vinculada a tu UID.');
    return s;
  }
  async function verifiedOwners(cuenta) {
    const owners = new Set(D.ownerUids(cuenta));
    // Legacy uid sometimes stores a beneficiary RUT. Only notify it if Auth confirms a real user.
    const candidate = D.text(cuenta.uid);
    if (candidate && !owners.has(candidate) && auth) {
      try { const user = await auth.getUser(candidate); if (!user.disabled) owners.add(candidate); }
      catch (e) { if (e.code !== 'auth/user-not-found' && e.code !== 'auth/invalid-uid') throw e; }
    }
    return [...owners];
  }

  async function loadLedger(accountSnap, reader, instant = now()) {
    const cuentaId = accountSnap.id, cuenta = accountSnap.data();
    const result = Object.fromEntries(COLS.map(c => [c, new Map()]));
    const extraWarnings = [];
    const ambiguousWarning = path => `Registro histórico ${path} vinculado al apoderado de varias cuentas: debe imputarse explícitamente antes de cobrar.`;
    const paidRecord = (col, d) => (D.FINAL_PAID.has(D.estado(d)) ||
      (['tesoreria_movimientos', 'tesoreria_pagos'].includes(col) && !D.estado(d))) &&
      (col !== 'tesoreria_movimientos' || D.isIngreso(d));
    const collect = (col, snap) => snap.docs.forEach(x => result[col].set(x.ref.path, {id: x.ref.path, data: x.data(), collection: col}));
    for (const col of COLS) {
      for (const field of ['cuenta_id', 'apoderado_id', 'beneficiario_id', 'rut_usuario', 'uid']) {
        collect(col, await get(reader, db.collection(col).where(field, '==', cuentaId)));
      }
    }
    // Discover only UID-bound legacy records. Email/RUT-apoderado are never account aliases.
    const ownerIds = new Set(D.ownerUids(cuenta));
    if (cuenta.uid && !/^\d{6,9}-?[\dkK]$/.test(cuenta.uid)) ownerIds.add(cuenta.uid);
    const uniqueOwnerAccount = new Map();
    for (const uid of ownerIds) {
      const ownerAccounts = await accountsForUid(uid, reader);
      const unique = ownerAccounts.length === 1 && ownerAccounts[0].id === cuentaId;
      uniqueOwnerAccount.set(uid, unique);
      for (const col of ['tesoreria_pagos', 'tesoreria_movimientos', 'comprobantes_pago', 'tesoreria_comprobantes']) {
        for (const field of ['uid', 'apoderado_uid', 'apoderado_id']) {
          const snap = await get(reader, db.collection(col).where(field, '==', uid));
          for (const x of snap.docs) {
            const d = x.data();
            if (!paidRecord(col, d)) continue;
            const target = D.text(d.cuenta_id || d.beneficiario_id || d.rut_usuario || d.apoderado_id);
            if (target && target !== uid && target !== cuentaId) continue;
            if (target === cuentaId || unique) result[col].set(x.ref.path, {id: x.ref.path, data: d, collection: col});
            else extraWarnings.push(ambiguousWarning(x.ref.path));
          }
        }
      }
    }
    // Account references take precedence over UID aliases, including the V57 reference fields.
    // A financial document ID can itself equal an Auth UID; that coincidence cannot resolve
    // an unassigned payment when the same parent owns several financial accounts.
    for (const col of COLS) {
      for (const [id, r] of result[col]) {
        const explicit = D.text(r.data.cuenta_id || r.data.beneficiario_id || r.data.rut_usuario);
        if (explicit) {
          if (explicit !== cuentaId) result[col].delete(id);
          continue;
        }
        const legacyTarget = D.text(r.data.apoderado_id);
        if (legacyTarget === cuentaId) continue;
        if (legacyTarget && !ownerIds.has(legacyTarget)) { result[col].delete(id); continue; }
        const ownerAlias = legacyTarget || D.text(r.data.uid || r.data.apoderado_uid);
        if (ownerIds.has(ownerAlias) && !uniqueOwnerAccount.get(ownerAlias)) {
          result[col].delete(id);
          if (paidRecord(col, r.data)) extraWarnings.push(ambiguousWarning(id));
        }
      }
    }
    const input = {cuentaId, cuenta, movimientos: [...result.tesoreria_movimientos.values()],
      pagos: [...result.tesoreria_pagos.values()], comprobantes: [...result.comprobantes_pago.values(), ...result.tesoreria_comprobantes.values()],
      eventos: [...result.tesoreria_evento_cargos.values()], ahora: instant};
    const book = D.calcularLibro(input);
    for (const warning of new Set(extraWarnings)) { book.advertencias.push(warning); book.bloqueos.push(warning); }
    book.resumen.deudaNoConciliada = book.bloqueos.length > 0;
    return {...book, input};
  }
  function requireReconciled(book) {
    if (book.bloqueos.length) fail('failed-precondition', `La cuenta requiere conciliación previa: ${book.bloqueos.join(' ')}`);
  }
  function findCharge(book, path) {
    const c = book.cargos.find(x => x.id === path);
    if (!c) fail('failed-precondition', 'El cargo no pertenece inequívocamente a esta cuenta o no está vigente.');
    return c;
  }
  function cache(summary) {
    const deuda = summary.deuda;
    return {monto_deuda: deuda, saldo_vencido_v58: summary.saldoVencido, meses_morosos: summary.cuotasMorosas,
      estado_pago: deuda <= 0 ? 'al_dia' : summary.saldoVencido > 0 ? 'moroso' : 'pendiente',
      aviso_activo: summary.saldoVencido > 0,
      mensaje_aviso: summary.saldoVencido > 0 ? `Saldo vencido pendiente: $${summary.saldoVencido}.` : '',
      saldo_calculado_libro_mayor: true, saldo_calculado_fecha: stamp(), actualizado: stamp(), version_contable: 58};
  }

  async function consultar(request) {
    const uid = requireAuth(request), data = safeObject(request.data || {});
    if (!data.cuentaId) {
      const docs = await staff(uid) ? (await db.collection(ACCOUNT).get()).docs : await accountsForUid(uid);
      return {cuentas: docs.map(x => serialize({...x.data(), id: x.id})), fechaChile: D.chileDate(now())};
    }
    const cuentaId = identifier(data.cuentaId, 'Cuenta');
    const account = await getAccount(cuentaId, uid);
    const book = await loadLedger(account);
    return serialize({cuenta: {...account.data(), id: account.id}, resumen: book.resumen,
      cargos: book.cargos, pagos: book.pagos, advertencias: book.advertencias, fechaChile: D.chileDate(now())});
  }

  async function imageMetadata(uid, solicitudId, storagePath, expectedGeneration) {
    const allowed = Object.keys(MIME).find(ext => storagePath === `comprobantes_v58/${uid}/${solicitudId}.${ext}`);
    if (!allowed) fail('invalid-argument', 'Ruta del comprobante inválida para el usuario y solicitud.');
    if (!bucket) fail('failed-precondition', 'Configura el bucket de comprobantes.');
    let meta;
    try { [meta] = await bucket.file(storagePath).getMetadata(); }
    catch (e) { if (e.code === 404) fail('failed-precondition', 'Primero sube la imagen del comprobante.'); throw e; }
    const size = Number(meta.size);
    if (!Number.isSafeInteger(size) || size < 1 || size > MAX_IMAGE || meta.contentType !== MIME[allowed]) fail('invalid-argument', 'La imagen debe ser JPG, PNG o WebP y pesar hasta 10 MiB.');
    if (!meta.md5Hash) fail('failed-precondition', 'Storage no entregó una huella verificable de la imagen; vuelva a subirla.');
    if (expectedGeneration && String(meta.generation) !== String(expectedGeneration)) fail('failed-precondition', 'La imagen cambió después del envío; requiere un nuevo comprobante.');
    return meta;
  }
  function pendingNotification(id, receipt) {
    return {tipo: 'comprobante_pendiente', comprobante_id: id, cuenta_id: receipt.cuenta_id || '',
      uid_origen: receipt.uid || '', titulo: 'Comprobante pendiente de revisión',
      mensaje: 'Se recibió un comprobante de pago. Verifique el depósito antes de aprobarlo.',
      resuelta: false, leida: false, fecha: stamp(), version: 58};
  }
  async function enviarComprobante(request) {
    const uid = requireAuth(request), data = safeObject(request.data);
    const cuentaId = identifier(data.cuentaId, 'Cuenta'), solicitudId = identifier(data.solicitudId, 'Solicitud');
    if (!/^[A-Za-z0-9_-]{16,100}$/.test(solicitudId)) fail('invalid-argument', 'Usa un identificador de solicitud aleatorio de 16 a 100 caracteres.');
    const cargoId = D.normalizePath(data.cargoId, ['tesoreria_movimientos', 'tesoreria_evento_cargos']);
    const monto = D.money(data.monto);
    if (!cargoId || monto === null || monto <= 0 || monto > 1000000000) fail('invalid-argument', 'Cargo o monto inválido.');
    const storagePath = D.text(data.storagePath), observacion = D.text(data.observacion);
    if (observacion.length > 2000) fail('invalid-argument', 'La observación admite hasta 2000 caracteres.');
    const id = D.receiptId(uid, solicitudId), ref = db.collection('comprobantes_pago').doc(id);
    const fingerprint = D.digest(uid, cuentaId, cargoId, monto, storagePath, observacion);
    const existing = await ref.get();
    if (existing.exists) {
      if (existing.data().solicitud_huella !== fingerprint) fail('already-exists', 'La solicitud ya corresponde a otro envío.');
      return {comprobanteId: id};
    }
    const account = await getAccount(cuentaId, uid, null, false);
    const meta = await imageMetadata(uid, solicitudId, storagePath);
    await db.runTransaction(async tx => {
      const prev = await tx.get(ref);
      if (prev.exists) {
        if (prev.data().solicitud_huella !== fingerprint) fail('already-exists', 'La solicitud ya corresponde a otro envío.');
        return;
      }
      const freshAccount = await getAccount(account.id, uid, tx, false);
      const book = await loadLedger(freshAccount, tx);
      requireReconciled(book);
      const cargo = findCharge(book, cargoId);
      if (monto > cargo.saldo) fail('failed-precondition', 'El abono supera el saldo pendiente del cargo.');
      const imageFingerprint = meta.md5Hash ? D.digest(cuentaId, meta.md5Hash) : null;
      const imageRef = imageFingerprint ? db.collection('tesoreria_comprobantes_huellas_v58').doc(imageFingerprint) : null;
      const imagePrev = imageRef ? await tx.get(imageRef) : null;
      if (imagePrev?.exists && imagePrev.data().estado !== 'rechazado' && imagePrev.data().comprobante_id !== id) fail('already-exists', 'Esta misma imagen ya fue enviada para la cuenta. Revise el historial antes de repetirla.');
      const receipt = {version: 58, solicitud_id: solicitudId, solicitud_huella: fingerprint,
        uid, email: D.text(request.auth.token?.email), cuenta_id: cuentaId, apoderado_id: cuentaId,
        cargo_id: cargoId, periodo: cargo.periodo, monto, observacion,
        storage_path: storagePath, storage_generation: String(meta.generation || ''),
        imagen_huella: imageFingerprint,
        estado: 'pendiente', fecha: stamp()};
      tx.create(ref, receipt);
      if (imageRef) tx.set(imageRef, {comprobante_id: id, cuenta_id: cuentaId, estado: 'pendiente', fecha: stamp()});
      tx.create(db.collection('tesoreria_notificaciones').doc(`comprobante_${id}`), pendingNotification(id, receipt));
    });
    return {comprobanteId: id};
  }

  async function notificarPendiente({id, data}) {
    if (!data) return;
    const ref = db.collection('tesoreria_notificaciones').doc(`comprobante_${id}`);
    await db.runTransaction(async tx => {
      const receipt = await tx.get(db.collection('comprobantes_pago').doc(id));
      const notification = await tx.get(ref);
      if (!receipt.exists || !['pendiente', 'pendiente_revision'].includes(D.estado(receipt.data())) || notification.exists) return;
      tx.create(ref, pendingNotification(id, receipt.data()));
    });
  }

  async function revisarComprobante(request) {
    const uid = requireAuth(request), data = safeObject(request.data);
    await requireStaff(uid);
    const id = identifier(data.comprobanteId, 'Comprobante');
    const decision = D.text(data.decision), motivo = D.text(data.motivo);
    if (!['aprobado', 'rechazado'].includes(decision)) fail('invalid-argument', 'Decisión inválida.');
    if (motivo.length > 1000 || (decision === 'rechazado' && motivo.length < 3)) fail('invalid-argument', 'Indica un motivo de rechazo de 3 a 1000 caracteres.');
    const ref = db.collection('comprobantes_pago').doc(id);
    // Storage is read outside the transaction; immutable uploads and the generation check protect the attachment.
    const initial = await ref.get();
    if (decision === 'aprobado' && initial.exists && initial.data().version === 58 && ['pendiente', 'pendiente_revision'].includes(D.estado(initial.data()))) {
      const r = initial.data();
      await imageMetadata(r.uid, r.solicitud_id, r.storage_path, r.storage_generation);
    }
    return db.runTransaction(async tx => {
      await requireStaff(uid, tx);
      const snap = await tx.get(ref);
      if (!snap.exists) fail('not-found', 'No existe el comprobante.');
      const receipt = snap.data();
      const reviewAmount = D.money(receipt.monto);
      if (receipt.estado === decision) {
        if (decision === 'aprobado') {
          const posted = await tx.get(db.collection('tesoreria_pagos').doc(D.paymentId(id)));
          if (receipt.version !== 58 || !posted.exists || !D.FINAL_PAID.has(D.estado(posted.data())) || posted.data().cuenta_id !== receipt.cuenta_id || posted.data().comprobante_id !== id || D.money(posted.data().monto) !== reviewAmount || posted.data().cargo_id !== receipt.cargo_id) fail('failed-precondition', 'El comprobante ya figura aprobado, pero su asiento no está conciliado. No se aplicó otro descuento.');
        }
        return {comprobanteId: id, estado: decision, yaRevisado: true};
      }
      if (!['pendiente', 'pendiente_revision'].includes(D.estado(receipt))) fail('failed-precondition', 'El comprobante ya fue revisado; no puede descontarse ni cambiar de resultado.');
      let cuentaId = D.text(receipt.cuenta_id || receipt.apoderado_id);
      // Legacy apoderado_id could be Auth UID, so only cuenta_id is immutable unless version 58.
      if (receipt.version !== 58 && !receipt.cuenta_id && data.cuentaId) cuentaId = identifier(data.cuentaId, 'Cuenta');
      else if (data.cuentaId && cuentaId !== data.cuentaId) fail('failed-precondition', 'No se puede reasignar la cuenta de un comprobante.');
      const cargoId = D.normalizePath(receipt.cargo_id || data.cargoId, ['tesoreria_movimientos', 'tesoreria_evento_cargos']);
      if (receipt.cargo_id && data.cargoId && receipt.cargo_id !== data.cargoId) fail('failed-precondition', 'No se puede reasignar el cargo de un comprobante.');
      let account, book, cargo, summary;
      if (decision === 'aprobado') {
        if (!cuentaId || !cargoId) fail('failed-precondition', 'Selecciona una cuenta y cargo explícitos para el comprobante histórico.');
        account = await getAccount(identifier(cuentaId, 'Cuenta'), uid, tx);
        if (!receipt.uid || !D.owns(account.data(), receipt.uid)) fail('failed-precondition', 'El UID que envió el comprobante no pertenece a esta cuenta. Revisa la vinculación, sin inferirla por correo.');
        const monto = reviewAmount;
        if (monto === null || monto <= 0) fail('failed-precondition', 'El monto del comprobante no es válido.');
        const posting = await tx.get(db.collection('tesoreria_pagos').doc(D.paymentId(id)));
        if (posting.exists) fail('failed-precondition', 'Ya existe un asiento para un comprobante aún pendiente. Requiere conciliación.');
        book = await loadLedger(account, tx);
        requireReconciled(book);
        if (book.pagos.some(p => p.id === `comprobante:${id}` || p.comprobante_id === id)) fail('failed-precondition', 'Ya existe un pago asociado a este comprobante en el histórico. No se aplicó otro descuento.');
        cargo = findCharge(book, cargoId);
        if (monto > cargo.saldo) fail('failed-precondition', 'El pago supera el saldo del cargo. Revisa el abono antes de aprobar.');
        summary = summaryAfterPayment(book, cargoId, monto, now());
      }
      const notificationRef = db.collection('tesoreria_notificaciones').doc(`comprobante_${id}`);
      const notification = await tx.get(notificationRef);
      const imageRef = receipt.imagen_huella ? db.collection('tesoreria_comprobantes_huellas_v58').doc(receipt.imagen_huella) : null;
      const imageFingerprint = imageRef ? await tx.get(imageRef) : null;
      if (decision === 'aprobado' && receipt.version === 58 && (!imageFingerprint?.exists || imageFingerprint.data().comprobante_id !== id)) fail('failed-precondition', 'La imagen está asociada a otro comprobante o falta su reserva. No se aplicó otro descuento.');
      const reviewer = {revisado_por_uid: uid, revisado_por: D.text(request.auth.token?.email), fecha_revision: stamp()};
      const result = {...reviewer, estado: decision, motivo_rechazo: decision === 'rechazado' ? motivo : ''};
      if (decision === 'aprobado') {
        Object.assign(result, {cuenta_id: cuentaId, apoderado_id: cuentaId, cargo_id: cargoId,
          aprobado_por: reviewer.revisado_por, aprobado_por_uid: uid, fecha_aprobacion: stamp()});
        tx.create(db.collection('tesoreria_pagos').doc(D.paymentId(id)), {
          version: 58, cuenta_id: cuentaId, apoderado_id: cuentaId, apoderado_uid: receipt.uid,
          apoderados_uids_autorizados: [...new Set([...D.ownerUids(account.data()), receipt.uid])],
          cargo_id: cargoId, comprobante_id: id, monto: D.money(receipt.monto), periodo: cargo.periodo,
          tipo: cargo.tipo === 'evento' ? 'evento' : 'pago', cuenta_destino: cargo.tipo === 'evento' ? 'CUENTA VISTA' : 'CUENTA CORRIENTE',
          estado: 'aprobado', fecha: stamp(), ...reviewer,
        });
        tx.update(db.doc(cargoId), {monto_pagado: cargo.pagado + reviewAmount,
          saldo_pendiente: cargo.saldo - reviewAmount, estado: cargo.saldo === reviewAmount ? 'pagado' : cargo.tipo === 'evento' ? 'abono' : 'parcial',
          fecha_ultimo_abono: stamp(), actualizado: stamp()});
        tx.set(account.ref, cache(summary), {merge: true});
      } else Object.assign(result, {rechazado_por: reviewer.revisado_por, rechazado_por_uid: uid, fecha_rechazo: stamp()});
      tx.update(ref, result);
      if (imageFingerprint?.exists && imageFingerprint.data().comprobante_id === id) tx.update(imageRef, {estado: decision, actualizado: stamp()});
      if (notification.exists) tx.update(notificationRef, {resuelta: true, resultado: decision, fecha_revision: stamp(), revisado_por_uid: uid});
      if (receipt.uid) {
        tx.set(db.collection('avisos_apoderados').doc(`comprobante_${D.digest(id, receipt.uid)}`), {
          apoderado_id: receipt.uid, comprobante_id: id, cuenta_id: cuentaId || '', tipo: 'revision_comprobante',
          titulo: decision === 'aprobado' ? 'Comprobante aprobado' : 'Comprobante rechazado',
          mensaje: decision === 'aprobado' ? `Se aprobó su abono de $${receipt.monto}. El saldo del cargo fue actualizado.` : `Su comprobante fue rechazado. Motivo: ${motivo}`,
          estado: decision, leido: false, aceptado: false, leida: false, resuelta: false, fecha: stamp(), version: 58,
        });
      }
      tx.create(db.collection('tesoreria_auditoria').doc(`revision_${id}`), {
        accion: `comprobante_${decision}`, comprobante_id: id, cuenta_id: cuentaId || '', cargo_id: cargoId || '',
        monto: D.money(receipt.monto), motivo_rechazo: decision === 'rechazado' ? motivo : '',
        usuario_uid: uid, usuario_email: reviewer.revisado_por, fecha: stamp(), version: 58,
      });
      return {comprobanteId: id, estado: decision, yaRevisado: false};
    });
  }

  async function generarMensualidad(cuentaId, mes, fecha, instant) {
    return db.runTransaction(async tx => {
      const snap = await tx.get(db.collection(ACCOUNT).doc(cuentaId));
      if (!snap.exists || !D.isActive(snap.data())) return {estado: 'omitido', motivo: 'Cuenta no activa explícitamente'};
      const cuenta = snap.data(), monto = D.money(cuenta.cuota_mensual);
      if (monto === null || monto <= 0) return {estado: 'omitido', motivo: 'Sin cuota mensual positiva explícita'};
      const inicio = D.period(cuenta.periodo_inicio_cobro || cuenta.mes_inicio_cobro || cuenta.inicio_cobro);
      if (inicio && inicio > mes) return {estado: 'omitido', motivo: 'Inicio de cobro posterior'};
      const ref = db.collection('tesoreria_movimientos').doc(D.chargeId(cuentaId, mes));
      const existing = await tx.get(ref);
      if (existing.exists) return {estado: 'ya_existente', cargo_id: ref.path};
      const book = await loadLedger(snap, tx, instant);
      // Guard legacy charges by account and period before considering a new deterministic V58 ID.
      if (book.cargos.some(c => c.tipo === 'cargo_mensual' && c.periodo === mes)) return {estado: 'legado_existente'};
      if (D.text(cuenta.ultimo_mes_procesado) === mes) fail('failed-precondition', 'El marcador histórico indica un período procesado sin cargo explícito; requiere conciliación.');
      requireReconciled(book);
      const cargo = {version: 58, cuenta_id: cuentaId, apoderado_id: cuentaId,
        apoderados_uids_autorizados: D.ownerUids(cuenta), apoderado_uid: D.text(cuenta.apoderado_uid || cuenta.uid_apoderado),
        apoderado_nombre: D.text(cuenta.nombre_apoderado || cuenta.nombre),
        tipo: 'cargo_mensual', concepto: `Mensualidad ${mes}`, periodo: mes, mes,
        monto, monto_pagado: 0, saldo_pendiente: monto, estado: 'pendiente',
        emitido_el: fecha, vence_el: D.lastDay(D.previousPeriod(mes)), fecha: stamp(), origen: 'scheduler_v58'};
      const nextBook = D.calcularLibro({...book.input, movimientos: [...book.input.movimientos, {id: ref.path, data: cargo}], ahora: instant});
      tx.create(ref, cargo);
      tx.set(snap.ref, {...cache(nextBook.resumen), ultimo_mes_procesado: mes}, {merge: true});
      return {estado: 'generado', cargo_id: ref.path};
    });
  }

  async function avisarCuenta(cuentaId, tipo, fecha, mes, instant) {
    const account = await db.collection(ACCOUNT).doc(cuentaId).get();
    if (!account.exists) return {estado: 'omitido'};
    const owners = await verifiedOwners(account.data());
    return db.runTransaction(async tx => {
      const snap = await tx.get(account.ref);
      if (!snap.exists) return {estado: 'omitido'};
      const book = await loadLedger(snap, tx, instant);
      requireReconciled(book);
      const selected = book.cargos.filter(c => c.saldo > 0 && (tipo === 'recordatorio_pago' ? c.tipo === 'cargo_mensual' && c.periodo === mes : c.vence_el && c.vence_el < fecha));
      const saldo = selected.reduce((s, c) => s + c.saldo, 0);
      if (!saldo) return {estado: 'sin_saldo'};
      const recipients = owners.filter(uid => D.owns(snap.data(), uid));
      if (!recipients.length) fail('failed-precondition', 'La cuenta no tiene un UID de apoderado autorizado para notificar.');
      const refs = recipients.map(uid => db.collection('avisos_apoderados').doc(`v58_${D.digest(tipo, fecha, cuentaId, uid)}`));
      const docs = [];
      for (const ref of refs) docs.push(await tx.get(ref));
      docs.forEach((s, i) => {
        if (s.exists) return;
        tx.create(refs[i], {version: 58, tipo, apoderado_id: recipients[i], cuenta_id: cuentaId,
          periodo: mes, fecha_efectiva: fecha, fecha: stamp(), monto_pendiente: saldo,
          cargos: selected.map(c => ({cargo_id: c.id, saldo: c.saldo})),
          titulo: tipo === 'recordatorio_pago' ? 'Recordatorio de pago' : 'Aviso de cobranza',
          mensaje: tipo === 'recordatorio_pago' ? `Recuerde pagar la mensualidad de ${mes} hasta el ${D.lastDay(D.previousPeriod(mes))}. Saldo pendiente: $${saldo}.` : `Mantiene un saldo vencido pendiente de $${saldo}. Los pagos aprobados y abonos parciales ya fueron descontados.`,
          leido: false, aceptado: false, leida: false, resuelta: false,
        });
      });
      tx.set(snap.ref, cache(book.resumen), {merge: true});
      return {estado: 'notificado', monto: saldo};
    });
  }

  async function procesarCalendario(scheduleTime) {
    const config = await db.collection('configuracion_tesoreria').doc('automatizacion_v58').get();
    if (!config.exists || config.data().habilitada !== true) return {estado: 'deshabilitado', procesadas: 0, fallos: 0};
    const plan = D.calendar(scheduleTime), instant = new Date(scheduleTime);
    let after = null, procesadas = 0, fallos = 0;
    do {
      let query = db.collection(ACCOUNT).orderBy(FieldPath.documentId()).limit(100);
      if (after) query = query.startAfter(after);
      const accounts = await query.get();
      if (accounts.empty) break;
      for (const account of accounts.docs) {
        const jobs = [];
        if (plan.generar) jobs.push(['generacion', () => generarMensualidad(account.id, plan.generar, plan.fecha, instant)]);
        if (plan.recordar) jobs.push(['recordatorio', () => avisarCuenta(account.id, 'recordatorio_pago', plan.fecha, plan.recordar, instant)]);
        if (plan.cobrar) jobs.push(['cobranza', () => avisarCuenta(account.id, 'aviso_cobranza', plan.fecha, plan.cobrar, instant)]);
        for (const [accion, execute] of jobs) {
          const record = db.collection('tesoreria_procesos_v58').doc(D.digest(plan.fecha, accion, account.id));
          try {
            const outcome = await execute();
            await record.set({cuenta_id: account.id, fecha_efectiva: plan.fecha, accion, ...outcome, actualizado: stamp()}, {merge: true});
            procesadas++;
          } catch (error) {
            fallos++;
            await record.set({cuenta_id: account.id, fecha_efectiva: plan.fecha, accion, estado: 'fallido',
              error_codigo: String(error.code || 'internal'), detalle: error instanceof HttpsError ? error.message : 'Fallo transitorio del proceso. Consulte Cloud Logging.', actualizado: stamp()}, {merge: true});
          }
        }
      }
      after = accounts.docs.at(-1);
      if (accounts.size < 100) break;
    } while (true);
    if (fallos) throw new Error(`Tesorería V58: ${fallos} procesos fallidos; revisar tesoreria_procesos_v58 para ${plan.fecha}.`);
    return {estado: 'completado', fecha: plan.fecha, procesadas, fallos};
  }

  return {consultar, enviarComprobante, revisarComprobante, notificarPendiente, procesarCalendario,
    generarMensualidad, avisarCuenta, loadLedger};
}

module.exports = {createTreasuryService, hasStaffRole, summaryAfterPayment, MAX_IMAGE};
