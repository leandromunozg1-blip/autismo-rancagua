'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateDemoEnvironment} = require('../scripts/seed-demo-v58');
const local = {FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080', FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099'};

test('seed DEMO no admite hosts ausentes, externos ni proyecto real', () => {
  assert.throws(() => validateDemoEnvironment({}));
  assert.throws(() => validateDemoEnvironment({...local, FIRESTORE_EMULATOR_HOST: 'firestore.googleapis.com:443'}));
  assert.throws(() => validateDemoEnvironment({...local, FIREBASE_AUTH_EMULATOR_HOST: '10.0.0.2:9099'}));
  assert.throws(() => validateDemoEnvironment({...local, GCLOUD_PROJECT: 'autismo-rancagua'}));
  assert.throws(() => validateDemoEnvironment({...local, FIREBASE_CONFIG: '{"projectId":"autismo-rancagua"}'}));
  assert.throws(() => validateDemoEnvironment({...local, FIREBASE_CONFIG: '/path/config.json'}));
});

test('seed DEMO acepta solo emuladores locales con identidad fija', () => {
  assert.doesNotThrow(() => validateDemoEnvironment(local));
  assert.doesNotThrow(() => validateDemoEnvironment({...local, GCLOUD_PROJECT: 'demo-autismo-rancagua-v58', FIREBASE_CONFIG: '{"projectId":"demo-autismo-rancagua-v58"}'}));
});
