param(
    [ValidateSet("admin", "student", "sync", "backend", "start-nodb")]
    [string[]]$Phase = @("admin", "student", "sync", "backend"),
    [ValidateSet("json", "csv")]
    [string]$OutputFormat = "json",
    [string]$OutputPath,
    [switch]$SkipInstall,
    [switch]$RunTests,
    [string]$LogDir
)

$ErrorActionPreference = "Stop"

function Invoke-TimedPhase {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $startedAt = Get-Date
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "Succeeded"
    $message = ""

    try {
        & $Action | Out-Host
    } catch {
        $status = "Failed"
        $message = $_.Exception.Message
    } finally {
        $stopwatch.Stop()
    }

    New-Object PSObject -Property ([ordered]@{
        Phase = $Name
        Status = $status
        Seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        StartedAt = $startedAt.ToString("o")
        FinishedAt = (Get-Date).ToString("o")
        Message = $message
    })
}

function Assert-LastExitCode {
    param(
        [string]$ScriptPath
    )

    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$ScriptPath failed with exit code $LASTEXITCODE"
    }
}

function Invoke-WebBuildScript {
    param(
        [string]$ScriptPath,
        [switch]$SkipInstall,
        [string]$LogDir
    )

    if ($SkipInstall -and $LogDir) {
        Write-Output "Running: $ScriptPath -SkipInstall -LogDir $LogDir"
        & $ScriptPath -SkipInstall -LogDir $LogDir
    } elseif ($SkipInstall) {
        Write-Output "Running: $ScriptPath -SkipInstall"
        & $ScriptPath -SkipInstall
    } elseif ($LogDir) {
        Write-Output "Running: $ScriptPath -LogDir $LogDir"
        & $ScriptPath -LogDir $LogDir
    } else {
        Write-Output "Running: $ScriptPath"
        & $ScriptPath
    }

    Assert-LastExitCode -ScriptPath $ScriptPath
}

function Invoke-BackendPackageScript {
    param(
        [string]$ScriptPath,
        [switch]$RunTests,
        [string]$LogDir
    )

    if ($RunTests -and $LogDir) {
        Write-Output "Running: $ScriptPath -RunTests -LogDir $LogDir"
        & $ScriptPath -RunTests -LogDir $LogDir
    } elseif ($RunTests) {
        Write-Output "Running: $ScriptPath -RunTests"
        & $ScriptPath -RunTests
    } elseif ($LogDir) {
        Write-Output "Running: $ScriptPath -LogDir $LogDir"
        & $ScriptPath -LogDir $LogDir
    } else {
        Write-Output "Running: $ScriptPath"
        & $ScriptPath
    }

    Assert-LastExitCode -ScriptPath $ScriptPath
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$results = @()

Write-Output "Measure options: Phase=$($Phase -join ',') SkipInstall=$($SkipInstall.IsPresent) RunTests=$($RunTests.IsPresent) LogDir=$LogDir"

foreach ($name in $Phase) {
    switch ($name) {
        "admin" {
            $results += Invoke-TimedPhase -Name $name -Action {
                Invoke-WebBuildScript -ScriptPath (Join-Path $PSScriptRoot "build-admin.ps1") -SkipInstall:$($SkipInstall.IsPresent) -LogDir $LogDir
            }
        }
        "student" {
            $results += Invoke-TimedPhase -Name $name -Action {
                Invoke-WebBuildScript -ScriptPath (Join-Path $PSScriptRoot "build-student.ps1") -SkipInstall:$($SkipInstall.IsPresent) -LogDir $LogDir
            }
        }
        "sync" {
            $results += Invoke-TimedPhase -Name $name -Action {
                $scriptPath = Join-Path $PSScriptRoot "sync-web-static.ps1"
                Write-Output "Running: $scriptPath"
                & $scriptPath
                Assert-LastExitCode -ScriptPath $scriptPath
            }
        }
        "backend" {
            $results += Invoke-TimedPhase -Name $name -Action {
                Invoke-BackendPackageScript -ScriptPath (Join-Path $PSScriptRoot "package-backend.ps1") -RunTests:$($RunTests.IsPresent) -LogDir $LogDir
            }
        }
        "start-nodb" {
            $results += Invoke-TimedPhase -Name $name -Action {
                $startScript = Join-Path $workspaceRoot "start.ps1"
                $stopScript = Join-Path $workspaceRoot "stop.ps1"
                try {
                    Write-Output "Running: $startScript -NoDatabase"
                    & $startScript -NoDatabase
                    Assert-LastExitCode -ScriptPath $startScript
                } finally {
                    if (Test-Path -LiteralPath $stopScript) {
                        try {
                            Write-Output "Running: $stopScript"
                            & $stopScript
                            Assert-LastExitCode -ScriptPath $stopScript
                        } catch {
                            Write-Warning "Failed to stop application after start-nodb measurement: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
    }
}

$results | Sort-Object { [array]::IndexOf($Phase, $_.Phase) } | Format-Table Phase, Status, Seconds, Message -AutoSize

if (-not $OutputPath) {
    $outputDir = Join-Path $workspaceRoot ".tmp\build-measure"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $outputDir "build-measure-$timestamp.$OutputFormat"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))) | Out-Null
if ($OutputFormat -eq "json") {
    ConvertTo-Json -InputObject @($results) -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
} else {
    $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
}

Write-Output "Measurement written to $OutputPath"

if ($results.Status -contains "Failed") {
    exit 1
}
