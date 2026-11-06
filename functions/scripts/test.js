'use strict';

// Run the native node:test harness in this process. Supported by Node 22 and 24;
// avoids the cloud sandbox's incomplete child-process test protocol.
const {readdirSync} = require('node:fs');
const {join} = require('node:path');
const root = join(__dirname, '..', 'test');
const files = readdirSync(root).filter(name => name.endsWith('.test.js')).sort();
if (!files.length) throw new Error('No test files found.');
for (const file of files) require(join(root, file));
