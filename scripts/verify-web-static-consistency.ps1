param(
    [string]$BaseUrl = "http://127.0.0.1:8000",
    [switch]$SkipHttpCheck,
    [switch]$AllowMissingRuntimeStatic,
    [switch]$SkipAdmin,
    [switch]$SkipStudent,
    [string[]]$ForbiddenText = @()
)

$ErrorActionPreference = "Stop"

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
}

function Get-NormalizedEntryAssets {
    param(
        [string]$IndexPath,
        [string]$AppName
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        throw "Missing $AppName index.html: $IndexPath"
    }

    $content = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8
    $matches = [regex]::Matches($content, '(?:src|href)=["''](?<asset>[^"'']+\.(?:js|css))(?:\?[^"'']*)?["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $assets = New-Object System.Collections.Generic.List[string]

    foreach ($match in $matches) {
        $asset = $match.Groups["asset"].Value.Trim()
        $asset = $asset -replace '\\', '/'
        $asset = $asset.TrimStart('.')
        $asset = $asset.TrimStart('/')

        $appPrefix = "$AppName/"
        if ($asset.StartsWith($appPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $asset = $asset.Substring($appPrefix.Length)
        }

        if (-not $assets.Contains($asset)) {
            $assets.Add($asset)
        }
    }

    $jsAssets = @($assets | Where-Object { $_ -match '\.js$' } | Sort-Object)
    $cssAssets = @($assets | Where-Object { $_ -match '\.css$' } | Sort-Object)

    if ($jsAssets.Count -lt 1) {
        throw "$AppName index.html does not reference an entry JavaScript asset: $IndexPath"
    }

    if ($cssAssets.Count -lt 1) {
        throw "$AppName index.html does not reference an entry CSS asset: $IndexPath"
    }

    return [pscustomobject]@{
        Js = $jsAssets
        Css = $cssAssets
        Key = (($jsAssets + $cssAssets) -join "`n")
    }
}

function Assert-EntryAssetsEqual {
    param(
        [string]$AppName,
        [string]$ExpectedName,
        [object]$Expected,
        [string]$ActualName,
        [object]$Actual
    )

    if ($Expected.Key -ne $Actual.Key) {
        throw @"
$AppName static entry assets differ.
Expected from ${ExpectedName}:
JS: $($Expected.Js -join ', ')
CSS: $($Expected.Css -join ', ')
Actual from ${ActualName}:
JS: $($Actual.Js -join ', ')
CSS: $($Actual.Css -join ', ')
"@
    }
}

function Get-HttpEntryAssets {
    param(
        [string]$Url,
        [string]$AppName
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url
    } catch {
        throw "Failed to fetch $AppName index from $Url. Start the backend or pass -SkipHttpCheck. $($_.Exception.Message)"
    }

    if ([int]$response.StatusCode -ge 400) {
        throw "Failed to fetch $AppName index from $Url. HTTP $($response.StatusCode)"
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tempFile, $response.Content, [System.Text.Encoding]::UTF8)
        return Get-NormalizedEntryAssets -IndexPath $tempFile -AppName $AppName
    } finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Assert-ForbiddenTextAbsent {
    param(
        [string]$AppName,
        [string]$RuntimeAppRoot,
        [string[]]$TextList
    )

    if ($TextList.Count -eq 0) {
        return
    }

    $runtimeStatic = Join-Path $RuntimeAppRoot "static"
    if (-not (Test-Path -LiteralPath $runtimeStatic -PathType Container)) {
        Write-Output "Skip forbidden text check for $AppName because runtime static directory is missing: $runtimeStatic"
        return
    }

    $bundleFiles = @(Get-ChildItem -LiteralPath $runtimeStatic -File -Recurse -Include "*.js", "*.css")
    foreach ($text in $TextList) {
        if ([string]::IsNullOrEmpty($text)) {
            continue
        }

        foreach ($file in $bundleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            if ($content.Contains($text)) {
                throw "Forbidden text was found in $AppName runtime bundle: $($file.FullName)"
            }
        }
    }
}

function Test-AppStaticConsistency {
    param(
        [string]$AppName,
        [string]$ViteRoot,
        [string]$ResourceRoot,
        [string]$RuntimeRoot,
        [string]$BaseUrl,
        [bool]$ShouldSkipHttpCheck,
        [bool]$ShouldAllowMissingRuntimeStatic,
        [string[]]$ForbiddenText
    )

    $viteIndex = Join-Path $ViteRoot "index.html"
    $resourceIndex = Join-Path $ResourceRoot "index.html"

    $viteAssets = Get-NormalizedEntryAssets -IndexPath $viteIndex -AppName $AppName
    $resourceAssets = Get-NormalizedEntryAssets -IndexPath $resourceIndex -AppName $AppName
    Assert-EntryAssetsEqual -AppName $AppName -ExpectedName $viteIndex -Expected $viteAssets -ActualName $resourceIndex -Actual $resourceAssets

    $runtimeParent = Split-Path -Parent $RuntimeRoot
    if (Test-Path -LiteralPath $runtimeParent -PathType Container) {
        if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
            if ($ShouldAllowMissingRuntimeStatic) {
                Write-Output "Runtime static directory missing for $AppName, allowed by -AllowMissingRuntimeStatic: $RuntimeRoot"
            } else {
                throw "$AppName runtime static directory is missing while target/classes/static exists: $RuntimeRoot. Run scripts/sync-web-static.ps1 or package the backend first, or pass -AllowMissingRuntimeStatic only when the backend is configured to read local Vite output directly."
            }
        } else {
            $runtimeIndex = Join-Path $RuntimeRoot "index.html"
            $runtimeAssets = Get-NormalizedEntryAssets -IndexPath $runtimeIndex -AppName $AppName
            Assert-EntryAssetsEqual -AppName $AppName -ExpectedName $viteIndex -Expected $viteAssets -ActualName $runtimeIndex -Actual $runtimeAssets
            Assert-ForbiddenTextAbsent -AppName $AppName -RuntimeAppRoot $RuntimeRoot -TextList $ForbiddenText
        }
    } elseif ($ShouldAllowMissingRuntimeStatic) {
        Write-Output "Runtime static root missing for $AppName, allowed by -AllowMissingRuntimeStatic: $runtimeParent"
    } else {
        throw "$AppName runtime static root is missing: $runtimeParent. Run scripts/sync-web-static.ps1 or package the backend first, or pass -AllowMissingRuntimeStatic only when the backend is configured to read local Vite output directly."
    }

    if (-not $ShouldSkipHttpCheck) {
        $httpUrl = "$($BaseUrl.TrimEnd('/'))/$AppName/index.html"
        $httpAssets = Get-HttpEntryAssets -Url $httpUrl -AppName $AppName
        Assert-EntryAssetsEqual -AppName $AppName -ExpectedName $viteIndex -Expected $viteAssets -ActualName $httpUrl -Actual $httpAssets
    }

    Write-Output "$AppName static entries are consistent. JS=$($viteAssets.Js -join ', ') CSS=$($viteAssets.Css -join ', ')"
}

Set-NoProxyValue -RequiredHosts @("localhost", "127.0.0.1", "::1")

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$backendStatic = Join-Path $workspaceRoot "source\xzs\src\main\resources\static"
$runtimeStatic = Join-Path $workspaceRoot "source\xzs\target\classes\static"

if (-not $SkipAdmin) {
    Test-AppStaticConsistency `
        -AppName "admin" `
        -ViteRoot (Join-Path $workspaceRoot "frontend\apps\admin\admin") `
        -ResourceRoot (Join-Path $backendStatic "admin") `
        -RuntimeRoot (Join-Path $runtimeStatic "admin") `
        -BaseUrl $BaseUrl `
        -ShouldSkipHttpCheck ([bool]$SkipHttpCheck) `
        -ShouldAllowMissingRuntimeStatic ([bool]$AllowMissingRuntimeStatic) `
        -ForbiddenText $ForbiddenText
}

if (-not $SkipStudent) {
    Test-AppStaticConsistency `
        -AppName "student" `
        -ViteRoot (Join-Path $workspaceRoot "frontend\apps\student\student") `
        -ResourceRoot (Join-Path $backendStatic "student") `
        -RuntimeRoot (Join-Path $runtimeStatic "student") `
        -BaseUrl $BaseUrl `
        -ShouldSkipHttpCheck ([bool]$SkipHttpCheck) `
        -ShouldAllowMissingRuntimeStatic ([bool]$AllowMissingRuntimeStatic) `
        -ForbiddenText $ForbiddenText
}

Write-Output "Web static consistency check completed."
