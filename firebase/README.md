# Seguridad de Tesorería V58

Estos archivos son prototipos de integración, no una copia de las reglas desplegadas. El ZIP V57 no contiene reglas Firestore/Storage. No se puede demostrar que los permisos reales de otros módulos permanezcan intactos sin obtener esas reglas y probar su fusión antes de producción.

- `tesoreria.firestore.rules.fragment`: insertar dentro del `match /databases/{database}/documents` de las reglas reales después de revisar cada coincidencia existente.
- `tesoreria.storage.rules.fragment`: insertar dentro de `match /b/{bucket}/o` conservando las demás rutas.
- `emulator.*.rules`: **solo pruebas locales**; deniegan deliberadamente todos los módulos no incluidos. No desplegarlos.
- `../firebase.v58.emulators.json`: configuración local con proyecto `demo-autismo-rancagua-v58`; incluye Functions para pruebas integradas opcionales.

Las reglas combinan permisos con OR. Agregar un `allow ...: if false` no revoca otro `allow` amplio. Es obligatorio eliminar o restringir las concesiones existentes que permitan a clientes escribir recibos, aprobarlos, modificar asientos, cambiar saldos o asignarse roles. Ningún despliegue de estos archivos se ha ejecutado.

## Autoridad y compatibilidad

La autoridad de Tesorería procede de `usuarios/{uid}.rol` o `.roles`, nunca del rol enviado por el cliente ni de correos especiales. Los roles permitidos son `tesoreria`, `tesorero`, `admin_general`, `admin`, `administrador`, `admin_asociacion`, `administrador_asociacion` y `asociacion`. `activo:false` revoca el acceso. Normalizar los roles guardados a los valores oficiales antes de habilitar V58; los fragmentos no modifican perfiles.

En las reglas reales, todas las rutas de edición del perfil deben impedir cambios no autorizados de `rol`, `roles`, `activo`, UID, vínculos y ACL. El helper `v58PerfilAuthorityUnchanged()` documenta el cierre requerido para actualizaciones del propio usuario; también deben cerrarse las creaciones de perfiles con privilegios y cualquier ruta por correo o perfiles alternativos. El fixture de pruebas prohíbe todas las escrituras de perfiles para probar el límite, sin afirmar que esa sea la política V57.

Las fichas de Tesorería conservan su ID financiero (beneficiario/RUT), mientras el campo `apoderado_uid` identifica al padre autenticado. El fragmento permite al staff editar únicamente cuota mensual y texto/estado del aviso, con límites y tipos. No permite editar deuda, UID o ACL desde el cliente. Las altas/vínculos de Coordinación, acciones operativas de suspensión/cobranza, auditorías administrativas de pruebas/normalización y cargos de eventos requieren fusionar sus permisos V57 reales; no sustituirlos por una concesión global. Las acciones V58 de comprobantes se realizan exclusivamente en Functions y conservan su auditoría del servidor.

`avisos_apoderados.apoderado_id` contiene UID Auth. El propietario puede marcar `leido` y/o `aceptado` en `true`, y guardar una fecha de lectura reciente. No puede cambiar destinatario, mensaje, fecha de creación ni agregar campos. Las escrituras de avisos de otros módulos deben conservar sus autorizaciones específicas durante la integración.

Los objetos `comprobantes_v58/{uid}/{solicitudId}.jpg|png|webp` son privados: propietario crea una sola vez, propietario/staff leen, ningún cliente modifica ni elimina. La extensión y MIME declarado deben coincidir y el tamaño debe estar entre 1 byte y 10 MiB. Rules no interpreta los bytes de la imagen; Functions también debe verificar los metadatos y la relación con cuenta/cargo antes de aceptar el comprobante. Las imágenes antiguas conservan las rutas y permisos de V57; revisar acceso público previo durante el despliegue sin borrar datos.

## Pruebas locales

Desde `firebase/`:

```sh
npm ci --ignore-scripts
npm run test:emulators
```

El runner exige hosts de emulador locales y usa un ID `demo-`; no conecta a producción. Prueba consultas por propietario, pendientes de Tesorería, roles inactivos, prohibición de revisión/contabilidad cliente, lectura de avisos, protección de contenido y UID, cuota validada, autoescalamiento y almacenamiento privado create-only con MIME/tamaño.

`npm test` ejecuta directamente `node test/rules.test.js`, que registra los casos mediante `node:test`. Funciona en Node 22 y 24 sin opciones experimentales ni procesos de aislamiento; el resumen debe mostrar los 14 casos individuales, no solo el archivo. Requiere que los emuladores estén ejecutándose y sus variables locales presentes.

Antes de producción, ejecutar además pruebas de regresión con las reglas reales de todos los módulos y verificar autorización IAM de la cuenta de servicio Functions. Estas pruebas aisladas no certifican la seguridad del proyecto desplegado.

La auditoría cliente de ingresos institucionales V57 conserva `create` para staff con UID/correo autenticados, fecha del servidor y acción/esquema acotados. No admite reescritura ni auditoría falsa de aprobación V58. Los esquemas de auditoría de los módulos administrativos de pruebas/normalización requieren integración separada con sus permisos reales.

El propietario de la ficha puede conservar la acción V57 “enterado” actualizando únicamente `aviso_visto_por_apoderado=true` y `fecha_lectura_aviso` con timestamp del servidor; no puede borrar el aviso ni tocar saldo/campos extra.

## Resultado de la validación en esta sesión

`npm install --ignore-scripts --no-audit --no-fund` completó y generó lockfile; `node --check test/rules.test.js` y validación JSON/igualdad fragmentos-fixtures pasaron. `npm run test:emulators` no logró descargar `cloud-firestore-emulator-v1.22.0.jar` desde `storage.googleapis.com`, bloqueado por la política de red. Las 14 pruebas de Rules permanecen **sin ejecutar**; no hay validación sintáctica del compilador de Rules ni afirmación de aprobación de las reglas. Reintentar después de aplicar el dominio requerido en el entorno.

Las reservas de imagen `tesoreria_comprobantes_huellas_v58` son privadas y exclusivas del servidor: ningún cliente lee, fabrica ni libera huellas. Los logs `tesoreria_procesos_v58` y el documento `configuracion_tesoreria/automatizacion_v58` son de lectura solo para staff y escritura exclusiva Admin SDK. El fragmento no otorga permisos sobre `montos_oficiales` ni sobre otros documentos de configuración V57. La aplicación no puede habilitar la automatización global.
