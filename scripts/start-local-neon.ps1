param(
    [string]$EnvFile,
    [switch]$SkipBuild,
    [switch]$SkipInstall,
    [switch]$SkipSync,
    [switch]$CheckOnly,
    [switch]$SkipHttpCheck,
    [switch]$UseExistingService,
    [bool]$VerifyAfterStart = $true,
    [int]$HttpTimeoutSeconds = 120,
    [int]$HttpPollSeconds = 2,
    [string]$BaseUrl = "http://127.0.0.1:8000",
    [string[]]$ForbiddenText = @()
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

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Environment file not found: $Path"
    }

    $loaded = 0
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf("=")
        if ($separatorIndex -le 0) {
            continue
        }

        $name = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if ($name.Length -eq 0) {
            continue
        }

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        Set-Item -Path "Env:$name" -Value $value
        $loaded += 1
    }

    Write-Output "Loaded $loaded environment variables from $Path"
}

function Set-NoProxyValue {
    param([string[]]$RequiredHosts)

    $existing = @()
    if ($env:NO_PROXY) {
        $existing += @($env:NO_PROXY.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if ($env:no_proxy) {
        $existing += @($env:no_proxy.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($item in $existing) {
        if (-not $values.Contains($item)) {
            $values.Add($item)
        }
    }

    foreach ($hostName in $RequiredHosts) {
        if (-not $values.Contains($hostName)) {
            $values.Add($hostName)
        }
    }

    $joined = $values -join ","
    $env:NO_PROXY = $joined
    $env:no_proxy = $joined
    Write-Output "NO_PROXY/no_proxy configured for localhost addresses."
}

function Invoke-StaticConsistencyCheck {
    param(
        [string]$VerifyScript,
        [string]$BaseUrl,
        [bool]$IncludeHttp,
        [string[]]$ForbiddenText
    )

    $skipHttp = $SkipHttpCheck -or -not $IncludeHttp
    $global:LASTEXITCODE = 0

    if ($ForbiddenText.Count -gt 0 -and $skipHttp) {
        Write-Output "Running: $VerifyScript -BaseUrl $BaseUrl -SkipHttpCheck -AllowMissingRuntimeStatic -ForbiddenText <redacted-list>"
        & $VerifyScript -BaseUrl $BaseUrl -SkipHttpCheck -AllowMissingRuntimeStatic -ForbiddenText $ForbiddenText
    } elseif ($ForbiddenText.Count -gt 0) {
        Write-Output "Running: $VerifyScript -BaseUrl $BaseUrl -AllowMissingRuntimeStatic -ForbiddenText <redacted-list>"
        & $VerifyScript -BaseUrl $BaseUrl -AllowMissingRuntimeStatic -ForbiddenText $ForbiddenText
    } elseif ($skipHttp) {
        Write-Output "Running: $VerifyScript -BaseUrl $BaseUrl -SkipHttpCheck -AllowMissingRuntimeStatic"
        & $VerifyScript -BaseUrl $BaseUrl -SkipHttpCheck -AllowMissingRuntimeStatic
    } else {
        Write-Output "Running: $VerifyScript -BaseUrl $BaseUrl -AllowMissingRuntimeStatic"
        & $VerifyScript -BaseUrl $BaseUrl -AllowMissingRuntimeStatic
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Static consistency verification failed with exit code $LASTEXITCODE"
    }
}

function Test-HttpEndpoint {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
        return ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400)
    } catch {
        return $false
    }
}

function Test-AnyExistingHttpService {
    param([string]$BaseUrl)

    $adminUrl = "$($BaseUrl.TrimEnd('/'))/admin/index.html"
    $studentUrl = "$($BaseUrl.TrimEnd('/'))/student/index.html"

    return ((Test-HttpEndpoint -Url $adminUrl) -or (Test-HttpEndpoint -Url $studentUrl))
}

function Wait-HttpReady {
    param(
        [string]$BaseUrl,
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds,
        [int]$PollSeconds
    )

    $adminUrl = "$($BaseUrl.TrimEnd('/'))/admin/index.html"
    $studentUrl = "$($BaseUrl.TrimEnd('/'))/student/index.html"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) {
            throw "Spring Boot exited before HTTP verification could run. Exit code: $($Process.ExitCode)"
        }

        if ((Test-HttpEndpoint -Url $adminUrl) -and (Test-HttpEndpoint -Url $studentUrl)) {
            return
        }

        Start-Sleep -Seconds $PollSeconds
    }

    throw "Timed out after $TimeoutSeconds seconds waiting for $adminUrl and $studentUrl to become available."
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    try {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
        }

        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Output "Failed to stop process tree for PID $ProcessId. $($_.Exception.Message)"
    }
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvFile) {
    $EnvFile = Join-Path $workspaceRoot ".env.neon-test"
}

Import-DotEnv -Path $EnvFile
Set-NoProxyValue -RequiredHosts @("localhost", "127.0.0.1", "::1")

$env:XZS_WEB_STATIC_USE_LOCAL = "true"
Write-Output "Enabled local Vite static resource mode for this process."

if ($UseExistingService -and $SkipHttpCheck) {
    throw "-UseExistingService requires HTTP verification. Remove -SkipHttpCheck, or use -CheckOnly -SkipHttpCheck for file-level checks only."
}

