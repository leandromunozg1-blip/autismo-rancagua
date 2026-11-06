[CmdletBinding()]
param(
    [ValidateSet('Backend', 'Flutter', 'PruebasSeguridad', 'Emuladores', 'Semilla', 'App', 'Todo')]
    [string]$Modo = 'Backend',
    [switch]$InstalarDependencias,
    [string]$Dispositivo = 'chrome',
    [ValidateSet('127.0.0.1', '10.0.2.2')]
    [string]$HostEmulador = '127.0.0.1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$demoProject = 'demo-autismo-rancagua-v58'

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments = @())
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "El comando fallo con codigo ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
    }
}

function Require-Command {
    param([string]$Name, [string]$Instruction)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Falta ${Name}. $Instruction" }
    return $command.Source
}

function Require-Node22 {
    $script:nodeExe = Require-Command 'node.exe' 'Instala Node.js 22 desde nodejs.org/dist/latest-v22.x/.'
    $script:npmExe = Require-Command 'npm.cmd' 'Abre otra terminal despues de instalar Node.js 22.'
    $version = & $script:nodeExe --version
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v22[.]') {
        throw "Se necesita Node.js 22 para reproducir el runtime Firebase. Version encontrada: $version"
    }
    Write-Host "Runtime backend: $version"
}

function Require-Flutter {
    $script:flutterExe = Require-Command 'flutter.bat' 'Instala el SDK oficial Flutter y agrega C:\src\flutter\bin al Path. Consulta docs/INSTALAR_Y_PROBAR_EN_WINDOWS.md.'
}

function Install-BackendDependencies {
    if ($InstalarDependencias) {
        Invoke-Checked $script:npmExe @('--prefix', 'functions', 'ci', '--ignore-scripts')
    }
}

function Require-LocalFirebase {
    if ($InstalarDependencias) {
        Invoke-Checked $script:npmExe @('--prefix', 'firebase', 'ci', '--ignore-scripts')
    }
    $script:firebaseExe = Join-Path $projectRoot 'firebase\node_modules\.bin\firebase.cmd'
    if (-not (Test-Path $script:firebaseExe)) {
        throw 'Falta Firebase CLI local. Ejecuta npm.cmd --prefix firebase ci --ignore-scripts.'
    }
}

function Verify-PackageMetadata {
    $pubspec = Get-Content (Join-Path $projectRoot 'pubspec.yaml') -Raw
    if ($pubspec -notmatch '(?m)^version:\s*1[.]0[.]58[+]58\s*$') {
        throw 'La copia no declara la version Flutter V58 esperada: 1.0.58+58.'
    }
    $functionsPackage = Get-Content (Join-Path $projectRoot 'functions\package.json') -Raw | ConvertFrom-Json
    if ($functionsPackage.engines.node -ne '22') { throw 'El backend debe declarar runtime Node22.' }
    foreach ($name in @('firebase.json', 'firebase.v58.emulators.json', 'firebase.v58.demo.json')) {
        $null = Get-Content (Join-Path $projectRoot $name) -Raw | ConvertFrom-Json
    }
    Write-Host 'Version V58, runtime Node22 y configuraciones JSON verificados.'
}

function Verify-V57Scope {
    $manifestPath = Join-Path $projectRoot 'docs\V57_FILES_SHA256.json'
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $allowed = @(
        'pubspec.yaml', 'firebase.json', 'lib/main.dart', 'lib/tesoreria.dart',
        'lib/services/tesoreria_finanzas_service.dart',
        'lib/pages/tesoreria/detalle_financiero_apoderado_page.dart',
        'lib/app_roles.dart',
        'lib/core/auth/app_roles.dart',
        'lib/firebase_options.dart',
        'lib/pages/admin/normalizar_firebase_page.dart',
        'lib/pages/coordinacion/beneficiarios_contactos_page.dart',
        'lib/pages/admin/carga_masiva_real_page.dart'
    )
    $unchanged = 0
    $changed = 0
    foreach ($property in $manifest.PSObject.Properties) {
        if ($property.Name -eq 'assets/images/tesoreria_v25/referencia_diseno_v25e.png') { continue }
        $original = Join-Path $projectRoot $property.Name
        if (-not (Test-Path $original -PathType Leaf)) { throw "Falta un archivo original V57: $($property.Name)" }
        $actualHash = (Get-FileHash $original -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $property.Value) {
            if ($property.Name -notin $allowed) { throw "Cambio fuera del alcance V58: $($property.Name)" }
            $changed++
        } else { $unchanged++ }
    }
    Write-Host "V57: $unchanged archivos originales intactos, $changed cambios dentro del alcance."
}

