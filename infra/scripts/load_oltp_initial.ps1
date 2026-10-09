# Commerce Analytics Platform | DEV only | PostgreSQL initial bulk load
# Runs the companion SQL file in the existing Docker PostgreSQL container.
# No passwords or credentials are stored in this script.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$csvDir = Join-Path $projectRoot 'data\generated\oltp\prodlike\initial'
$sqlPath = Join-Path $projectRoot 'infra\sql\postgres\002_load_initial_oltp.sql'
$tables = @('customers', 'products', 'orders', 'order_items', 'payments')
$expected = @{ customers = 50000; products = 3000; orders = 200000; order_items = 500000; payments = 215000 }

if (-not (Test-Path -LiteralPath $sqlPath -PathType Leaf)) {
    throw "SQL file not found: $sqlPath"
}
$manifestPath = Join-Path $csvDir 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Manifest not found: $manifestPath. Run the prodlike initial generator first."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.profile -ne 'prodlike' -or $manifest.mode -ne 'initial') {
    throw 'Manifest is not a prodlike initial batch.'
}
foreach ($table in $tables) {
    $csvPath = Join-Path $csvDir "$table.csv"
    if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        throw "Missing CSV: $csvPath"
    }
    if ([long]$manifest.counts.$table -ne [long]$expected[$table]) {
        throw "Unexpected count in manifest for $table."
    }
}

$compose = @('compose', '--env-file', 'infra\environments\dev\.env.dev',
             '-f', 'infra\docker\compose.yaml', '-p', 'commerce-dev')
$workdir = '/tmp/commerce_oltp_initial'

Push-Location $projectRoot
try {
    $containerIds = @(& docker @compose ps -q postgres_oltp)
    if ($LASTEXITCODE -ne 0) { throw 'Could not query Docker Compose.' }
    $containerId = [string]($containerIds | Select-Object -First 1)
    $containerId = $containerId.Trim()
    if (-not $containerId) { throw 'postgres_oltp container is not running.' }

    Write-Host 'Copying synthetic CSVs into the PostgreSQL container...'
    & docker exec $containerId mkdir -p $workdir
    if ($LASTEXITCODE -ne 0) { throw 'Could not create temporary load directory.' }
    foreach ($table in $tables) {
        $csvPath = Join-Path $csvDir "$table.csv"
        $destination = '{0}:{1}/{2}.csv' -f $containerId, $workdir, $table
        & docker cp $csvPath $destination
        if ($LASTEXITCODE -ne 0) { throw "Failed to stage $table.csv" }
    }
    $sqlDestination = '{0}:{1}/load.sql' -f $containerId, $workdir
    & docker cp $sqlPath $sqlDestination
    if ($LASTEXITCODE -ne 0) { throw 'Failed to stage SQL.' }

    Write-Host 'Running transactional PostgreSQL bulk load...'
    & docker exec $containerId psql -X -v ON_ERROR_STOP=1 -U commerce_app_dev -d commerce_oltp_dev -f "$workdir/load.sql"
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL load failed. Database transaction was rolled back.' }

    Write-Host 'INITIAL BULK LOAD: COMPLETE (968,000 rows)' -ForegroundColor Green
    & docker exec $containerId rm -rf $workdir
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Load succeeded but cleanup of temporary container files failed.' }
}
finally {
    Pop-Location
}
