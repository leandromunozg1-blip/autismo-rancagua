# Diagnóstico previo a V58

Fuente: `AUTISMO_RANCAGUA_V57_ROLES_COPIA_FIX.zip`, inspeccionado antes de editar código. Las referencias corresponden al ZIP V57, no a los archivos V58. No se consultaron ni modificaron datos de producción.

## Causas comprobadas

| Problema | Causa en V57 |
| --- | --- |
| Mensualidades inexistentes | `lib/services/tesoreria_finanzas_service.dart:221–264` rellena todos los meses desde la primera cuota o la fecha de creación de la ficha, aunque no haya asientos. También omite cargos futuros y anticipos. |
| Pagos aprobados sin descuento | Un solo ingreso en `tesoreria_movimientos` hace que se ignoren todos los registros de `tesoreria_pagos` (`:194–218`). En la pantalla antigua se busca `uid == Auth UID`, pero Coordinación guarda el RUT del beneficiario en `uid` y el Auth UID en `apoderado_uid` (`coordinacion_home_page.dart:423–427`). |
| Abonos iguales perdidos | El servicio deduplica por monto y mes (`:167–181`), no por identidad del comprobante o asiento. Dos transferencias iguales pueden ser pagos distintos. |
| Descuentos duplicados o revisión incompleta | Hay dos aprobadores (`tesoreria.dart:1044` y `main.dart:2843`). Ambos cambian el estado antes de contabilizar, sin transacción. El principal crea pagos con `.add()` y no comprueba que siga pendiente. Un fallo o concurrencia deja aprobación sin asiento o pagos repetidos. |
| Eventos parcialmente pagados figuran pagados | `tesoreria.dart:1089–1102` marca todo el evento pagado con cualquier abono y reemplaza `monto_pagado`. El cálculo general lee el pago de evento, pero no su cargo. |
| No hay automatización real | `_verificarCargaAutomaticaMensual` no se invoca y, aun invocada, depende del reloj local y del último día del mes. No hay Functions ni Scheduler en el ZIP. |
| Cargos repetidos/injustificados | `_procesarMensualidades` usa un marcador escrito antes del cargo y luego `.add()`, sin transacción ni filtro de activos; aplica $5.000 por defecto. |
| Cuenta ambigua | El comprobante guarda UID/email pero no beneficiario, cargo ni período (`main.dart:2559`). Las búsquedas por correo/nombre mezclan cuentas cuando hay varios beneficiarios. Se acepta monto cero. |
| Rechazo incompleto y sin avisos | Falta motivo obligatorio y no se notifica ni la llegada de comprobantes a Tesorería ni el resultado al apoderado. |
| Reportes distintos al saldo | El detalle suma pagos y movimientos del mismo ingreso dos veces, incluye pendientes/rechazados y silencia errores de consultas. Abrir Tesorería recalcula y escribe todas las fichas con ese cálculo. |
| Deuda histórica sin trazabilidad | Coordinación incrementa `monto_deuda` sin asiento (`coordinacion_home_page.dart:435–436`). Ese caché no permite reconstruir cargos reales de forma segura. No se convertirá automáticamente en mensualidades ni en saldos de apertura. |

## Límites del material recibido

El ZIP no trae reglas Firestore/Storage, Functions, índices, lockfile, pruebas ni carpetas Android/iOS/web. Por ello no se puede auditar la seguridad desplegada ni confirmar permisos de cámara o compilar un binario nativo únicamente con este archivo. Cámara y galería ya están parcialmente implementadas en móvil; se necesita completar validación, tratamiento de errores y asociación contable, no atribuir su ausencia a Firebase.

Los avisos existentes son internos en `avisos_apoderados`, consultados por UID de Auth. No existe FCM ni registro de tokens. Se conserva ese canal y no se promete push en segundo plano.

## Decisiones para V58

- Backend confiable con autorización, cargos explícitos, IDs estables y revisión transaccional. Nunca inferir cuotas desde fechas ni deduplicar pagos por monto.
- Procesos programados con `America/Santiago`, sin apertura de app; activación de producción deliberada, inicialmente apagada.
- Imputación a cuenta de beneficiario y cargo concreto, con abonos parciales. Históricos ambiguos se señalan para conciliación; no se borran ni se migran automáticamente.
- Fragmentos de reglas para integrar con las reglas reales. No reemplazar reglas desconocidas ni permisos de otros módulos. Pruebas aisladas en proyecto de emulador `demo-*`.
- Conservar código y permisos de los módulos ajenos. No ejecutar limpieza de datos, migración ni despliegue.
