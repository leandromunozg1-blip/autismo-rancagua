# Autismo Rancagua V58 — entrega de código fuente

Versión Flutter: `1.0.58+58`. Base: ZIP V57 aportado por el usuario. Esta entrega contiene implementación local, pruebas y configuración propuesta. No es un APK/IPA compilado ni una publicación Firebase. No se han consultado, borrado ni migrado datos reales.

## Implementación

| Solicitud | Resultado en el código V58 |
| --- | --- |
| Cobros el día20 | Scheduler en Firebase, 09:00 `America/Santiago`: crea el próximo mes con ID por cuenta+período. Del21 al fin de mes recupera ejecuciones fallidas sin duplicar. Solo cuentas activas y cuota explícita positiva; sin $5.000 por defecto. |
| Recordatorios hasta fin de mes | Aviso interno diario del20 al último día por el saldo aún pendiente de la mensualidad siguiente. Identidad por fecha/cuenta/destinatario. |
| Cobranza día1 | Solo cargos vencidos con saldo positivo, con abonos aprobados ya descontados. No se emite para saldo cero. |
| Contabilidad | Libro de cargos explícitos, pagos deduplicados por referencia y asignación al cargo. Sin cuotas desde fechas, sin descartes por monto igual, sin ignorar una colección entera de pagos. |
| Revisión | Una callable transaccional para ambas pantallas: estado, pago, abono del cargo, caché, responsable UID/correo, fecha, auditoría y aviso se confirman juntos. Rechazo exige motivo. |
| Comprobante | Beneficiario y cargo explícitos, foto o galería, JPEG/PNG/WebP privados, límite10MiB, validación de monto y errores de permisos. Reintentos del mismo envío no duplican comprobantes. |
| Duplicados | IDs de cargos/pagos/avisos estables y reserva del hash de la misma imagen por cuenta. Otra foto de la misma transferencia requiere verificación bancaria humana. |
| Notificaciones | Bandeja interna persistente para Tesorería y avisos existentes para el apoderado. No incluye FCM/push, SMS ni correo. Los avisos históricos muestran saldo al emitir y se contrastan con el saldo actual al consultarlos. |
| Otros módulos | Los archivos originales de roles/permisos y módulos ajenos siguen idénticos. No se reemplazaron reglas desplegadas desconocidas. |

La automatización global queda apagada hasta su activación autorizada. La lógica está preparada, pero aún no funciona en producción porque no se desplegó Firebase.

## Históricos y conservación

Los saldos V57 podían ser ficticios o incompletos. Las discrepancias, pagos sin cargo inequívoco, duplicados contradictorios y UIDs ambiguos generan advertencias y bloquean cobros/aprobaciones automáticas de esa cuenta. No se convierte `monto_deuda` en una deuda nueva ni se inventan aperturas. Los créditos históricos se conservan como evidencia. Los registros requieren conciliación supervisada con documentación bancaria; no hay un script de migración masiva.

El nuevo formulario no acepta abonos mayores al saldo de un cargo. Si una transferencia debe cubrir varios cargos o incluye un excedente, se necesita revisión de Tesorería y un registro de imputación autorizado: esta versión no reparte automáticamente un comprobante entre varias cuentas/cargos.

## Validación ejecutada

- **43 pruebas unitarias de backend aprobadas** en Node22.23.4 y Node24.22.1: calendario Chile, DST, bisiesto, cambio de año, contabilidad, abonos, identidades, carreras simuladas, rollback, autorización, imagen repetida, recordatorios y cobranza.
- Las pruebas del servicio usan Firestore en memoria con transacciones serializadas. No prueban la concurrencia distribuida real ni la compilación de reglas. Las pruebas de dominio ejecutan la lógica pura de producción.
- `npm --prefix functions run check`: aprobado.
- Sintaxis Dart comprobada con parser tree-sitter en60 archivos, sin errores. No equivale a resolver dependencias ni a `flutter analyze`.
- `python3 scripts/verify-v57-scope.py`:91 archivos originales V57 idénticos;6 archivos originales cambiados dentro del alcance declarado. El manifiesto SHA-256 permite repetir la comprobación.
- **Sin ejecutar**:5 pruebas Flutter, análisis Flutter, compilaciones nativas/web,14 pruebas de Rules y3 pruebas de integración sobre Firestore Emulator. La descarga oficial del SDK Flutter y del emulador Firestore está bloqueada por la política de red (`storage.googleapis.com`). No hay un resultado aprobado de esas suites.

