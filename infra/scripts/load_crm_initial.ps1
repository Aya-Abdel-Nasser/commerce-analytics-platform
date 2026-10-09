# Commerce Analytics Platform | DEV only | MySQL CRM initial bulk load
# Uses Docker Compose service mysql_crm, not a Windows-installed MySQL server.
# Reads the root password from the container environment; never hardcodes it.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$csvDir = Join-Path $projectRoot 'data\generated\crm\prodlike\initial'
$sqlTemplate = Join-Path $projectRoot 'infra\sql\mysql\002_load_initial_crm.sql'
$tables = @('crm_customers', 'loyalty_accounts', 'loyalty_transactions',
            'campaigns', 'campaign_memberships', 'support_tickets')
$expected = @{
    crm_customers = 50000
    loyalty_accounts = 35000
    loyalty_transactions = 175000
    campaigns = 120
    campaign_memberships = 360000
    support_tickets = 45000
}
$manifestPath = Join-Path $csvDir 'manifest.json'
if (-not (Test-Path -LiteralPath $sqlTemplate -PathType Leaf)) {
    throw "Missing SQL template: $sqlTemplate"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing CRM manifest: $manifestPath. Generate the CRM prodlike batch first."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.profile -ne 'prodlike' -or $manifest.mode -ne 'initial' -or $manifest.source -ne 'mysql_crm') {
    throw 'CRM manifest must describe mysql_crm / prodlike / initial.'
}
foreach ($table in $tables) {
    if (-not (Test-Path -LiteralPath (Join-Path $csvDir "$table.csv") -PathType Leaf)) {
        throw "Missing CRM CSV: $table.csv"
    }
    if ([long]$manifest.counts.$table -ne [long]$expected[$table]) {
        throw "Unexpected count for $table in CRM manifest."
    }
}

$compose = @('compose', '--env-file', 'infra\environments\dev\.env.dev',
             '-f', 'infra\docker\compose.yaml', '-p', 'commerce-dev')
$temporarySql = $null
$stageDir = $null
$containerId = $null

Push-Location $projectRoot
try {
    $containerIds = @(& docker @compose ps -q mysql_crm)
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed.' }
    $containerId = [string]($containerIds | Select-Object -First 1)
    $containerId = $containerId.Trim()
    if (-not $containerId) { throw 'mysql_crm Docker container is not running.' }

    # Determine the server's allowed LOAD DATA INFILE directory.
    $probeCommand = 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -u root --batch --skip-column-names --silent -e SELECT\ @@GLOBAL.secure_file_priv'
    $probeLines = @(& docker exec $containerId sh -c $probeCommand)
    if ($LASTEXITCODE -ne 0) { throw 'Could not query MySQL secure_file_priv with the container root credentials.' }
    $secureDir = [string]($probeLines | Select-Object -Last 1)
    $secureDir = $secureDir.Trim()
    if ($secureDir -eq 'NULL') {
        throw 'MySQL secure_file_priv is NULL: server-side file imports are disabled. No data changed.'
    }
    if ($secureDir -eq '') { $secureDir = '/tmp' }
    if (-not $secureDir.StartsWith('/')) {
        throw "Unexpected MySQL secure_file_priv path: $secureDir"
    }
    $stageDir = $secureDir.TrimEnd('/') + '/commerce_crm_initial'
    if ($stageDir -notmatch '^/[A-Za-z0-9_./-]+$') {
        throw 'Unsafe/unsupported staging path returned by MySQL.'
    }

    Write-Host "Staging CRM CSVs inside MySQL container: $stageDir"
    & docker exec -u 0 $containerId mkdir -p $stageDir
    if ($LASTEXITCODE -ne 0) { throw 'Could not create MySQL staging directory.' }
    foreach ($table in $tables) {
        & docker cp (Join-Path $csvDir "$table.csv") ('{0}:{1}/{2}.csv' -f $containerId, $stageDir, $table)
        if ($LASTEXITCODE -ne 0) { throw "Could not stage $table.csv" }
    }

    # Prepare a copy of the SQL, using the actual directory from MySQL itself.
    $sql = [System.IO.File]::ReadAllText($sqlTemplate)
    if (-not $sql.Contains('__CSV_DIR__')) { throw 'SQL template is missing __CSV_DIR__ placeholder.' }
    $sql = $sql.Replace('__CSV_DIR__', $stageDir)
    $temporarySql = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($temporarySql, $sql, (New-Object System.Text.UTF8Encoding($false)))
    & docker cp $temporarySql ('{0}:{1}/load.sql' -f $containerId, $stageDir)
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage MySQL load.sql.' }
    & docker exec -u 0 $containerId chmod -R a+rX $stageDir
    if ($LASTEXITCODE -ne 0) { throw 'Could not set file read permissions for MySQL.' }

    Write-Host 'Loading CRM rows into MySQL in one transaction (no deletes/truncates)...'
    $loadCommand = 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql --batch --raw --show-warnings --default-character-set=utf8mb4 -u root commerce_crm_dev < "' + $stageDir + '/load.sql"'
    & docker exec $containerId sh -c $loadCommand
    if ($LASTEXITCODE -ne 0) {
        throw 'MySQL initial load failed. InnoDB should roll back the uncommitted transaction; review the SQL error before retrying.'
    }
    Write-Host 'MYSQL CRM INITIAL LOAD: COMPLETE (665,120 rows)' -ForegroundColor Green
}
finally {
    if ($temporarySql -and (Test-Path -LiteralPath $temporarySql)) {
        Remove-Item -LiteralPath $temporarySql -Force -ErrorAction SilentlyContinue
    }
    if ($containerId -and $stageDir) {
        # Staged CSVs are local synthetic files, never production files.
        & docker exec -u 0 $containerId rm -rf $stageDir 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not remove temporary MySQL staging files.' }
    }
    Pop-Location
}
