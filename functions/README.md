# Tesorería V58 — backend preparado, sin desplegar

Este directorio contiene Cloud Functions v2 para Node.js 22. No se ha ejecutado ningún despliegue, migración ni operación sobre datos reales. La configuración y las reglas desplegadas en V57 no venían en el ZIP y deben contrastarse antes de producción.

## Ejecución y pruebas locales

Desde `functions/`:

```sh
npm ci --ignore-scripts
npm run check
npm test
```

`test/domain.test.js` cubre calendario de Chile, DST, febrero bisiesto, cambio de año, cargos explícitos, abonos, duplicados por referencia, créditos y errores históricos. `test/service.memory.test.js` usa un adaptador de Firestore en memoria: comprueba las operaciones completas y el rollback de transacciones serializadas. Esas pruebas no sustituyen la validación de índices, IAM, Storage, reglas o concurrencia distribuida del emulador/servicio real. La prueba de carga y los canales de cámara móviles también requieren dispositivos/configuración nativa.

`scripts/test.js` carga los archivos de pruebas con el harness nativo `node:test` dentro del mismo proceso. Funciona en Node.js 22 y permite que este entorno ejecute y muestre cada caso y aserción sin depender del protocolo de procesos secundarios del runner. No cambia la lógica de las pruebas.

## API y permisos

Funciones ubicadas en `southamerica-west1`, con Firebase Auth obligatorio:

- `tesoreriaConsultar({cuentaId?})`: sin cuenta devuelve `{cuentas, fechaChile}`. Con cuenta devuelve `{cuenta, resumen, cargos, pagos, advertencias, fechaChile}`. Solo lectura; no escribe cachés al abrir la pantalla.
- `tesoreriaEnviarComprobante({solicitudId, cuentaId, cargoId, monto, storagePath, observacion})`: devuelve `{comprobanteId}`. El UID autenticado debe ser apoderado autorizado de la cuenta. `solicitudId` debe contener 16–100 caracteres alfanuméricos, `_` o `-`, y debe mantenerse en los reintentos. Un identificador reutilizado con otro contenido produce error.
- `tesoreriaRevisarComprobante({comprobanteId, decision, motivo?, cuentaId?, cargoId?})`: solo Tesorería/administradores. `decision` es `aprobado` o `rechazado`; rechazo requiere motivo de 3–1000 caracteres. Cuenta/cargo solo se seleccionan para legados que carecen de esas referencias. Los nuevos no pueden reasignarse. Una segunda aprobación no aplica otro descuento.

La autoridad procede exclusivamente de `usuarios/{uid}`: `rol`/`roles` con Tesorería, administrador general o administrador de asociación y sus alias de V57; `activo:false` impide revisar. No se usan emails especiales de prueba. Las reglas existentes deben impedir que los usuarios se asignen esos roles.

Las cuentas se vinculan por `apoderado_uid`, `uid_apoderado` o `apoderados_uids_autorizados`. La coincidencia exacta `uid == request.auth.uid` permite leer una ficha antigua que guardaba un UID Auth real. Nunca se atribuyen cuentas usando email, nombres ni RUT del apoderado. Para avisar a un `uid` antiguo, el programador comprueba que exista en Authentication: en V57 ese campo a menudo contiene el RUT del beneficiario.

## Cargos, pagos y evidencias

Los cargos son documentos existentes en `tesoreria_movimientos` (ingresos excluidos) o `tesoreria_evento_cargos`. `cargo_id` siempre contiene la ruta completa, por ejemplo `tesoreria_movimientos/mensual_v58_...`. Las mensualidades requieren período explícito `YYYY-MM`; vencen el último día del mes anterior. Para otros cargos se exige un vencimiento verificable antes de emitir cobranza; se reconoce también `fecha_limite` de eventos V57. Un cargo sin fecha se expone con `sin_vencimiento:true`: admite abonos identificados, pero nunca se incluye en saldo vencido ni cobranza automática. No se construyen cuotas desde fechas de creación, no se aplica un monto por defecto y no se crea apertura desde el caché `monto_deuda`.

Un recibo aprobado crea exactamente un documento `tesoreria_pagos/pago_comprobante_{id}` y actualiza, en la misma transacción, el comprobante, `monto_pagado`/`saldo_pendiente` del cargo, caché de la cuenta, auditoría y notificación del apoderado. Los abonos parciales quedan como `parcial` en movimientos o `abono` en cargos de evento, conservando el estado que usa la interfaz V57; solo saldo cero pasa a `pagado`. Por ahora un nuevo abono superior al saldo del cargo se rechaza, sin perder ni truncar excedentes históricos.

La consulta concilia pagos, movimientos de ingreso y comprobantes aprobados por referencia explícita al comprobante/asiento, nunca por monto+mes. Dos abonos iguales con referencias distintas son dos pagos. El período explícito o `evento_id` de un pago legado solo se usa si identifica un cargo único de esa cuenta; la fecha del depósito/aprobación no determina a qué obligación pertenece.

`resumen.deuda` expresa cargos explícitos menos pagos reconocidos; `saldoVencido` y `cuotasMorosas` consideran únicamente cargos vencidos con saldo. `credito` conserva excedentes y `pagosNoImputados` conserva pagos sin imputación segura. Si `deudaNoConciliada` es verdadero, las cifras son información de diagnóstico y no una deuda confirmada: las advertencias explican el dato que debe revisarse. Un abono guardado en el cargo sin asiento equivalente se expone como evidencia, sin sumarlo encima de un posible pago duplicado.

