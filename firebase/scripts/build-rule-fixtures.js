'use strict';

// Derive local fixtures from the reviewed fragments. No Firebase API is used.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const fragment = read('tesoreria.firestore.rules.fragment');
const storageFragment = read('tesoreria.storage.rules.fragment');
const header = "rules_version = '2';\nservice cloud.firestore {\n  match /databases/{database}/documents {\n";
const tail = `
    // Perfil provisionado únicamente con Admin SDK; el cliente no asigna roles.
    match /usuarios/{uid} {
      allow read: if v58Owner(uid);
      allow write: if false;
    }
    match /{document=**} { allow read, write: if false; }
  }
}
`;
const demoFragment = fragment.replace(
  'return request.auth != null;',
  "return request.auth != null && request.auth.token.get('aud', '') == 'demo-autismo-rancagua-v58';",
);
assert.notEqual(demoFragment, fragment, 'Demo profile must require the demo project token');
const demoReads = `
    // Lecturas limitadas para las pestañas V57 de Tesorería sobre datos ficticios.
    // No confieren permisos de escritura ni representan la política productiva V57.
    match /tesoreria_eventos/{id} { allow read: if v58Staff(); }
    match /tesoreria_evento_cargos/{id} { allow read: if v58Staff(); }
    match /tesoreria_ingresos_institucionales/{id} { allow read: if v58Staff(); }
    match /tesoreria_gestiones_cobranza/{id} { allow read: if v58Staff(); }
    match /aseo_reemplazos/{id} { allow read: if v58Staff(); }
    match /ar_asignaciones_mensuales/{id} { allow read: if v58Staff(); }
`;
const outputs = {
  'emulator.firestore.rules':
    '// SOLO pruebas locales demo-autismo-rancagua-v58. NUNCA desplegar este archivo.\n' +
    '// Los módulos ajenos a Tesorería se deniegan deliberadamente en este fixture.\n' +
    header + fragment + tail,
  'emulator.storage.rules':
    '// SOLO pruebas locales demo-autismo-rancagua-v58. NUNCA desplegar este archivo.\n' +
    "rules_version = '2';\nservice firebase.storage {\n  match /b/{bucket}/o {\n" +
    storageFragment + '\n    match /{object=**} { allow read, write: if false; }\n  }\n}\n',
  'demo.firestore.rules':
    '// SOLO demo local, con usuarios ficticios sembrados vía Admin SDK. NUNCA desplegar.\n' +
    '// Auth exige aud=demo-autismo-rancagua-v58; no hay altas ni edición de roles cliente.\n' +
    header + demoFragment + demoReads + tail,
};
for (const [name, expected] of Object.entries(outputs)) {
  if (process.argv.includes('--check')) {
    assert.equal(read(name), expected, `${name} must be regenerated from current fragments`);
  } else {
    fs.writeFileSync(path.join(root, name), expected);
  }
}
console.log(process.argv.includes('--check') ? 'Rule fixtures match current fragments.' : 'Local rule fixtures generated.');
