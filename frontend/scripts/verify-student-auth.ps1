param(
    [string]$BaseUrl = "http://localhost:8001",
    [string]$UserName = "student",
    [string]$Password = "123456"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tmpDir = Join-Path $repoRoot ".tmp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$cookieJar = Join-Path $tmpDir "student-auth-cookies.txt"
$payloadPath = Join-Path $tmpDir "student-auth-login.json"

if (Test-Path $cookieJar) {
    Remove-Item -LiteralPath $cookieJar -Force
}

$payload = @{
    userName = $UserName
    password = $Password
    remember = $false
} | ConvertTo-Json -Compress
Set-Content -Path $payloadPath -Value $payload -Encoding utf8

function Invoke-StudentApi {
    param(
        [string]$Path,
        [string]$DataFile
    )

    $arguments = @(
        "--noproxy", "*",
        "-s",
        "-c", $cookieJar,
        "-b", $cookieJar,
        "-H", "Content-Type: application/json",
        "-H", "request-ajax: true",
        "-X", "POST",
        "$BaseUrl$Path"
    )

    if ($DataFile) {
        $arguments += @("--data-binary", "@$DataFile")
    }

    $raw = & curl.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed with exit code $LASTEXITCODE"
    }

    return $raw | ConvertFrom-Json
}

function Assert-Code {
    param(
        [object]$Response,
        [int]$Expected,
        [string]$Label
    )

    if ($Response.code -ne $Expected) {
        throw "$Label expected code $Expected, got $($Response.code): $($Response | ConvertTo-Json -Compress)"
    }
}

$beforeLogin = Invoke-StudentApi -Path "/api/student/user/current"
Assert-Code -Response $beforeLogin -Expected 401 -Label "current before login"

$login = Invoke-StudentApi -Path "/api/user/login" -DataFile $payloadPath
Assert-Code -Response $login -Expected 1 -Label "login"

$current = Invoke-StudentApi -Path "/api/student/user/current"
Assert-Code -Response $current -Expected 1 -Label "current after login"

if ($current.response.userName -ne $UserName) {
    throw "current user expected $UserName, got $($current.response.userName)"
}

$logout = Invoke-StudentApi -Path "/api/user/logout"
Assert-Code -Response $logout -Expected 1 -Label "logout"

$afterLogout = Invoke-StudentApi -Path "/api/student/user/current"
Assert-Code -Response $afterLogout -Expected 401 -Label "current after logout"

Write-Output "student auth verification passed for $BaseUrl"
