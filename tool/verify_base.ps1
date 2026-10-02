param(
    [switch]$BuildWeb,
    [switch]$BuildReleaseApk
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot

try {
    foreach ($requiredFile in @(
        'pubspec.yaml',
        'assets/data/ecopoints_geosampa.geojson',
        'supabase/ECOSCAN_SUPABASE_NOVO.sql',
        'config/mobile.json',
        'assets/data/yoloe_classes.json',
        'assets/models/ecoscan_yoloe26n_w8a32.tflite',
        'lib/services/auth_session.dart',
        'android/app/src/main/AndroidManifest.xml'
    )) {
        if (-not (Test-Path $requiredFile)) {
            throw "Arquivo ausente: $requiredFile"
        }
    }

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter SDK não encontrado no PATH.'
    }

    Write-Host "Flutter usado:"
    where.exe flutter
    flutter --version

    function Invoke-Flutter {
        & flutter @args
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter falhou: $args"
        }
    }

    Invoke-Flutter clean
    Invoke-Flutter pub get
    Invoke-Flutter analyze
    Invoke-Flutter test

    if ($BuildWeb) {
        Invoke-Flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
    }

    if ($BuildReleaseApk) {
        Invoke-Flutter build apk --release --dart-define-from-file=config/mobile.json
    }

    Write-Host 'EcoScan 3.4.2: verificações concluídas.'
}
finally {
    Pop-Location
}