Las inconsistencias históricas bloquean aprobación y cobranza automática. No se borran, corrigen ni migran documentos de forma silenciosa. La conciliación de documentos ambiguos debe hacerse en una tarea autorizada y revisada con respaldo bancario. Si existe `advertencias_conciliacion_v58` en una cuenta, también bloquea las operaciones; un responsable debe retirar esos avisos explícitos solo después de verificar la corrección de su causa. Este backend no los limpia automáticamente.

Si una ficha anterior a V58 declara `monto_deuda` y este difiere del libro explícito, también se detiene para revisión: ni el caché ni el libro incompleto se consideran una apertura cierta. Para regularizarla hay que identificar con documentos bancarios cada cargo/pago, resolver las referencias ambiguas y acordar los saldos derivados. Solo después de esa revisión puede un responsable registrar el caché correcto y `version_contable:58`. Cambiar esa versión por sí sola no es una conciliación, y este backend no incluye un script que lo haga en masa.

## Comprobantes privados y duplicación

El archivo se sube previamente a `comprobantes_v58/{uid}/{solicitudId}.jpg`, `.png` o `.webp`. El backend verifica el nombre, propietario, tamaño de 1 byte a 10 MiB, MIME, generación de objeto y MD5 proporcionados por Storage. Los archivos deben ser inmutables y privados mediante reglas. No se guardan URLs de descarga públicas para nuevos comprobantes.

`tesoreria_comprobantes_huellas_v58/{hash}` reserva transaccionalmente la combinación cuenta+MD5 de Storage. Evita volver a descontar por la misma imagen exacta aunque se use otro ID de solicitud. La reserva se verifica al aprobar. Un comprobante rechazado permite volver a enviar la misma imagen con datos corregidos; su auditoría permanece. Distintas fotografías de una misma transferencia tienen bytes diferentes: comprobar la transferencia bancaria y su referencia sigue siendo una responsabilidad humana de Tesorería.

La notificación interna de Tesorería se almacena en `tesoreria_notificaciones/comprobante_{id}`. Se crea al enviar y también mediante el trigger idempotente `tesoreriaComprobantePendiente` para legados. Revisar la marca resuelta. Los resultados se guardan en `avisos_apoderados` con `apoderado_id` igual al UID de quien envió. Se registra responsable, fecha y motivo de rechazo. No se implementó un canal FCM, SMS, email o WhatsApp; la entrega es la bandeja interna de la aplicación.

## Calendario en Firebase

`tesoreriaCalendarioChile` usa Cloud Scheduler diariamente a las 09:00, zona `America/Santiago`. La fecha efectiva se obtiene de `event.scheduleTime`, por lo que cambios de hora y reintentos no dependen del dispositivo:

- Del día 20 al fin del mes: genera el mes siguiente una sola vez por cuenta+período y registra recordatorios diarios por el saldo restante.
- El día 1: emite cobranza únicamente sobre cargos vencidos cuyo saldo aún es positivo. Un pago aprobado antes del proceso reduce/elimina el importe a avisar.

La generación exige cuenta explícitamente activa y `cuota_mensual` positiva. Un cargo mensual legado del mismo período impide crear otro. Si el marcador `ultimo_mes_procesado` existe sin cargo, se detiene para revisión. La ejecución diaria del 21 en adelante recupera una generación del día 20 que haya fallado; no inventa mensualidades retroactivas de meses omitidos.

Los cargos y avisos tienen IDs determinísticos. Cada operación revalida la contabilidad dentro de su transacción. Los resultados/fallos por fecha+cuenta+acción quedan en `tesoreria_procesos_v58`; los fallos se vuelven a intentar hasta tres veces por Scheduler, con backoff de 60–3600 segundos y ventana de seis horas. Las cuentas restantes siguen procesándose. Ante fallos permanentes, los documentos muestran `estado:fallido`, el código y la causa; deben revisarse y puede repetirse el job conservando la misma fecha efectiva. La cobranza del día 1 no se transforma en avisos diarios de morosidad; los reintentos conservan su fecha original.

## Requisitos antes de producción

1. Revisar las cuentas, cuotas explícitas, UIDs autorizados, cargos/vencimientos, pagos históricos y advertencias. No activar hasta conciliar los bloqueos; no hay migración automática ni borrados.
2. Confirmar el proyecto, edición/ubicación de Firestore y bucket. Configurar el bucket predeterminado en Admin/Firebase; la región del cliente debe coincidir con `southamerica-west1` o adaptarse expresamente en ambas partes.
3. Fusionar cuidadosamente los fragmentos de reglas V58 con las reglas reales, manteniendo los demás módulos. Las colecciones financieras, auditoría, procesos, reservas y avisos deben ser de escritura exclusiva del backend. Las reglas de rol deben evitar autoasignación. Validar con emuladores antes del despliegue.
4. Preparar plan Blaze, Cloud Functions/Cloud Scheduler/Eventarc/Firestore/Storage y los permisos mínimos de sus cuentas de servicio. Configurar alertas de logs/fallos. No hace falta almacenar claves administrativas dentro del proyecto.
5. Revisar y autorizar por separado el despliegue. Por defecto no se ejecutan automatizaciones aunque la función se despliegue: solo se habilitan cuando un responsable cree `configuracion_tesoreria/automatizacion_v58` con `habilitada:true` después de la revisión.
6. Verificar IAM, transacciones concurrentes reales, notificaciones internas, reloj/horario y captura de imágenes en pruebas integrales y dispositivos Android/iOS antes de habilitar a todos.

Una instancia en ejecución, una publicación de app y una automatización habilitada son estados distintos. Este código preparado y sus pruebas locales no implican que ninguno de esos cambios se haya publicado.
