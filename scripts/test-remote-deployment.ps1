param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [int]$RetryCount = 30,
    [int]$RetryDelaySeconds = 10,
    [int]$TimeoutSeconds = 20,
    [switch]$SkipAdmin,
    [switch]$SkipStudent
)

$ErrorActionPreference = "Stop"

function Join-RemoteUrl {
    param(
        [string]$Root,
        [string]$Path
    )

    return $Root.TrimEnd("/") + "/" + $Path.TrimStart("/")
}

function Invoke-DeploymentCheck {
    param(
        [string]$Name,
        [string]$Path,
        [scriptblock]$Validate
    )

    $uri = Join-RemoteUrl -Root $BaseUrl -Path $Path
    $lastError = $null

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $response = Invoke-WebRequest `
                -UseBasicParsing `
                -Uri $uri `
                -TimeoutSec $TimeoutSeconds `
                -Headers @{ "Cache-Control" = "no-cache" }

            & $Validate $response
            Write-Output "OK $Name $uri"
            return
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt $RetryCount) {
                Write-Output "WAIT $Name attempt $attempt/$RetryCount failed: $lastError"
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    throw "$Name failed after $RetryCount attempts: $lastError"
}

if ($RetryCount -lt 1) {
    throw "RetryCount must be greater than 0."
}

if ($RetryDelaySeconds -lt 1) {
    throw "RetryDelaySeconds must be greater than 0."
}

$BaseUrl = $BaseUrl.TrimEnd("/")

Invoke-DeploymentCheck -Name "health" -Path "/api/health" -Validate {
    param($response)

    if ([int]$response.StatusCode -ne 200) {
        throw "Expected HTTP 200, got $($response.StatusCode)."
    }

    $health = $response.Content | ConvertFrom-Json
    if ($health.status -ne "UP") {
        throw "Expected health.status=UP, got $($health.status)."
    }

    if ($health.database.status -ne "UP") {
        throw "Expected health.database.status=UP, got $($health.database.status)."
    }
}

if (-not $SkipStudent) {
    Invoke-DeploymentCheck -Name "student index" -Path "/student/index.html" -Validate {
        param($response)

        if ([int]$response.StatusCode -ge 400) {
            throw "Expected HTTP < 400, got $($response.StatusCode)."
        }

        if ($response.Content -notmatch 'type="module"') {
            throw "Student index does not look like a Vite build."
        }
    }
}

if (-not $SkipAdmin) {
    Invoke-DeploymentCheck -Name "admin index" -Path "/admin/index.html" -Validate {
        param($response)

        if ([int]$response.StatusCode -ge 400) {
            throw "Expected HTTP < 400, got $($response.StatusCode)."
        }

        if ($response.Content -notmatch 'type="module"') {
            throw "Admin index does not look like a Vite build."
        }
    }
}

Write-Output "Remote deployment checks passed: $BaseUrl"
