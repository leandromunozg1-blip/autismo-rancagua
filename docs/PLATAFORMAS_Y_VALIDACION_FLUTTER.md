# Plataformas y validación Flutter de V58

## Alcance del código entregado

El ZIP V57 contiene `lib/`, `assets/`, `pubspec.yaml` y configuración Firebase,
pero no contiene los directorios `android/`, `ios/` ni `web/`, tampoco pruebas
anteriores ni `pubspec.lock`. V58 conserva esa estructura: no se generó un
proyecto nativo nuevo ni se sustituyeron identificadores, firma o configuración
de plataformas existentes.

Para producir APK/AAB, IPA o una aplicación Web hay que integrar estos cambios
en el proyecto Flutter original que sí contenga las plataformas. Conservar sus
identificadores de aplicación, archivos de Firebase, capacidades, firma,
permisos y configuraciones de compilación. Revisar la diferencia V57 → V58 antes
de incorporar archivos; no reemplazar configuraciones nativas a ciegas.

## Herramientas y dependencias

- V58 declara Dart `>=3.6.0 <4.0.0`. Las versiones Firebase utilizadas existen
  en pub.dev y requieren Flutter 3.27 o superior en el conjunto principal.
  Usar un SDK estable compatible y verificar la resolución completa de los
  plugins; algunas versiones más recientes dentro de los rangos pueden elevar
  los mínimos de Flutter o de las plataformas.
- `cloud_functions: ^6.3.2` mantiene compatibilidad con `firebase_core` major 4.
  No sustituirlo por major 7 sin una actualización coordinada de FlutterFire.
- Generar `pubspec.lock` con `flutter pub get` y conservarlo en el proyecto de
  aplicación una vez validado. No se inventó ni resolvió manualmente un lockfile.
- Las Functions de Tesorería se invocan en `southamerica-west1`; la región debe
  coincidir con el despliegue que se autorice posteriormente.

El entorno de esta revisión no tenía Flutter/Dart instalados. La descarga del
SDK desde `storage.googleapis.com/flutter_infra_release/` devolvió HTTP 403 por
la política de red. El dominio `storage.googleapis.com` quedó solicitado en el
borrador de configuración del entorno; guardar el borrador no demuestra que la
política se haya aplicado. No desactivar TLS ni usar descargas sin verificar.
Una vez permitido el dominio, obtener el SDK del canal estable oficial y comprobar
el SHA-256 publicado en el manifiesto oficial antes de extraerlo.

## Cámara y galería

El formulario V58 permite elegir cámara o galería mediante `image_picker`.
El permiso concedido, la cancelación y los errores del sistema deben probarse
en los dispositivos de destino. La autorización del sistema operativo no
sustituye la autenticación ni las reglas Firebase.

### Android

- Integrar en la plataforma Android original. Conservar `applicationId`,
  `google-services.json`, firma y configuración Gradle existentes.
- Ajustar `minSdk`, `compileSdk`, Gradle y Java al mínimo mayor exigido por las
  versiones de FlutterFire e `image_picker_android` finalmente resueltas;
  comprobarlo con el lockfile real y una compilación. No bajar mínimos para
  ocultar un fallo de dependencias.
- El selector moderno de imágenes de Android permite escoger una imagen sin
  solicitar acceso general al almacenamiento. No añadir `READ_EXTERNAL_STORAGE`,
  `WRITE_EXTERNAL_STORAGE` ni permisos amplios de fotografías solo para este flujo.
- `image_picker` utiliza la aplicación de cámara del sistema. No requiere
  declarar `CAMERA` por sí mismo; si el proyecto original ya declara ese permiso
  por otro módulo, conservar y comprobar su gestión en tiempo de ejecución.
- Verificar la recuperación después de que Android destruya la actividad
  mientras se usa cámara/galería (`ImagePicker.retrieveLostData()`). La fuente
  V58 no acredita esa recuperación en un dispositivo físico; no dar por enviado
  un archivo recuperado sin confirmar primero la cuenta, el cargo y el monto.
- Probar cámara, captura de galería, cancelación, denegación, archivo grande,
  vuelta desde segundo plano y reintento de envío con conectividad interrumpida.

### iOS

Conservar el bundle ID y `GoogleService-Info.plist` originales. Agregar o
confirmar en `ios/Runner/Info.plist`, sin borrar otras claves:

```xml
<key>NSCameraUsageDescription</key>
<string>Permite fotografiar el comprobante de pago para enviarlo a Tesorería.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Permite seleccionar una captura o imagen del comprobante de pago.</string>
```

Este flujo solo toma imágenes y no necesita permiso de micrófono. Conservar los
permisos que sí utilizan otros módulos. Verificar el deployment target exigido
por las versiones Firebase resueltas y por CocoaPods; ejecutar la instalación de
pods y la compilación en macOS con Xcode. Probar la cámara en un iPhone físico;
el simulador no valida una cámara real. Incluir JPEG/PNG y selección de fotografías
HEIC desde dispositivo físico en la comprobación de formatos admitidos por el
flujo de comprobantes.

### Web

Integrar en el `web/` original y conservar su configuración de Firebase. El
selector de galería usa el diálogo de archivos del navegador. La opción cámara
es una sugerencia de captura para navegadores compatibles: en escritorio puede
abrir el mismo selector y no garantiza una cámara dedicada. Probar Chrome/Safari
móviles reales mediante HTTPS. Si se exige captura de cámara en todos los
navegadores, hace falta un flujo específico con cámara Web y permisos; el selector
de archivos de `image_picker` no ofrece esa garantía.

Verificar el acceso autenticado a Storage, las imágenes visibles solo para su
propietario/Tesorería y la ausencia de enlaces públicos de comprobantes. No
publicar Hosting ni relajar reglas para resolver un error de acceso.

## Comprobaciones pendientes de SDK y plataformas

En la raíz de la copia V58, una vez instalado el SDK oficial y permitidos los
dominios de descarga, ejecutar:

```bash
flutter --version
flutter pub get
flutter analyze
flutter test test/tesoreria_finanzas_test.dart
flutter test
```

Las pruebas de `test/tesoreria_finanzas_test.dart` verifican que una respuesta
contable vacía sea un error, que no se inventen períodos sin cargos, que los
abonos parciales conserven sus saldos, que un cargo futuro no se marque vencido
en el cliente y que lleguen las advertencias de conciliación. Son pruebas del
adaptador de respuesta; la aplicación y deduplicación efectiva de pagos se
comprueban en las pruebas de Functions, no inicializando Firebase real desde
estos tests.

Estos comandos Flutter no pudieron ejecutarse durante esta revisión por la
ausencia del SDK y el bloqueo de descarga. No hay resultados de análisis,
pruebas Flutter ni compilación nativa aprobados. Las verificaciones de Functions
y reglas se documentan por separado con sus resultados reales.

Después de integrar las plataformas originales, ejecutar además las
compilaciones correspondientes (por ejemplo, `flutter build apk --debug` y
`flutter build web`; iOS requiere macOS). Validar de extremo a extremo con un
proyecto Firebase de pruebas o emuladores configurados explícitamente: envío,
revisión, rechazo con motivo, aprobación con abono parcial, reintento y vista de
notificaciones. No apuntar estas pruebas a producción ni desplegar cambios sin
autorización.
