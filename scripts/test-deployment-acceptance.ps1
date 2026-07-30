<#
.SYNOPSIS
Runs HTTP and anonymous read-only browser acceptance checks for a deployment.

.DESCRIPTION
Select Local, Fly, or Raspi, or override the selected target with -BaseUrl.
The default check combines scripts/test-remote-deployment.ps1 with public
student/admin page screenshots from the frontend Playwright dependency.

.PARAMETER Plan
Prints the resolved target, evidence directory, and checks without making
network requests or writing evidence.
#>
param(
    [ValidateSet("Local", "Fly", "Raspi")]
    [string]$Target = "Local",
    [string]$BaseUrl,
    [string]$EvidenceDir,
    [int]$RetryCount = 30,
    [int]$RetryDelaySeconds = 10,
    [int]$TimeoutSeconds = 20,
    [int]$BrowserTimeoutMs = 20000,
    [switch]$SkipHttp,
    [switch]$SkipBrowser,
    [switch]$SkipAdmin,
    [switch]$SkipStudent,
    [switch]$Plan
)

$ErrorActionPreference = "Stop"
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$targetUrls = @{
    Local = "http://127.0.0.1:8000"
    Fly = "https://gesp-csp-quiz.fly.dev"
    Raspi = "https://gesp-csp-quiz.randolph87.top"
}

if ($SkipHttp -and $SkipBrowser) {
    throw "-SkipHttp and -SkipBrowser cannot be combined."
}

if ($SkipAdmin -and $SkipStudent) {
    throw "-SkipAdmin and -SkipStudent cannot be combined."
}

if ($RetryCount -lt 1) {
    throw "RetryCount must be greater than 0."
}

if ($RetryDelaySeconds -lt 1) {
    throw "RetryDelaySeconds must be greater than 0."
}

if ($TimeoutSeconds -lt 1) {
    throw "TimeoutSeconds must be greater than 0."
}

if ($BrowserTimeoutMs -lt 1) {
    throw "BrowserTimeoutMs must be greater than 0."
}

$resolvedTarget = if ($BaseUrl -and -not $PSBoundParameters.ContainsKey("Target")) { "Custom" } else { $Target }
$resolvedBaseUrl = if ($BaseUrl) { $BaseUrl.TrimEnd("/") } else { $targetUrls[$Target] }
$parsedBaseUrl = $null
if (-not [System.Uri]::TryCreate($resolvedBaseUrl, [System.UriKind]::Absolute, [ref]$parsedBaseUrl)) {
    throw "BaseUrl must be an absolute HTTP or HTTPS URL."
}

if ($parsedBaseUrl.Scheme -notin @("http", "https")) {
    throw "BaseUrl must use HTTP or HTTPS."
}

if ($parsedBaseUrl.UserInfo) {
    throw "BaseUrl must not contain credentials."
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
if (-not $EvidenceDir) {
    $EvidenceDir = Join-Path "output\deployment-acceptance" "$timestamp-$($resolvedTarget.ToLowerInvariant())"
}
$resolvedEvidenceDir = if ([System.IO.Path]::IsPathRooted($EvidenceDir)) {
    [System.IO.Path]::GetFullPath($EvidenceDir)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot $EvidenceDir))
}

$httpScript = Join-Path $PSScriptRoot "test-remote-deployment.ps1"
$browserScript = Join-Path $workspaceRoot "frontend\scripts\verify-public-pages.mjs"
$browserEvidenceDir = Join-Path $resolvedEvidenceDir "browser"

if ($Plan) {
    Write-Output "MODE=plan"
    Write-Output "TARGET=$resolvedTarget"
    Write-Output "BASE_URL=$resolvedBaseUrl"
    Write-Output "EVIDENCE_DIR=$resolvedEvidenceDir"
    if (-not $SkipHttp) {
        Write-Output "STEP_HTTP=test-remote-deployment.ps1"
    }
    if (-not $SkipBrowser) {
        Write-Output "STEP_BROWSER=anonymous-read-only student=$(-not $SkipStudent) admin=$(-not $SkipAdmin)"
    }
    return
}

