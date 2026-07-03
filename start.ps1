param(
    [string]$Profile = "dev",
    [int]$Port = 8000,
    [int]$DbPort = 5432,
    [switch]$NoDatabase
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Join-Path $Root "source\xzs"
$Jar = Join-Path $AppDir "target\xzs-3.9.0.jar"
$RuntimeDir = Join-Path $Root ".tmp\runtime"
$PidFile = Join-Path $RuntimeDir "xzs.pid"
$DbMarkerFile = Join-Path $RuntimeDir "xzs-postgres.started"
$OutLog = Join-Path $RuntimeDir "xzs.out.log"
$ErrLog = Join-Path $RuntimeDir "xzs.err.log"
$SqlFile = Join-Path $Root "sql\xzs-postgresql.sql"
$DbContainer = "xzs-postgres"
$DbVolume = "xzs-postgres-data"
$DbImage = "postgres:12-alpine"

function Test-Port {
    param([string]$HostName, [int]$PortNumber)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $PortNumber, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(500, $false)) {
            return $false
        }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Wait-Port {
    param([string]$HostName, [int]$PortNumber, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port -HostName $HostName -PortNumber $PortNumber) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Test-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $false
    }
    docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-ProcessByPidFile {
    if (-not (Test-Path -LiteralPath $PidFile)) {
        return $null
    }
    $pidValue = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if (-not $pidValue) {
        return $null
    }
    return Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

$existingProcess = Get-ProcessByPidFile
if ($existingProcess) {
    Write-Output "XZS is already running. PID: $($existingProcess.Id)"
    Write-Output "Admin:   http://localhost:$Port/admin/index.html"
    Write-Output "Student: http://localhost:$Port/student/index.html"
    exit 0
}

if (-not (Test-Path -LiteralPath $Jar)) {
    throw "Jar not found: $Jar. Build the backend first with Maven package."
}

if (-not $NoDatabase) {
    if (Test-DockerReady) {
        $containerNames = docker ps -a --format "{{.Names}}"
        if ($containerNames -contains $DbContainer) {
            $mappedDbPort = docker inspect $DbContainer --format "{{(index (index .HostConfig.PortBindings `"5432/tcp`") 0).HostPort}}"
            if ($mappedDbPort) {
                $DbPort = [int]$mappedDbPort
            }
        }
    }

    if (-not (Test-Port -HostName "127.0.0.1" -PortNumber $DbPort)) {
        if (-not (Test-DockerReady)) {
            throw "PostgreSQL is not listening on localhost:$DbPort and Docker daemon is not ready. Start Docker Desktop or start PostgreSQL manually."
        }
        if (-not (Test-Path -LiteralPath $SqlFile)) {
            throw "SQL init file not found: $SqlFile"
        }

        $containerNames = docker ps -a --format "{{.Names}}"
        if ($containerNames -contains $DbContainer) {
            docker start $DbContainer | Out-Null
            $mappedDbPort = docker inspect $DbContainer --format "{{(index (index .HostConfig.PortBindings `"5432/tcp`") 0).HostPort}}"
            if ($mappedDbPort) {
                $DbPort = [int]$mappedDbPort
            }
        } else {
            docker volume create $DbVolume | Out-Null
            docker run `
                --name $DbContainer `
                -e POSTGRES_PASSWORD=123456 `
                -e POSTGRES_DB=xzs `
                -p ${DbPort}:5432 `
                -v "${DbVolume}:/var/lib/postgresql/data" `
                -v "${SqlFile}:/docker-entrypoint-initdb.d/01-xzs-postgresql.sql:ro" `
                -d $DbImage | Out-Null
        }
        Set-Content -LiteralPath $DbMarkerFile -Value $DbContainer -Encoding UTF8

        if (-not (Wait-Port -HostName "127.0.0.1" -PortNumber $DbPort -TimeoutSeconds 90)) {
            throw "PostgreSQL did not become ready on localhost:$DbPort."
        }
        Start-Sleep -Seconds 5
    }
}

if (Test-Port -HostName "127.0.0.1" -PortNumber $Port) {
    throw "Port $Port is already in use."
}

$javaCommand = (Get-Command java -ErrorAction SilentlyContinue)
if (-not $javaCommand) {
    throw "java was not found in PATH."
}

$arguments = @(
    "-Duser.timezone=Asia/Shanghai",
    "-Dspring.profiles.active=$Profile",
    "-jar",
    $Jar,
    "--spring.datasource.url=jdbc:postgresql://localhost:$DbPort/xzs",
    "--spring.datasource.username=postgres",
    "--spring.datasource.password=123456"
)

$process = Start-Process `
    -FilePath $javaCommand.Source `
    -ArgumentList $arguments `
    -WorkingDirectory $AppDir `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -WindowStyle Hidden `
    -PassThru

Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII

if (-not (Wait-Port -HostName "127.0.0.1" -PortNumber $Port -TimeoutSeconds 90)) {
    $exited = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $exited) {
        Write-Output "XZS failed to start. Error log:"
        if (Test-Path -LiteralPath $ErrLog) {
            Get-Content -LiteralPath $ErrLog -Tail 80
        }
        exit 1
    }
    throw "XZS did not become ready on port $Port within 90 seconds. Check logs in $RuntimeDir."
}

Write-Output "XZS started. PID: $($process.Id)"
Write-Output "Admin:   http://localhost:$Port/admin/index.html"
Write-Output "Student: http://localhost:$Port/student/index.html"
Write-Output "Database: localhost:$DbPort/xzs"
Write-Output "Logs:    $RuntimeDir"