El ZIP original no incluye `android/`, `ios/`, `web/` ni `pubspec.lock`. No se generaron identificadores, configuración de firma ni lockfile ficticios para aparentar una compilación completa.

## Repetir pruebas

Desde la raíz del proyecto, con Node22:

```sh
npm --prefix functions ci --ignore-scripts
npm --prefix functions run check
npm --prefix functions test
python3 scripts/verify-v57-scope.py
```

Con el dominio oficial de descarga habilitado e Internet de dependencias disponible:

```sh
npm --prefix firebase ci --ignore-scripts
firebase/node_modules/.bin/firebase emulators:exec --project demo-autismo-rancagua-v58 --config firebase.v58.emulators.json --only firestore,storage "npm --prefix functions run test:integration && npm --prefix firebase test"
```

Las pruebas integradas del servicio usan Firestore Emulator real y un proveedor de metadatos de imágenes simulado; Storage y sus ACL se prueban por separado en la suite de Rules. El ID `demo-*` y las comprobaciones de hosts locales impiden que esas pruebas se conecten a producción. La configuración `firebase.v58.emulators.json` y las reglas `firebase/emulator.*.rules` son exclusivamente locales: **no desplegarlas**.

Con Flutter estable compatible instalado y las plataformas originales integradas:

```sh
flutter pub get
flutter analyze
flutter test
```

Conservar el lockfile resuelto para la aplicación y probar cámara/galería en dispositivos físicos. Ver `PLATAFORMAS_Y_VALIDACION_FLUTTER.md`.

## Configuraciones pendientes para producción

1. **Reglas reales y permisos**: obtener las reglas desplegadas Firestore/Storage, fusionar los fragmentos V58 y ejecutar regresión de todos los módulos. Proteger `usuarios/{uid}.rol/roles` y vínculos contra autoasignación. Cerrar cualquier concesión amplia superpuesta a las escrituras contables. No desplegar el fixture que deniega los demás módulos.
2. **Conciliación y vínculos**: revisar cuotas, cuentas de beneficiarios, UIDs autorizados, cargos, fechas y pagos históricos. Resolver advertencias con evidencia. Nunca activar simplemente cambiando `version_contable` ni eliminando registros.
3. **Proyecto Firebase**: confirmar edición/ubicación de Firestore, bucket predeterminado, región `southamerica-west1`, plan Blaze, APIs Functions/Scheduler/Eventarc y permisos IAM mínimos del servicio. No se necesitan claves privadas dentro del código.
4. **Flutter y plataformas**: aplicar acceso a `storage.googleapis.com` en el entorno, completar pruebas pendientes e integrar `android/ios/web` originales. Verificar permisos iOS y cámara/galería según la guía de plataformas. La publicación del entorno de desarrollo es distinta del despliegue Firebase.
5. **Despliegue autorizado**: solo después de aprobación, desplegar Functions V58 y las reglas integradas revisadas. El proyecto ya declara el codebase `tesoreria-v58`; no se ejecutó `firebase deploy` ni se modificó Hosting.
6. **Activación supervisada**: tras validación, un responsable autorizado puede crear `configuracion_tesoreria/automatizacion_v58` con `habilitada:true`. Supervisar `tesoreria_procesos_v58` y Cloud Logging, probar cargos/avisos en una cuenta de prueba y confirmar horario09:00 Chile. Ausencia/false mantiene el programador sin efectos.

Detalles de APIs y calendario: `../functions/README.md`. Auditoría previa: `DIAGNOSTICO_V57.md`. Reglas y compatibilidad: `../firebase/README.md`.
