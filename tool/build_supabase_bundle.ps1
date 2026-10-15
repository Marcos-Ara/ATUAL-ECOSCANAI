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
[void]$builder.AppendLine('-- EcoScan AI: instalação inicial consolidada do banco Supabase, em português.')
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
[void]$builder.AppendLine("select 'objetos' as conjunto, count(*) as quantidade from public.objetos;")
[void]$builder.AppendLine("select 'materiais' as conjunto, count(*) as quantidade from public.materiais where ativo;")
[void]$builder.AppendLine("select 'variantes' as conjunto, count(*) as quantidade from public.variantes_objeto;")
[void]$builder.AppendLine("select 'sinonimos' as conjunto, count(*) as quantidade from public.sinonimos_objeto where ativo;")
[void]$builder.AppendLine("select 'classes_yoloe' as conjunto, count(*) as quantidade from public.classes_yoloe;")
[void]$builder.AppendLine("select 'pontos_ecologicos_geosampa' as conjunto, count(*) as quantidade from public.pontos_ecologicos where fonte = 'geosampa' and ativo;")
[void]$builder.AppendLine("select 'aceites_de_materiais' as conjunto, count(*) as quantidade from public.materiais_ponto_ecologico;")
[void]$builder.AppendLine("select public.buscar_objeto_ecoscan('bottle') is null as classe_ambigua_nao_classificada_sozinha;")

[System.IO.File]::WriteAllText(
    $outputPath,
    $builder.ToString(),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "SQL consolidado criado: $outputPath"
