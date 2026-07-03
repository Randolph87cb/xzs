param(
    [switch]$RunTests,
    [string]$LogDir,
    [string[]]$Goals = @("package"),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
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

    return $null
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogFile,
        [switch]$AllowFailure
    )

    Push-Location $WorkingDirectory
    try {
        if ($LogFile) {
            & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $LogFile -Append
        } else {
            & $FilePath @Arguments
        }

        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            throw "Command failed with exit code $exitCode`: $FilePath $($Arguments -join ' ')"
        }

        if ($AllowFailure) {
            return $exitCode
        }
    } finally {
        Pop-Location
    }
}

function Get-TemporaryMaven {
    param([string]$Version = "3.8.8")

    $toolsRoot = Join-Path ([System.IO.Path]::GetTempPath()) "xzs-build-tools"
    $mavenRoot = Join-Path $toolsRoot "apache-maven-$Version"
    $mavenCmd = Join-Path $mavenRoot "bin\mvn.cmd"
    if (Test-Path -LiteralPath $mavenCmd) {
        return $mavenCmd
    }

    $zipPath = Join-Path $toolsRoot "apache-maven-$Version-bin.zip"
    $url = "https://archive.apache.org/dist/maven/maven-3/$Version/binaries/apache-maven-$Version-bin.zip"
    New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null

    Write-Output "Downloading temporary Maven $Version from $url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $toolsRoot -Force

    if (-not (Test-Path -LiteralPath $mavenCmd)) {
        throw "Temporary Maven was downloaded but mvn.cmd was not found: $mavenCmd"
    }

    return $mavenCmd
}

function Test-MavenCommand {
    param(
        [string]$FilePath,
        [string]$WorkingDirectory
    )

    try {
        Push-Location $WorkingDirectory
        try {
            & $FilePath -v *> $null
            return ($LASTEXITCODE -eq 0)
        } finally {
            Pop-Location
        }
    } catch {
        return $false
    }
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $workspaceRoot "source\xzs"
if (-not (Test-Path -LiteralPath (Join-Path $backendDir "pom.xml"))) {
    throw "Backend pom.xml not found: $backendDir"
}

$logFile = $null
if ($LogDir) {
    $resolvedLogDir = [System.IO.Path]::GetFullPath($LogDir)
    New-Item -ItemType Directory -Force -Path $resolvedLogDir | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $resolvedLogDir "package-backend-$timestamp.log"
}

$maven = $null
$wrapper = Join-Path $backendDir "mvnw.cmd"
if (Test-Path -LiteralPath $wrapper) {
    if (Test-MavenCommand -FilePath $wrapper -WorkingDirectory $backendDir) {
        $maven = $wrapper
    } else {
        Write-Warning "mvnw.cmd is present but not usable. Falling back to mvn or temporary Maven."
    }
}

if (-not $maven) {
    $maven = Resolve-CommandPath -Names @("mvn.cmd", "mvn")
}

if (-not $maven) {
    $maven = Get-TemporaryMaven
}

$mavenArgs = @()
if (-not $RunTests) {
    $mavenArgs += "-DskipTests"
}
$mavenArgs += $Goals
if ($ExtraArgs) {
    $mavenArgs += $ExtraArgs
}

Invoke-External -FilePath $maven -Arguments $mavenArgs -WorkingDirectory $backendDir -LogFile $logFile

Write-Output "Backend package completed: $(Join-Path $backendDir 'target')"
