param(
    [switch]$SkipAdmin,
    [switch]$SkipStudent
)

$ErrorActionPreference = "Stop"

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-InWorkspace {
    param(
        [string]$Path,
        [string]$WorkspaceRoot
    )

    $workspaceFull = (Get-FullPath -Path $WorkspaceRoot).TrimEnd('\', '/')
    $targetFull = Get-FullPath -Path $Path
    $prefix = $workspaceFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete outside workspace. Target: $targetFull Workspace: $workspaceFull"
    }

    if ($targetFull.Length -le $prefix.Length) {
        throw "Refusing to delete workspace root or an empty target: $targetFull"
    }

    return $targetFull
}

function Sync-StaticDirectory {
    param(
        [string]$Source,
        [string]$Target,
        [string]$WorkspaceRoot
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory not found: $Source"
    }

    $targetFull = Assert-InWorkspace -Path $Target -WorkspaceRoot $WorkspaceRoot
    if (Test-Path -LiteralPath $targetFull) {
        Remove-Item -LiteralPath $targetFull -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $targetFull | Out-Null
    Copy-Item -Path (Join-Path $Source "*") -Destination $targetFull -Recurse -Force
    Write-Output "Synced $Source -> $targetFull"
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$backendStatic = Join-Path $workspaceRoot "source\xzs\src\main\resources\static"

if (-not $SkipAdmin) {
    Sync-StaticDirectory `
        -Source (Join-Path $workspaceRoot "frontend\apps\admin\admin") `
        -Target (Join-Path $backendStatic "admin") `
        -WorkspaceRoot $workspaceRoot
}

if (-not $SkipStudent) {
    Sync-StaticDirectory `
        -Source (Join-Path $workspaceRoot "frontend\apps\student\student") `
        -Target (Join-Path $backendStatic "student") `
        -WorkspaceRoot $workspaceRoot
}
