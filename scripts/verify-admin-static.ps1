param(
    [string]$BaseUrl = "http://localhost:8000/admin/index.html",
    [string]$ApiBaseUrl = "http://localhost:8000",
    [string]$UserName = "admin",
    [string]$Password = "123456",
    [switch]$SkipBrowser
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$adminStatic = Join-Path $workspaceRoot "source\xzs\src\main\resources\static\admin"
$indexPath = Join-Path $adminStatic "index.html"
$faviconPath = Join-Path $adminStatic "favicon.ico"
$staticDir = Join-Path $adminStatic "static"

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Admin static index.html not found: $indexPath"
}

if (-not (Test-Path -LiteralPath $staticDir -PathType Container)) {
    throw "Admin static assets directory not found: $staticDir"
}

if (-not (Test-Path -LiteralPath $faviconPath -PathType Leaf)) {
    throw "Admin favicon.ico not found: $faviconPath"
}

$indexContent = Get-Content -LiteralPath $indexPath -Raw
if ($indexContent -notmatch 'type="module"') {
    throw "Admin static index.html does not look like a Vite build: $indexPath"
}

if ($indexContent -match 'href="\./favicon\.ico"' -and -not (Test-Path -LiteralPath $faviconPath -PathType Leaf)) {
    throw "Admin static index.html references ./favicon.ico but the file is missing: $faviconPath"
}

$jsCount = @(Get-ChildItem -LiteralPath $staticDir -Filter "*.js" -File -Recurse).Count
$cssCount = @(Get-ChildItem -LiteralPath $staticDir -Filter "*.css" -File -Recurse).Count
if ($jsCount -lt 1 -or $cssCount -lt 1) {
    throw "Admin static assets are incomplete. js=$jsCount css=$cssCount"
}

Write-Output "Admin static files look like Vite output: index=$indexPath js=$jsCount css=$cssCount"

if ($SkipBrowser) {
    return
}

try {
    $servedIndex = (Invoke-WebRequest -UseBasicParsing -Uri $BaseUrl).Content
} catch {
    throw "Failed to fetch admin page from $BaseUrl. Start or restart the backend after syncing static files. $($_.Exception.Message)"
}

if ($servedIndex -notmatch 'type="module"') {
    throw "Admin page served from $BaseUrl is not the Vue 3/Vite build. Repackage and restart the backend after running scripts/sync-web-static.ps1."
}

try {
    $faviconUrl = [System.Uri]::new([System.Uri]::new($BaseUrl), "./favicon.ico").AbsoluteUri
    $faviconResponse = Invoke-WebRequest -UseBasicParsing -Uri $faviconUrl
    if ([int]$faviconResponse.StatusCode -ge 400) {
        throw "HTTP $($faviconResponse.StatusCode)"
    }
} catch {
    throw "Failed to fetch admin favicon from $faviconUrl. $($_.Exception.Message)"
}

$oldBaseUrl = $env:XZS_ADMIN_BASE_URL
$oldApiBaseUrl = $env:XZS_ADMIN_API_BASE_URL
$oldUserName = $env:XZS_ADMIN_USERNAME
$oldPassword = $env:XZS_ADMIN_PASSWORD

try {
    $env:XZS_ADMIN_BASE_URL = $BaseUrl
    $env:XZS_ADMIN_API_BASE_URL = $ApiBaseUrl
    $env:XZS_ADMIN_USERNAME = $UserName
    $env:XZS_ADMIN_PASSWORD = $Password

    Push-Location (Join-Path $workspaceRoot "frontend")
    try {
        pnpm verify:admin-ui
        if ($LASTEXITCODE -ne 0) {
            throw "pnpm verify:admin-ui failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} finally {
    $env:XZS_ADMIN_BASE_URL = $oldBaseUrl
    $env:XZS_ADMIN_API_BASE_URL = $oldApiBaseUrl
    $env:XZS_ADMIN_USERNAME = $oldUserName
    $env:XZS_ADMIN_PASSWORD = $oldPassword
}
