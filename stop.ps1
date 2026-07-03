param(
    [switch]$KeepDatabase
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $Root ".tmp\runtime"
$PidFile = Join-Path $RuntimeDir "xzs.pid"
$DbMarkerFile = Join-Path $RuntimeDir "xzs-postgres.started"

if (Test-Path -LiteralPath $PidFile) {
    $pidValue = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if ($pidValue) {
        $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Id $process.Id -Force
            Write-Output "Stopped XZS process. PID: $($process.Id)"
        } else {
            Write-Output "XZS process from pid file is not running. PID: $pidValue"
        }
    }
    Remove-Item -LiteralPath $PidFile -Force
} else {
    Write-Output "No XZS pid file found."
}

if (-not $KeepDatabase -and (Test-Path -LiteralPath $DbMarkerFile)) {
    $containerName = (Get-Content -LiteralPath $DbMarkerFile -Raw).Trim()
    if ($containerName -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        $runningNames = docker ps --format "{{.Names}}"
        if ($runningNames -contains $containerName) {
            docker stop $containerName | Out-Null
            Write-Output "Stopped database container: $containerName"
        }
    }
    Remove-Item -LiteralPath $DbMarkerFile -Force
}
