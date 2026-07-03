param(
    [switch]$SkipInstall,
    [switch]$SkipAdmin,
    [switch]$SkipStudent,
    [switch]$SkipSync,
    [switch]$SkipBackend,
    [switch]$RunTests,
    [string]$LogDir
)

$ErrorActionPreference = "Stop"

function Assert-LastExitCode {
    param(
        [string]$Name
    )

    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipAdmin) {
    $scriptPath = Join-Path $PSScriptRoot "build-admin.ps1"
    Write-Output "==> Build admin web"
    if ($SkipInstall -and $LogDir) {
        Write-Output "Running: $scriptPath -SkipInstall -LogDir $LogDir"
        & $scriptPath -SkipInstall -LogDir $LogDir
    } elseif ($SkipInstall) {
        Write-Output "Running: $scriptPath -SkipInstall"
        & $scriptPath -SkipInstall
    } elseif ($LogDir) {
        Write-Output "Running: $scriptPath -LogDir $LogDir"
        & $scriptPath -LogDir $LogDir
    } else {
        Write-Output "Running: $scriptPath"
        & $scriptPath
    }
    Assert-LastExitCode -Name "Build admin web"
}

if (-not $SkipStudent) {
    $scriptPath = Join-Path $PSScriptRoot "build-student.ps1"
    Write-Output "==> Build student web"
    if ($SkipInstall -and $LogDir) {
        Write-Output "Running: $scriptPath -SkipInstall -LogDir $LogDir"
        & $scriptPath -SkipInstall -LogDir $LogDir
    } elseif ($SkipInstall) {
        Write-Output "Running: $scriptPath -SkipInstall"
        & $scriptPath -SkipInstall
    } elseif ($LogDir) {
        Write-Output "Running: $scriptPath -LogDir $LogDir"
        & $scriptPath -LogDir $LogDir
    } else {
        Write-Output "Running: $scriptPath"
        & $scriptPath
    }
    Assert-LastExitCode -Name "Build student web"
}

if (-not $SkipSync) {
    $scriptPath = Join-Path $PSScriptRoot "sync-web-static.ps1"
    Write-Output "==> Sync web static files"
    if ($SkipAdmin -and $SkipStudent) {
        Write-Output "Running: $scriptPath -SkipAdmin -SkipStudent"
        & $scriptPath -SkipAdmin -SkipStudent
    } elseif ($SkipAdmin) {
        Write-Output "Running: $scriptPath -SkipAdmin"
        & $scriptPath -SkipAdmin
    } elseif ($SkipStudent) {
        Write-Output "Running: $scriptPath -SkipStudent"
        & $scriptPath -SkipStudent
    } else {
        Write-Output "Running: $scriptPath"
        & $scriptPath
    }
    Assert-LastExitCode -Name "Sync web static files"
}

if (-not $SkipBackend) {
    $scriptPath = Join-Path $PSScriptRoot "package-backend.ps1"
    Write-Output "==> Package backend"
    if ($RunTests -and $LogDir) {
        Write-Output "Running: $scriptPath -RunTests -LogDir $LogDir"
        & $scriptPath -RunTests -LogDir $LogDir
    } elseif ($RunTests) {
        Write-Output "Running: $scriptPath -RunTests"
        & $scriptPath -RunTests
    } elseif ($LogDir) {
        Write-Output "Running: $scriptPath -LogDir $LogDir"
        & $scriptPath -LogDir $LogDir
    } else {
        Write-Output "Running: $scriptPath"
        & $scriptPath
    }
    Assert-LastExitCode -Name "Package backend"
}

Write-Output "Build all completed."
