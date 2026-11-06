'use strict';

const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {getAuth} = require('firebase-admin/auth');
const {onCall} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {createTreasuryService} = require('./src/service');

initializeApp();
const service = createTreasuryService({db: getFirestore(), bucket: getStorage().bucket(), auth: getAuth()});
const options = {region: 'southamerica-west1', timeoutSeconds: 120, memory: '256MiB'};

exports.tesoreriaConsultar = onCall(options, request => service.consultar(request));
exports.tesoreriaEnviarComprobante = onCall(options, request => service.enviarComprobante(request));
exports.tesoreriaRevisarComprobante = onCall(options, request => service.revisarComprobante(request));

exports.tesoreriaComprobantePendiente = onDocumentCreated({
  document: 'comprobantes_pago/{comprobanteId}', region: options.region, retry: true,
}, event => service.notificarPendiente({id: event.params.comprobanteId, data: event.data?.data()}));

// A daily job catches up a failed day-20 generation on days 21..end of month.
// Scheduler retries retain scheduleTime: notification identities remain stable.
exports.tesoreriaCalendarioChile = onSchedule({
  schedule: '0 9 * * *', timeZone: 'America/Santiago', region: options.region,
  timeoutSeconds: 540, memory: '512MiB', retryCount: 3, minBackoffSeconds: 60,
  maxBackoffSeconds: 3600, maxRetrySeconds: 21600,
}, event => service.procesarCalendario(event.scheduleTime));
