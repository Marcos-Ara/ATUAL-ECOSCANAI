$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$migrationRoot = Join-Path $projectRoot 'supabase\migrations'
$outputPath = Join-Path $projectRoot 'supabase\ECOSCAN_SUPABASE_NOVO.sql'
$migrations = Get-ChildItem -LiteralPath $migrationRoot -Filter '*.sql' |
    Sort-Object Name

if ($migrations.Count -eq 0) {
    throw "Nenhuma migração encontrada em $migrationRoot"
}

$builder = [System.Text.StringBuilder]::new()
[void]$builder.AppendLine('-- EcoScan AI: instalação inicial consolidada do banco Supabase.')
[void]$builder.AppendLine('-- Execute este arquivo uma vez em um projeto sem tabelas do EcoScan.')
[void]$builder.AppendLine('-- Não execute também as migrações individuais desta pasta.')
[void]$builder.AppendLine('begin;')

foreach ($migration in $migrations) {
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine("-- >>> MIGRATION $($migration.Name)")
    $content = [System.IO.File]::ReadAllText($migration.FullName)
    $content = [regex]::Replace(
        $content,
        '(?im)^\s*(begin|commit)\s*;\s*(?:--[^\r\n]*)?\r?\n',
        ''
    )
    [void]$builder.AppendLine($content.Trim())
    [void]$builder.AppendLine("-- <<< MIGRATION $($migration.Name)")
}

[void]$builder.AppendLine('commit;')
[void]$builder.AppendLine('')
[void]$builder.AppendLine("select 'objects' as dataset, count(*) as rows from public.objects;")
[void]$builder.AppendLine("select 'variants' as dataset, count(*) as rows from public.object_variants;")
[void]$builder.AppendLine("select 'aliases' as dataset, count(*) as rows from public.object_aliases where is_active;")
[void]$builder.AppendLine("select 'yoloe_prompts' as dataset, count(*) as rows from public.objects where object_id >= 10000;")
[void]$builder.AppendLine("select 'geosampa_ecopoints' as dataset, count(*) as rows from public.ecopoints where source = 'geosampa' and is_active;")
[void]$builder.AppendLine("select public.find_ecoscan_object('bottle') is null as generic_bottle_not_auto_classified;")

[System.IO.File]::WriteAllText(
    $outputPath,
    $builder.ToString(),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "SQL consolidado criado: $outputPath"
