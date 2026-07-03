param(
    [switch]$SkipInstall,
    [string]$LogDir,
    [string]$NpmScript = "build"
)

$ErrorActionPreference = "Stop"

function Resolve-CommandPath {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    throw "None of these commands were found: $($Names -join ', ')"
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogFile
    )

    Push-Location $WorkingDirectory
    try {
        if ($LogFile) {
            & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $LogFile -Append
        } else {
            & $FilePath @Arguments
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$projectDir = Join-Path $workspaceRoot "source\vue\xzs-admin"
if (-not (Test-Path -LiteralPath (Join-Path $projectDir "package.json"))) {
    throw "Admin package.json not found: $projectDir"
}

$npm = Resolve-CommandPath -Names @("npm.cmd", "npm")
$logFile = $null
if ($LogDir) {
    $resolvedLogDir = [System.IO.Path]::GetFullPath($LogDir)
    New-Item -ItemType Directory -Force -Path $resolvedLogDir | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $resolvedLogDir "build-admin-$timestamp.log"
}

if (-not $SkipInstall) {
    $installArgs = @("install")
    if (Test-Path -LiteralPath (Join-Path $projectDir "package-lock.json")) {
        $installArgs = @("ci")
    }
    Invoke-External -FilePath $npm -Arguments $installArgs -WorkingDirectory $projectDir -LogFile $logFile
}

Invoke-External -FilePath $npm -Arguments @("run", $NpmScript) -WorkingDirectory $projectDir -LogFile $logFile

Write-Output "Admin web build completed: $(Join-Path $projectDir 'admin')"