if (-not $CheckOnly) {
    $existingServiceAvailable = Test-AnyExistingHttpService -BaseUrl $BaseUrl
    if ($UseExistingService) {
        if (-not $existingServiceAvailable) {
            throw "-UseExistingService was specified, but no existing service responded at $($BaseUrl.TrimEnd('/'))/admin/index.html or /student/index.html."
        }

        Write-Output "Using existing local service at $BaseUrl. A new backend process will not be started."
    } elseif ($existingServiceAvailable) {
        throw "A local service is already responding at $BaseUrl. Stop the existing backend first, or pass -UseExistingService to validate that existing service without starting a new process."
    }
}

if (-not $SkipBuild) {
    $buildAdmin = Join-Path $PSScriptRoot "build-admin.ps1"
    $buildStudent = Join-Path $PSScriptRoot "build-student.ps1"
    if ($SkipInstall) {
        Write-Output "Running: $buildAdmin -SkipInstall"
        & $buildAdmin -SkipInstall
        if ($LASTEXITCODE -ne 0) {
            throw "Build admin failed with exit code $LASTEXITCODE"
        }

        Write-Output "Running: $buildStudent -SkipInstall"
        & $buildStudent -SkipInstall
        if ($LASTEXITCODE -ne 0) {
            throw "Build student failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Output "Running: $buildAdmin"
        & $buildAdmin
        if ($LASTEXITCODE -ne 0) {
            throw "Build admin failed with exit code $LASTEXITCODE"
        }

        Write-Output "Running: $buildStudent"
        & $buildStudent
        if ($LASTEXITCODE -ne 0) {
            throw "Build student failed with exit code $LASTEXITCODE"
        }
    }
} else {
    Write-Output "Skipped frontend build."
}

if (-not $SkipSync) {
    $syncScript = Join-Path $PSScriptRoot "sync-web-static.ps1"
    Write-Output "Running: $syncScript"
    $global:LASTEXITCODE = 0
    & $syncScript
    if ($LASTEXITCODE -ne 0) {
        throw "Static sync failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Output "Skipped static sync. This is only safe when local Vite static resource mode is intended."
}

$verifyScript = Join-Path $PSScriptRoot "verify-web-static-consistency.ps1"
Invoke-StaticConsistencyCheck -VerifyScript $verifyScript -BaseUrl $BaseUrl -IncludeHttp ([bool]$CheckOnly) -ForbiddenText $ForbiddenText

if ($CheckOnly) {
    Write-Output "CheckOnly completed. Backend was not started."
    return
}

if ($UseExistingService) {
    Invoke-StaticConsistencyCheck -VerifyScript $verifyScript -BaseUrl $BaseUrl -IncludeHttp $true -ForbiddenText $ForbiddenText
    Write-Output "Existing service HTTP static consistency verification completed. Backend was not started."
    return
}

$backendDir = Join-Path $workspaceRoot "source\xzs"
$mvnwCmd = Join-Path $backendDir "mvnw.cmd"
if (Test-Path -LiteralPath $mvnwCmd -PathType Leaf) {
    $mvnw = $mvnwCmd
} else {
    $mvnw = Resolve-CommandPath -Names @("mvnw.cmd", "mvnw", "mvn.cmd", "mvn")
}

$logRoot = Join-Path $workspaceRoot ".tmp\local-neon"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdoutLog = Join-Path $logRoot "spring-boot-run-$timestamp.out.log"
$stderrLog = Join-Path $logRoot "spring-boot-run-$timestamp.err.log"
$backendProcess = $null

Write-Output "Starting Spring Boot with Neon test environment from $backendDir"
Write-Output "Spring Boot logs: $stdoutLog ; $stderrLog"
try {
    $backendProcess = Start-Process `
        -FilePath $mvnw `
        -ArgumentList @("spring-boot:run") `
        -WorkingDirectory $backendDir `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -WindowStyle Hidden `
        -PassThru

    if ($VerifyAfterStart -and -not $SkipHttpCheck) {
        Write-Output "Waiting for local HTTP service before post-start static verification."
        Wait-HttpReady -BaseUrl $BaseUrl -Process $backendProcess -TimeoutSeconds $HttpTimeoutSeconds -PollSeconds $HttpPollSeconds
        Invoke-StaticConsistencyCheck -VerifyScript $verifyScript -BaseUrl $BaseUrl -IncludeHttp $true -ForbiddenText $ForbiddenText
        Write-Output "Post-start HTTP static consistency verification completed."
    } elseif (-not $VerifyAfterStart) {
        Write-Output "Skipped post-start HTTP verification because VerifyAfterStart is false."
    } else {
        Write-Output "Skipped post-start HTTP verification because -SkipHttpCheck was specified."
    }

    Write-Output "Spring Boot is running. Press Ctrl+C to stop it."
    Wait-Process -Id $backendProcess.Id
    if ($backendProcess.ExitCode -ne 0) {
        throw "spring-boot:run failed with exit code $($backendProcess.ExitCode)"
    }
} finally {
    if ($backendProcess -and -not $backendProcess.HasExited) {
        Write-Output "Stopping Spring Boot process tree."
        Stop-ProcessTree -ProcessId $backendProcess.Id
    }
}
