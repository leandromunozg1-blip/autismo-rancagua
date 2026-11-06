#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Read-only/local validation. Never deploys or touches a Firebase project.
node --version
npm --prefix functions run check
npm --prefix functions test
node --check firebase/test/rules.test.js
node --check functions/test/integration/firestore.test.js
python3 scripts/verify-v57-scope.py
python3 - <<'PY'
from pathlib import Path
import json
for filename in ['firebase.json', 'firebase.v58.emulators.json', 'functions/package.json', 'functions/package-lock.json', 'firebase/package.json', 'firebase/package-lock.json']:
    json.loads(Path(filename).read_text())
print('JSON configurations and npm lockfiles: valid')
PY
