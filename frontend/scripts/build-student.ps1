$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    pnpm --filter @xzs/student build
} finally {
    Pop-Location
}
