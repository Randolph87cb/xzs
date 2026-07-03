param(
  [ValidateSet('admin', 'student', 'both')]
  [string]$Target = 'both',

  [switch]$RunVueCliBuild,
  [switch]$RunViteBuild,

  [string]$VueCliCommand = 'npm run build:prod',
  [string]$ViteCommand = 'npm run build:vite'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$frontends = @()

if ($Target -eq 'admin' -or $Target -eq 'both') {
  $frontends += [pscustomobject]@{
    Name = 'admin'
    Path = Join-Path $repoRoot 'source/vue/xzs-admin'
    ExpectedPort = 8002
    VueCliOutput = 'admin'
    ViteOutput = 'admin-vite'
  }
}

if ($Target -eq 'student' -or $Target -eq 'both') {
  $frontends += [pscustomobject]@{
    Name = 'student'
    Path = Join-Path $repoRoot 'source/vue/xzs-student'
    ExpectedPort = 8001
    VueCliOutput = 'student'
    ViteOutput = 'student-vite'
  }
}

function Write-Section {
  param([string]$Title)
  Write-Host ''
  Write-Host "== $Title =="
}

function Test-PackageJson {
  param([string]$FrontendPath)

  $packageJsonPath = Join-Path $FrontendPath 'package.json'
  if (-not (Test-Path -LiteralPath $packageJsonPath)) {
    throw "Missing package.json: $packageJsonPath"
  }

  $json = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
  $scripts = @{}
  if ($json.scripts) {
    $json.scripts.PSObject.Properties | ForEach-Object {
      $scripts[$_.Name] = $_.Value
    }
  }

  $devDependencies = @{}
  if ($json.devDependencies) {
    $json.devDependencies.PSObject.Properties | ForEach-Object {
      $devDependencies[$_.Name] = $_.Value
    }
  }

  $dependencies = @{}
  if ($json.dependencies) {
    $json.dependencies.PSObject.Properties | ForEach-Object {
      $dependencies[$_.Name] = $_.Value
    }
  }

  [pscustomobject]@{
    Vue = $dependencies['vue']
    VueCliService = $devDependencies['@vue/cli-service']
    Vite = $devDependencies['vite']
    Vue2Plugin = $devDependencies['@vitejs/plugin-vue2']
    HasViteBuildScript = $scripts.ContainsKey('build:vite')
  }
}

function Invoke-TimedCommand {
  param(
    [string]$WorkingDirectory,
    [string]$Command,
    [string]$Label
  )

  Write-Host "Running $Label in $WorkingDirectory"
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  Push-Location $WorkingDirectory
  try {
    powershell -NoProfile -ExecutionPolicy Bypass -Command $Command
    if ($LASTEXITCODE -ne 0) {
      throw "$Label failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
    $stopwatch.Stop()
  }

  [pscustomobject]@{
    Label = $Label
    Seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
  }
}

Write-Section 'Vue 2.7 + Vite spike checks'
Write-Host 'This script does not install dependencies, edit package.json, or sync files into backend static.'
Write-Host 'By default it only checks the current frontend setup. Use -RunVueCliBuild or -RunViteBuild to time explicit commands.'

$results = @()

foreach ($frontend in $frontends) {
  Write-Section $frontend.Name
  if (-not (Test-Path -LiteralPath $frontend.Path)) {
    throw "Missing frontend directory: $($frontend.Path)"
  }

  $packageInfo = Test-PackageJson -FrontendPath $frontend.Path
  Write-Host "path: $($frontend.Path)"
  Write-Host "expected dev port: $($frontend.ExpectedPort)"
  Write-Host "vue: $($packageInfo.Vue)"
  Write-Host "vue-cli-service: $($packageInfo.VueCliService)"
  Write-Host "vite: $($packageInfo.Vite)"
  Write-Host "@vitejs/plugin-vue2: $($packageInfo.Vue2Plugin)"
  Write-Host "has build:vite script: $($packageInfo.HasViteBuildScript)"
  Write-Host "vue cli output dir: $($frontend.VueCliOutput)"
  Write-Host "suggested vite output dir: $($frontend.ViteOutput)"

  if ($RunVueCliBuild) {
    $results += Invoke-TimedCommand -WorkingDirectory $frontend.Path -Command $VueCliCommand -Label "$($frontend.Name) Vue CLI build"
  }

  if ($RunViteBuild) {
    if (-not $packageInfo.Vite -or -not $packageInfo.Vue2Plugin) {
      Write-Warning "$($frontend.Name) has no Vite spike dependencies in package.json; skipping Vite timing."
    } elseif (-not $packageInfo.HasViteBuildScript -and $ViteCommand -eq 'npm run build:vite') {
      Write-Warning "$($frontend.Name) has no build:vite script; pass -ViteCommand 'npx vite build --mode prod' if this is an isolated spike checkout."
    } else {
      $results += Invoke-TimedCommand -WorkingDirectory $frontend.Path -Command $ViteCommand -Label "$($frontend.Name) Vite build"
    }
  }
}

if ($results.Count -gt 0) {
  Write-Section 'Timing results'
  $results | Format-Table -AutoSize
} else {
  Write-Section 'Next step'
  Write-Host 'Create an isolated Vite spike checkout, add Vite-only dev dependencies there, then rerun with -RunViteBuild.'
}
