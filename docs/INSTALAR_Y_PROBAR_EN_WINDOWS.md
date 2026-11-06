# Instalar y probar Autismo Rancagua V58 en Windows

Esta guía prepara una copia de pruebas con datos ficticios. No publica Firebase,
no ejecuta migraciones y no activa cobros automáticos. La entrada de pruebas es
`lib/main_v58_pruebas.dart`; no utilizar `lib/main.dart` para las pruebas de esta
guía.

## Herramienta que falta en el entorno actual

Falta el **SDK Flutter**, que incluye el ejecutable Flutter y el SDK Dart. Tanto
`flutter` como `dart` están ausentes del `PATH`; no basta instalar una extensión
de VS Code ni agregar paquetes con npm. Git, Java y Node sí están disponibles.

El intento de consultar el manifiesto oficial
`https://storage.googleapis.com/flutter_infra_release/flutter/releases/releases_windows.json`
falló con `CONNECT 403 Forbidden`: `storage.googleapis.com` no está en la política
de red aplicada. La solicitud del dominio guardada en el borrador del entorno no
lo habilitó todavía. No se deshabilitó TLS ni se usó una descarga alternativa para
eludir la política. Por ello en esta sesión no se puede ejecutar `flutter pub get`,
`flutter analyze`, `flutter test` ni una compilación Flutter. La descarga del
emulador Firestore depende del mismo dominio y permanece bloqueada.

## 1. Instalar Flutter y Dart en Windows

Requisitos: Windows de 64 bits compatible con el SDK estable, PowerShell y Git
para Windows. Usar un directorio propio sin espacios ni permisos administrativos
para Flutter; no instalarlo en `C:\Program Files`.

