param(
    [string]$AppName = "gesp-csp-quiz",
    [string]$EnvFile = ".env.neon-test",
    [string]$BaseUrl = "https://gesp-csp-quiz.fly.dev",
    [switch]$SkipRemoteCheck
)

$ErrorActionPreference = "Stop"
$workspaceRoot = Split-Path -Parent $PSScriptRoot

function Resolve-WorkspacePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $workspaceRoot $Path
}

function Read-EnvFile {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2 -or -not $parts[0].Trim()) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }

    return $values
}

function Invoke-FlySecretsImport {
    param(
        [string]$Payload,
        [string]$AppName
    )

    $flyctl = Get-Command flyctl -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $flyctl.Source
    $startInfo.Arguments = "secrets import --stage -a $AppName"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stdin = $null
    $originalInputEncoding = [Console]::InputEncoding
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [Console]::InputEncoding = $utf8NoBom

        if (-not $process.Start()) {
            throw "Failed to start flyctl secrets import."
        }

        $stdin = $process.StandardInput.BaseStream
        $payloadBytes = $utf8NoBom.GetBytes($Payload)
        $stdin.Write($payloadBytes, 0, $payloadBytes.Length)
        $stdin.Close()
        $stdin = $null

        $process.WaitForExit()
        return $process.ExitCode
    } finally {
        if ($null -ne $stdin) {
            $stdin.Dispose()
        }
        [Console]::InputEncoding = $originalInputEncoding
        $process.Dispose()
    }
}

$envPath = Resolve-WorkspacePath $EnvFile
if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Env file not found: $envPath"
}

$envValues = Read-EnvFile $envPath
$requiredNames = @(
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE",
    "SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE",
    "XZS_AI_CONFIG_SECRET"
)

foreach ($name in $requiredNames) {
    if (-not $envValues.ContainsKey($name) -or -not $envValues[$name]) {
        throw "Missing required value in ${EnvFile}: $name"
    }
}

if ($envValues["SPRING_DATASOURCE_URL"] -notmatch "sslmode=require") {
    throw "SPRING_DATASOURCE_URL must point to Neon with sslmode=require."
}

$secretNames = @(
    "SPRING_PROFILES_ACTIVE",
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE",
    "SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE",
    "XZS_AI_CONFIG_SECRET"
)

$secretValues = @{
    SPRING_PROFILES_ACTIVE = $envValues["SPRING_PROFILES_ACTIVE"]
    SPRING_DATASOURCE_URL = $envValues["SPRING_DATASOURCE_URL"]
    SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE = $envValues["SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE"]
    SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE = $envValues["SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE"]
    XZS_AI_CONFIG_SECRET = $envValues["XZS_AI_CONFIG_SECRET"]
}

if (-not $secretValues["SPRING_PROFILES_ACTIVE"]) {
    $secretValues["SPRING_PROFILES_ACTIVE"] = "prod"
}

$payload = ($secretNames | ForEach-Object { "$_=$($secretValues[$_])" }) -join "`n"

Write-Output "Importing Fly test secrets from $EnvFile for app $AppName."
Write-Output "Secret names: $($secretNames -join ', ')"
$importExitCode = Invoke-FlySecretsImport -Payload $payload -AppName $AppName
if ($importExitCode -ne 0) {
    throw "flyctl secrets import failed with exit code $importExitCode."
}

Write-Output "Staging removal of legacy datasource username/password secrets if present."
flyctl secrets unset SPRING_DATASOURCE_USERNAME SPRING_DATASOURCE_PASSWORD --stage -a $AppName | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "flyctl secrets unset failed with exit code $LASTEXITCODE."
}

Write-Output "Deploying Fly test app $AppName."
flyctl deploy -a $AppName
if ($LASTEXITCODE -ne 0) {
    throw "flyctl deploy failed with exit code $LASTEXITCODE."
}

if (-not $SkipRemoteCheck) {
    Write-Output "Running deployment acceptance for $BaseUrl."
    & (Join-Path $workspaceRoot "scripts\test-deployment-acceptance.ps1") `
        -Target Fly `
        -BaseUrl $BaseUrl `
        -RetryCount 45 `
        -RetryDelaySeconds 10
}