Push-Location $projectRoot
try {
    # No commands in this script deploy, select a production project or enable charges.
    Verify-PackageMetadata
    if ($Modo -in @('Backend', 'Todo')) {
        Require-Node22
        Install-BackendDependencies
        Invoke-Checked $script:npmExe @('--prefix', 'functions', 'run', 'check')
        Invoke-Checked $script:npmExe @('--prefix', 'functions', 'test')
        Verify-V57Scope
    }
    if ($Modo -in @('Flutter', 'Todo')) {
        Require-Flutter
        Invoke-Checked $script:flutterExe @('--version')
        if ($InstalarDependencias) {
            Invoke-Checked $script:flutterExe @('pub', 'get')
        }
        Invoke-Checked $script:flutterExe @('analyze')
        Invoke-Checked $script:flutterExe @('test')
    }
    if ($Modo -eq 'PruebasSeguridad') {
        Require-Node22
        Install-BackendDependencies
        Require-LocalFirebase
        Write-Warning 'Estas suites limpian SOLO los datos de los emuladores demo. Deten la sesion demo interactiva antes de continuar.'
        Invoke-Checked $script:firebaseExe @(
            'emulators:exec', '--project', $demoProject,
            '--config', 'firebase.v58.emulators.json', '--only', 'firestore,storage',
            'npm --prefix functions run test:integration && npm --prefix firebase test'
        )
    }
    if ($Modo -eq 'Emuladores') {
        Require-Node22
        Install-BackendDependencies
        Require-LocalFirebase
        Invoke-Checked $script:firebaseExe @(
            'emulators:start', '--project', $demoProject,
            '--config', 'firebase.v58.demo.json', '--only', 'auth,firestore,storage,functions'
        )
    }
    if ($Modo -eq 'Semilla') {
        Require-Node22
        Install-BackendDependencies
        if ([string]::IsNullOrWhiteSpace($env:V58_DEMO_PASSWORD)) {
            throw 'Define V58_DEMO_PASSWORD solo en esta terminal (minimo 12 caracteres). No la guardes en Git.'
        }
        $savedFirestoreHost = $env:FIRESTORE_EMULATOR_HOST
        $savedAuthHost = $env:FIREBASE_AUTH_EMULATOR_HOST
        try {
            $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
            $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
            Invoke-Checked $script:nodeExe @('functions/scripts/seed-demo-v58.js')
        } finally {
            $env:FIRESTORE_EMULATOR_HOST = $savedFirestoreHost
            $env:FIREBASE_AUTH_EMULATOR_HOST = $savedAuthHost
        }
    }
    if ($Modo -eq 'App') {
        Require-Flutter
        if (-not (Test-Path 'lib/main_v58_pruebas.dart')) { throw 'Falta la entrada V58 de pruebas.' }
        if ((Test-Path 'android/app/google-services.json') -or (Test-Path 'ios/Runner/GoogleService-Info.plist')) {
            throw 'Usa una copia demo aislada sin archivos Firebase nativos de produccion; consulta la guia Windows.'
        }
        Invoke-Checked $script:flutterExe @(
            'run', '-d', $Dispositivo, '--target', 'lib/main_v58_pruebas.dart',
            "--dart-define=V58_EMULATOR_HOST=$HostEmulador"
        )
    }
} finally {
    Pop-Location
}