1. Instalar Git desde [git-scm.com/download/win](https://git-scm.com/download/win)
   o con este comando y después abrir una nueva terminal:

   ```powershell
   winget install --exact --id Git.Git
   ```

2. Obtener el SDK estable de una fuente oficial. La documentación de instalación
   está en [docs.flutter.dev/install](https://docs.flutter.dev/install) y el
   archivo de versiones en
   [docs.flutter.dev/install/archive](https://docs.flutter.dev/install/archive).
   Se puede descargar el ZIP estable de Windows, comprobar su SHA-256 publicado
   y extraer la carpeta `flutter` en `C:\src\flutter`. Otra instalación oficial
   reproducible es clonar la rama estable:

   ```powershell
   New-Item -ItemType Directory -Path C:\src -Force | Out-Null
   git clone --branch stable https://github.com/flutter/flutter.git C:\src\flutter
   ```

   Si `C:\src\flutter` ya existe, verificar su procedencia y su estado antes de
   actualizar; no borrar una instalación existente a ciegas. La primera ejecución
   de Flutter descargará Dart y artefactos desde los servidores oficiales.
   La red de Windows también debe permitir `storage.googleapis.com`, `pub.dev`,
   `github.com` y los destinos de dependencias indicados por Flutter Doctor.

3. Añadir `C:\src\flutter\bin` al **Path del usuario** en Configuración avanzada
   del sistema → Variables de entorno → Path → Nuevo. No sustituir el Path
   completo. Para esta terminal, sin cambiar la configuración permanente:

   ```powershell
   $env:Path = "C:\src\flutter\bin;$env:Path"
   flutter --version
   dart --version
   flutter doctor -v
   ```

   V58 declara Dart `>=3.6.0 <4.0.0`. Usar Flutter estable compatible con todas
   las versiones de plugins que resuelva `flutter pub get`; Flutter 3.27 es un
   mínimo de parte del conjunto Firebase recibido, no una garantía para todas
   las versiones futuras de los rangos de dependencias. No instalar Dart por
   separado: Flutter ya entrega su versión compatible.

4. Para editar, instalar VS Code y sus extensiones oficiales Flutter/Dart:

   ```powershell
   winget install --exact --id Microsoft.VisualStudioCode
   code --install-extension Dart-Code.flutter
   code --install-extension Dart-Code.dart-code
   ```

## 2. Preparar Android o Web

Para **Web**, instalar Chrome y confirmar que aparezca al ejecutar:

```powershell
flutter devices
```

Para **Android**, instalar Android Studio desde
[developer.android.com/studio](https://developer.android.com/studio), abrir su
SDK Manager e instalar Android SDK Platform, Build-Tools, Command-line Tools y
Platform-Tools compatibles con el proyecto. Crear un dispositivo virtual en
Device Manager. Usar Java/JDK 21 para el emulador Firestore; Android Studio incluye
su propio JDK y `flutter doctor -v` informa qué Java utiliza Flutter.

Si necesitas un JDK independiente para Firebase Emulator, instala Microsoft
OpenJDK21 desde [learn.microsoft.com/java/openjdk/download](https://learn.microsoft.com/java/openjdk/download)
o con `winget install --exact --id Microsoft.OpenJDK.21`. Después abre otra
terminal. Si se usa el JDK de Android Studio y no aparece en PATH, se puede
seleccionar solo para esta terminal:

```powershell
$env:JAVA_HOME = "$env:ProgramFiles\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
java -version
flutter doctor --android-licenses
flutter doctor -v
flutter devices
```

Si hay varias instalaciones Java, configurar `JAVA_HOME` para las herramientas
Firebase de esta terminal o usar la configuración Java de Flutter expresamente;
no cambiar configuraciones de otros proyectos sin revisarlas. No ocultar errores
de licencias ni bajar los mínimos de SDK para forzar una compilación.

Windows no permite producir ni firmar un IPA de iOS. La integración iOS y la
prueba de cámara real en iPhone requieren macOS y Xcode. Ver también
`PLATAFORMAS_Y_VALIDACION_FLUTTER.md` para permisos de cámara/galería.

## 3. Instalar Node.js 22 y herramientas Firebase locales

El backend apunta a **Node.js 22**, aunque los tests también se han ejecutado con
Node 24. Instalar una versión actual de Node 22 desde
[nodejs.org/dist/latest-v22.x](https://nodejs.org/dist/latest-v22.x/).
Para Windows x64, el siguiente ejemplo selecciona el MSI oficial de la rama 22,
verifica su SHA-256 contra `SHASUMS256.txt` del mismo origen y abre su instalador:

```powershell
$release = Invoke-RestMethod 'https://nodejs.org/dist/index.json' |
    Where-Object { $_.version -like 'v22.*' -and $_.files -contains 'win-x64-msi' } |
    Select-Object -First 1
if (-not $release) { throw 'No se encontró un instalador oficial Node 22 x64.' }
$base = "https://nodejs.org/dist/$($release.version)"
$file = "node-$($release.version)-x64.msi"
$target = Join-Path $env:TEMP $file
Invoke-WebRequest "$base/$file" -OutFile $target
$lines = (Invoke-WebRequest "$base/SHASUMS256.txt").Content -split "`n"
$line = $lines | Where-Object { $_.TrimEnd().EndsWith("  $file") } | Select-Object -First 1
if (-not $line) { throw 'El manifiesto oficial no contiene el instalador.' }
$expected = ($line -split '\s+')[0].ToLowerInvariant()
$actual = (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'Checksum incorrecto: no ejecutar el instalador.' }
Start-Process msiexec.exe -ArgumentList @('/i', $target) -Wait
```

Para Windows ARM64, utilizar el instalador ARM64 oficial correspondiente; no
copiar el comando x64. Tras la instalación, abrir una nueva terminal:

```powershell
node --version
npm.cmd --version
```

En la raíz de la copia V58 instalar las dependencias guardadas en los lockfiles:

```powershell
npm.cmd --prefix functions ci --ignore-scripts
npm.cmd --prefix firebase ci --ignore-scripts
.\firebase\node_modules\.bin\firebase.cmd --version
```

No se necesita `firebase login` ni un archivo de claves privadas para estos
emuladores locales. El proyecto de pruebas es siempre
`demo-autismo-rancagua-v58`. No ejecutar `firebase use`, `firebase deploy`,
`firebase init` ni comandos de borrado sobre el proyecto real.

## 4. Usar una copia Flutter de pruebas

El ZIP recibido no contiene `android/`, `ios/` ni `web/`. Para publicar será
necesario integrar los cambios en las plataformas originales, conservando
identificadores, firma y permisos. Para **probar sin conectarse al Firebase real**,
crear una carpeta independiente con identificadores de pruebas; no generar
plataformas encima del proyecto original.

Ejemplo, suponiendo la fuente V58 en `C:\src\autismo-rancagua-v58`:

```powershell
$source = 'C:\src\autismo-rancagua-v58'
$demo = 'C:\src\autismo-rancagua-v58-demo'
if (Test-Path $demo) { throw 'La carpeta demo ya existe: revisarla antes de continuar.' }
flutter create --platforms=web,android --project-name autismo_rancagua --org cl.autismorancagua.pruebas $demo
Copy-Item "$source\lib\*" "$demo\lib" -Recurse -Force
New-Item -ItemType Directory "$demo\assets" -Force | Out-Null
Copy-Item "$source\assets\*" "$demo\assets" -Recurse -Force
Copy-Item "$source\pubspec.yaml" "$demo\pubspec.yaml"
foreach ($folder in @('test', 'functions', 'firebase', 'scripts', 'docs')) {
    New-Item -ItemType Directory "$demo\$folder" -Force | Out-Null
    Get-ChildItem "$source\$folder" -Force |
        Where-Object { $_.Name -notin @('node_modules', '.firebase') -and $_.Name -notlike '.env*' -and $_.Name -notlike '*.log' } |
        Copy-Item -Destination "$demo\$folder" -Recurse -Force
}
Copy-Item "$source\firebase.json" "$demo\firebase.json"
Copy-Item "$source\firebase.v58.emulators.json" "$demo\firebase.v58.emulators.json"
Copy-Item "$source\firebase.v58.demo.json" "$demo\firebase.v58.demo.json"
Set-Location $demo
flutter pub get
```

No copiar `google-services.json`, `GoogleService-Info.plist`, archivos de firma,
claves, `.firebaserc` ni configuración nativa de producción a esa demo. La entrada
V58 de pruebas crea una configuración Firebase `demo-*`, enlaza los SDK con los
emuladores y debe detenerse si encuentra una aplicación Firebase predeterminada
de producción ya inicializada. No utilizar la entrada normal como alternativa si
ocurre ese error: revisar que la copia demo esté aislada.

`flutter pub get` generará el lockfile real de Flutter en esta copia. Conservarlo
tras verificar la resolución. Un `pubspec.lock` no verificado no reemplaza esta
operación.

## 5. Ejecutar las pruebas automatizadas

Desde la copia demo preparada:

```powershell
npm.cmd --prefix functions ci --ignore-scripts
npm.cmd --prefix firebase ci --ignore-scripts
npm.cmd --prefix functions run check
npm.cmd --prefix functions test
flutter analyze
flutter test
```

Las pruebas Flutter usan dobles de los servicios y no deben inicializar Firebase
real. Las pruebas del backend en memoria verifican reglas de negocio; no prueban
la concurrencia distribuida ni el compilador de Security Rules.

Para ejecutar además las pruebas sobre emuladores reales, sin datos de producción:

```powershell
.\firebase\node_modules\.bin\firebase.cmd emulators:exec `
    --project demo-autismo-rancagua-v58 `
    --config firebase.v58.emulators.json `
    --only firestore,storage `
    "npm --prefix functions run test:integration && npm --prefix firebase test"
```

Detener antes cualquier sesión de emuladores usada para navegar la demo. Estas
suites limpian el contenido de su base de datos demo local para aislar los casos;
no ejecutarlas encima de una sesión cuyos datos ficticios se quieran conservar.
No acceden a datos reales.

Este comando inicia servicios, ejecuta tests y los detiene; las suites exigen
hosts locales y un ID `demo-*`. Los fixtures de reglas de esta configuración son
solo de pruebas y no deben desplegarse ni considerarse las reglas V57 completas.
Si falla la descarga del JAR Firestore, habilitar `storage.googleapis.com` en la
red de esa máquina y reintentar después de ese cambio; no deshabilitar TLS.

El script `scripts/test-v58.ps1` ofrece estos modos sin publicar ni activar nada:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-v58.ps1 -Modo Backend -InstalarDependencias
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-v58.ps1 -Modo Flutter -InstalarDependencias
```

Otros modos del script: `Emuladores` usa el perfil demo interactivo; `Semilla`
carga los datos ficticios con cobros apagados; `App` usa la entrada de pruebas;
`PruebasSeguridad` ejecuta las suites aisladas que limpian su base demo, y `Todo`
ejecuta únicamente las pruebas unitarias Backend+Flutter. Por ejemplo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-v58.ps1 -Modo Emuladores -InstalarDependencias
# En otra terminal, con los emuladores activos:
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-v58.ps1 -Modo Semilla
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-v58.ps1 -Modo App -Dispositivo chrome
```

`ExecutionPolicy Bypass` se aplica solo a ese proceso local; no cambia la política
permanente del equipo. También se puede revisar y ejecutar el script con la
política de scripts permitida por la organización.

## 6. Probar las pantallas reales con datos ficticios

El perfil `firebase.v58.demo.json` permite navegar las pantallas con datos
ficticios; el perfil `firebase.v58.emulators.json` sirve para las suites de reglas
y deniega los módulos que no forman parte de esas pruebas. No arrancar ambos
perfiles al mismo tiempo porque usan los mismos puertos.

Abrir una terminal en la copia demo y arrancar Auth, Firestore, Storage y Functions:

```powershell
.\firebase\node_modules\.bin\firebase.cmd emulators:start `
    --project demo-autismo-rancagua-v58 `
    --config firebase.v58.demo.json `
    --only auth,firestore,storage,functions
```

Con los emuladores activos, abrir otra terminal en la misma carpeta y cargar solo
los datos ficticios iniciales. El script tiene proyecto fijo `demo-*`, exige
emuladores locales, no borra datos ni sobrescribe registros existentes. Mantiene
`configuracion_tesoreria/automatizacion_v58.habilitada` en `false`:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
# PowerShell 7: escribe una contraseña local de al menos 12 caracteres.
$env:V58_DEMO_PASSWORD = Read-Host 'Contraseña solo para cuentas ficticias' -MaskInput
node .\functions\scripts\seed-demo-v58.js
```

Cuentas de prueba, únicamente dentro del Auth Emulator:

| Rol | Correo ficticio | Contraseña ficticia |
| --- | --- | --- |
| Apoderado | `apoderado.v58@example.test` | `valor local de V58_DEMO_PASSWORD` |
| Tesorería | `tesoreria.v58@example.test` | `valor local de V58_DEMO_PASSWORD` |

Arrancar Web en Chrome:

```powershell
flutter run -d chrome --target lib/main_v58_pruebas.dart --dart-define=V58_EMULATOR_HOST=127.0.0.1
```

En un dispositivo virtual Android, el host de Windows se alcanza mediante
`10.0.2.2`:

```powershell
flutter devices
flutter run -d <ID_DEL_EMULADOR> --target lib/main_v58_pruebas.dart --dart-define=V58_EMULATOR_HOST=10.0.2.2
```

Sustituir `<ID_DEL_EMULADOR>` por el identificador mostrado, sin escribir los
signos `<` y `>`. El encabezado de la app debe indicar modo de pruebas. Un fallo
al enlazar los emuladores debe detener las operaciones; no debe provocar conexión
de respaldo al proyecto de producción.

Para probar cámara/galería en un Android físico por USB, se pueden reenviar los
puertos locales con Android Platform-Tools, evitando abrir servicios a la red LAN:

```powershell
adb devices
adb reverse tcp:9099 tcp:9099
adb reverse tcp:8080 tcp:8080
adb reverse tcp:9199 tcp:9199
adb reverse tcp:5001 tcp:5001
flutter run -d <ID_DEL_TELEFONO> --target lib/main_v58_pruebas.dart --dart-define=V58_EMULATOR_HOST=127.0.0.1
```

Para deshacer esos reenvíos al terminar:

```powershell
adb reverse --remove-all
```

Comprobar en la app:

1. Iniciar sesión como apoderado y abrir Enviar comprobante. Elegir beneficiario,
   cargo y monto parcial; probar foto, captura de galería y cancelación.
2. Enviar una sola vez. Confirmar que aparece pendiente y que todavía no reduce
   el saldo. Reintentar tras una interrupción sin crear otro comprobante.
3. Iniciar sesión como Tesorería. Comprobar el aviso de pendientes y abrir la
   imagen privada. Aprobar el abono: verificar saldo del cargo, deuda y estado.
4. Repetir una aprobación y confirmar que no vuelve a descontar. Probar dos abonos
   distintos del mismo monto y comprobar que sí se contabilizan ambos.
5. Rechazar otro comprobante con motivo. Comprobar responsable, fecha y aviso en
   el historial del apoderado.
6. Mantener cobros automáticos desactivados. Los calendarios del20/último día/día1
   se validan con las pruebas automatizadas y datos ficticios; no habilitar el
   documento de automatización para simularlos en producción.

## Lo que sigue pendiente de publicación

Esta guía no prueba que la aplicación haya compilado en una máquina Windows:
los comandos anteriores deben ejecutarse con el SDK instalado y registrar sus
resultados. También faltan la validación de los emuladores y la integración de
las reglas desplegadas reales. Los fragmentos no permiten demostrar los permisos
V57 de otros módulos por sí solos. Antes de publicar, integrar las plataformas
originales y las reglas reales, conciliar los históricos ambiguos y validar todos
los roles. El despliegue Firebase y la activación de automatización requieren una
autorización posterior independiente.
