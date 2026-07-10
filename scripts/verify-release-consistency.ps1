Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseJar = Join-Path $repoRoot 'release/java/xzs-3.9.0.jar'
$dockerJar = Join-Path $repoRoot 'docker/release/xzs-3.9.0.jar'
$dockerComposeBinary = Join-Path $repoRoot 'docker/install/docker-compose-linux-x86_64'

$failures = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $releaseJar -PathType Leaf)) {
    $failures.Add("Missing release jar: $releaseJar")
}

if (Test-Path -LiteralPath $dockerJar -PathType Leaf) {
    $failures.Add("Duplicate docker jar must be removed: $dockerJar")
}

if (Test-Path -LiteralPath $dockerComposeBinary -PathType Leaf) {
    $failures.Add("Bundled docker-compose binary must be removed: $dockerComposeBinary")
}

$docsToCheck = @(
    (Join-Path $repoRoot 'release/README.md'),
    (Join-Path $repoRoot 'docker/README.md'),
    (Join-Path $repoRoot 'docs/guide/deploy.html'),
    (Join-Path $repoRoot 'docs/assets/deploy.html.1f0eca1c.js')
)

$composeDocsToCheck = @(
    (Join-Path $repoRoot 'docker/README.md'),
    (Join-Path $repoRoot 'docs/project-structure/database-deploy.md')
)

$staleTerms = @(
    'xzs-mysql',
    'xzs-mysql.sql',
    'root/123456',
    'mindskip.net:999',
    'MYSQL_ROOT_PASSWORD'
)

foreach ($doc in $docsToCheck) {
    if (-not (Test-Path -LiteralPath $doc -PathType Leaf)) {
        $failures.Add("Missing README: $doc")
        continue
    }

    $content = Get-Content -LiteralPath $doc -Raw -Encoding UTF8
    foreach ($term in $staleTerms) {
        if ($content.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $failures.Add("Stale deployment term '$term' found in $doc")
        }
    }
}

$bundledComposeTerms = @(
    'docker/install',
    'docker-compose-linux-x86_64',
    '附带的 docker-compose 二进制',
    '仓库内附带 docker-compose'
)

foreach ($doc in $composeDocsToCheck) {
    if (-not (Test-Path -LiteralPath $doc -PathType Leaf)) {
        $failures.Add("Missing deployment doc: $doc")
        continue
    }

    $content = Get-Content -LiteralPath $doc -Raw -Encoding UTF8
    foreach ($term in $bundledComposeTerms) {
        if ($content.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $failures.Add("Bundled docker-compose recommendation '$term' found in $doc")
        }
    }
}

if ($failures.Count -gt 0) {
    throw ("Release consistency check failed:`n" + ($failures -join "`n"))
}

Write-Host 'Release consistency check passed.'
