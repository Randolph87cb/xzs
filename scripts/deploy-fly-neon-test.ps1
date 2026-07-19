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
$payload | flyctl secrets import --stage -a $AppName | Out-Host

try {
    Write-Output "Staging removal of legacy datasource username/password secrets if present."
    flyctl secrets unset SPRING_DATASOURCE_USERNAME SPRING_DATASOURCE_PASSWORD --stage -a $AppName | Out-Host
} catch {
    Write-Output "Legacy datasource username/password secrets were not removed or were already absent."
}

Write-Output "Deploying Fly test app $AppName."
flyctl deploy -a $AppName

if (-not $SkipRemoteCheck) {
    Write-Output "Running remote deployment check for $BaseUrl."
    & (Join-Path $workspaceRoot "scripts\test-remote-deployment.ps1") -BaseUrl $BaseUrl -RetryCount 45 -RetryDelaySeconds 10
}
