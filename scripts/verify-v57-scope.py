#!/usr/bin/env python3
"""Verify all original V57 files outside the declared Treasury change scope."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'docs/V57_FILES_SHA256.json').read_text())
allowed = {
    'pubspec.yaml', 'firebase.json', 'lib/main.dart', 'lib/tesoreria.dart',
    'lib/services/tesoreria_finanzas_service.dart',
    'lib/pages/tesoreria/detalle_financiero_apoderado_page.dart',
    # Sanitización autorizada para el respaldo Git sin datos/configuración real.
    'lib/app_roles.dart',
    'lib/core/auth/app_roles.dart',
    'lib/firebase_options.dart',
    'lib/pages/admin/normalizar_firebase_page.dart',
    'lib/pages/coordinacion/beneficiarios_contactos_page.dart',
    'lib/pages/admin/carga_masiva_real_page.dart',
}
private_excluded = {'assets/images/tesoreria_v25/referencia_diseno_v25e.png'}
changed = []
intact = []
for name, digest in manifest.items():
    path = root / name
    if name in private_excluded:
        continue
    assert path.is_file(), f'Original V57 file missing: {name}'
    current = hashlib.sha256(path.read_bytes()).hexdigest()
    if current != digest:
        assert name in allowed, f'Unexpected V57 change: {name}'
        changed.append(name)
    else:
        intact.append(name)
print(f'{len(intact)} original V57 files unchanged byte-for-byte; {len(changed)} declared files changed; {len(private_excluded)} private reference excluded.')
for name in changed:
    print(name)