if (-not $SkipHttp -and -not (Test-Path -LiteralPath $httpScript -PathType Leaf)) {
    throw "HTTP check script not found: $httpScript"
}

if (-not $SkipBrowser -and -not (Test-Path -LiteralPath $browserScript -PathType Leaf)) {
    throw "Browser check script not found: $browserScript"
}

New-Item -ItemType Directory -Path $resolvedEvidenceDir -Force | Out-Null

$result = [ordered]@{
    target = $resolvedTarget
    baseUrl = $resolvedBaseUrl
    mode = "anonymous-read-only"
    evidenceDir = $resolvedEvidenceDir
    startedAt = (Get-Date).ToUniversalTime().ToString("o")
    status = "running"
    steps = [ordered]@{}
}
$failure = $null

try {
    if (-not $SkipHttp) {
        $httpLog = Join-Path $resolvedEvidenceDir "http-check.txt"
        try {
            $httpOutput = @(
                & $httpScript `
                    -BaseUrl $resolvedBaseUrl `
                    -RetryCount $RetryCount `
                    -RetryDelaySeconds $RetryDelaySeconds `
                    -TimeoutSeconds $TimeoutSeconds `
                    -SkipAdmin:$SkipAdmin `
                    -SkipStudent:$SkipStudent 2>&1
            )
            $httpOutput | Set-Content -LiteralPath $httpLog -Encoding UTF8
            $result.steps.http = [ordered]@{ status = "passed"; evidence = $httpLog }
            $httpOutput | Write-Output
        } catch {
            $_ | Out-String | Set-Content -LiteralPath $httpLog -Encoding UTF8
            $result.steps.http = [ordered]@{ status = "failed"; evidence = $httpLog }
            throw
        }
    } else {
        $result.steps.http = [ordered]@{ status = "skipped" }
    }

    if (-not $SkipBrowser) {
        $node = Get-Command node -ErrorAction Stop
        $browserLog = Join-Path $resolvedEvidenceDir "browser-check.txt"
        $browserArguments = @(
            $browserScript,
            "--base-url", $resolvedBaseUrl,
            "--output-dir", $browserEvidenceDir,
            "--timeout-ms", $BrowserTimeoutMs
        )
        if ($SkipAdmin) {
            $browserArguments += "--skip-admin"
        }
        if ($SkipStudent) {
            $browserArguments += "--skip-student"
        }

        Push-Location (Join-Path $workspaceRoot "frontend")
        try {
            $browserOutput = @(& $node.Source @browserArguments 2>&1)
            $browserExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $browserOutput | Set-Content -LiteralPath $browserLog -Encoding UTF8
        $browserOutput | Write-Output
        if ($browserExitCode -ne 0) {
            $result.steps.browser = [ordered]@{ status = "failed"; evidence = $browserEvidenceDir; log = $browserLog }
            throw "Browser check failed with exit code $browserExitCode. Evidence: $browserEvidenceDir"
        }
        $result.steps.browser = [ordered]@{ status = "passed"; evidence = $browserEvidenceDir; log = $browserLog }
    } else {
        $result.steps.browser = [ordered]@{ status = "skipped" }
    }

    $result.status = "passed"
} catch {
    $failure = $_
    $result.status = "failed"
    $result.error = $_.Exception.Message
} finally {
    $result.finishedAt = (Get-Date).ToUniversalTime().ToString("o")
    $resultPath = Join-Path $resolvedEvidenceDir "acceptance-result.json"
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($null -ne $failure) {
    throw "$($failure.Exception.Message) Acceptance evidence: $resolvedEvidenceDir"
}

Write-Output "Deployment acceptance passed: $resolvedBaseUrl"
Write-Output "Evidence: $resolvedEvidenceDir"
