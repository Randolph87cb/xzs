param(
  [string]$LocalEnvPath = "docker/.env.production",
  [string]$LocalComposePath = "docker/docker-compose.yml",
  [string]$RootEnvPath = ".env",
  [string]$RemoteAppDir = "/opt/apps/gesp-csp-quiz",
  [string]$Hostname = "rp.randolph87.top",
  [string]$User = "caobin",
  [switch]$Restart,
  [switch]$SkipPull,
  [switch]$Verify,
  [switch]$AllowPlaceholders
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LocalEnvPath)) {
  throw "Local production env file not found: $LocalEnvPath. Copy docker/.env.production.example to docker/.env.production and fill production values first."
}

if (-not (Test-Path -LiteralPath $LocalComposePath)) {
  throw "Local compose file not found: $LocalComposePath"
}

if (-not (Test-Path -LiteralPath $RootEnvPath)) {
  throw "Root env file not found: $RootEnvPath. It must contain MY_SSH_KEY for my-rp."
}

$resolvedLocalEnv = (Resolve-Path -LiteralPath $LocalEnvPath).Path
$resolvedLocalCompose = (Resolve-Path -LiteralPath $LocalComposePath).Path
$resolvedRootEnv = (Resolve-Path -LiteralPath $RootEnvPath).Path

$localEnvText = Get-Content -Raw -LiteralPath $resolvedLocalEnv
if (-not $AllowPlaceholders) {
  $placeholderPatterns = @(
    '<user>',
    '<password>',
    '<production-branch-host>',
    '<database>',
    '<production-secret-32-chars-or-longer>'
  )
  foreach ($pattern in $placeholderPatterns) {
    if ($localEnvText.Contains($pattern)) {
      throw "Local env file still contains placeholder: $pattern. Fill real production values or pass -AllowPlaceholders for a dry copy."
    }
  }
}

function ConvertTo-ComposeSafeEnv {
  param(
    [string]$SourcePath,
    [string]$TargetPath
  )

  $lines = Get-Content -LiteralPath $SourcePath
  $converted = foreach ($line in $lines) {
    if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
      $line
      continue
    }

    $key = $Matches[1]
    $value = $Matches[2].Trim()
    if (-not $value.Contains('$') -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $line
      continue
    }

    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    $escapedValue = $value.Replace("'", "\'")
    "$key='$escapedValue'"
  }

  Set-Content -LiteralPath $TargetPath -Value $converted -Encoding UTF8
}

$python = Get-Command python -ErrorAction Stop
$tempScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")
$tempEnv = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".env")

$pythonSource = @'
import base64
import os
import re
import shlex
import socket
import subprocess
import sys
import time
from pathlib import Path

try:
    import paramiko
except ImportError:
    raise SystemExit("Python module paramiko is required")


def read_env_value(path, key):
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=\s*(.*)\s*$")
    for line in Path(path).read_text(encoding="utf-8", errors="ignore").splitlines():
        match = pattern.match(line)
        if match:
            value = match.group(1).strip()
            if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
                value = value[1:-1]
            return value
    return None


def free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


local_env = Path(os.environ["SYNC_LOCAL_ENV"])
local_compose = Path(os.environ["SYNC_LOCAL_COMPOSE"])
root_env = Path(os.environ["SYNC_ROOT_ENV"])
remote_app_dir = os.environ["SYNC_REMOTE_APP_DIR"]
hostname = os.environ["SYNC_HOSTNAME"]
user = os.environ["SYNC_USER"]
restart = os.environ.get("SYNC_RESTART") == "1"
skip_pull = os.environ.get("SYNC_SKIP_PULL") == "1"
verify = os.environ.get("SYNC_VERIFY") == "1"

password = read_env_value(root_env, "MY_SSH_KEY")
if not password:
    raise SystemExit("MY_SSH_KEY not found in root env file")

port = free_port()
cloudflared = subprocess.Popen(
    ["cloudflared", "access", "tcp", "--hostname", hostname, "--url", f"localhost:{port}"],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)

try:
    deadline = time.time() + 20
    while time.time() < deadline:
        if cloudflared.poll() is not None:
            output = cloudflared.stdout.read() if cloudflared.stdout else ""
            raise SystemExit("cloudflared exited early\n" + output)
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            break
        except OSError:
            time.sleep(0.4)
    else:
        raise SystemExit("cloudflared local tcp tunnel did not open")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        "127.0.0.1",
        port=port,
        username=user,
        password=password,
        timeout=20,
        banner_timeout=20,
        auth_timeout=20,
        look_for_keys=False,
        allow_agent=False,
    )

    stamp = int(time.time())
    remote_env_tmp = f"/tmp/gesp-csp-quiz-env-{stamp}.tmp"
    remote_compose_tmp = f"/tmp/gesp-csp-quiz-compose-{stamp}.tmp"
    sftp = client.open_sftp()
    sftp.put(str(local_env), remote_env_tmp)
    sftp.put(str(local_compose), remote_compose_tmp)
    sftp.close()

    restart_block = ""
    if restart:
        pull_block = "" if skip_pull else "docker compose --env-file .env pull app\n"
        verify_block = ""
        if verify:
            verify_block = r'''
printf '\n--- health ---\n'
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8000/api/health; then
    printf '\nHEALTH_OK\n'
    break
  fi
  sleep 2
  if [ "$i" = "30" ]; then
    printf '\nHEALTH_FAIL\n'
    docker logs --tail=120 xzs-app | sed -n '/password/Id; /SPRING_DATASOURCE/Id; p'
    exit 1
  fi
done
printf '\n--- pages ---\n'
curl -I --max-time 10 http://127.0.0.1:8000/student/index.html | head -n 1
curl -I --max-time 10 http://127.0.0.1:8000/admin/index.html | head -n 1
'''
        restart_block = pull_block + r'''
docker compose --env-file .env up -d --remove-orphans
docker compose --env-file .env ps
''' + verify_block

    script = f'''
set -eu
APP_DIR={shlex.quote(remote_app_dir)}
cd "$APP_DIR"
stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="backups/deploy-$stamp"
mkdir -p "$backup_dir"
if [ -f .env ]; then
  cp -a .env "$backup_dir/.env"
  chmod 600 "$backup_dir/.env"
fi
if [ -f docker-compose.yml ]; then
  cp -a docker-compose.yml "$backup_dir/docker-compose.yml"
fi
mv {shlex.quote(remote_env_tmp)} .env
mv {shlex.quote(remote_compose_tmp)} docker-compose.yml
chmod 600 .env
docker compose --env-file .env config >/dev/null
printf 'SYNCED_ENV=%s\n' "$APP_DIR/.env"
printf 'SYNCED_COMPOSE=%s\n' "$APP_DIR/docker-compose.yml"
printf 'BACKUP_DIR=%s\n' "$APP_DIR/$backup_dir"
printf 'COMPOSE_CHECK=ok\n'
{restart_block}
'''
    encoded = base64.b64encode(script.encode()).decode()
    stdin, stdout, stderr = client.exec_command("printf %s " + shlex.quote(encoded) + " | base64 -d | bash")
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    rc = stdout.channel.recv_exit_status()
    print(out, end="")
    if err:
        print("\nSTDERR\n" + err, end="")
    if rc:
        raise SystemExit(rc)
    client.close()
finally:
    cloudflared.terminate()
    try:
        cloudflared.wait(timeout=5)
    except subprocess.TimeoutExpired:
        cloudflared.kill()
'@

try {
  ConvertTo-ComposeSafeEnv -SourcePath $resolvedLocalEnv -TargetPath $tempEnv
  Set-Content -LiteralPath $tempScript -Value $pythonSource -Encoding UTF8
  $env:SYNC_LOCAL_ENV = $tempEnv
  $env:SYNC_LOCAL_COMPOSE = $resolvedLocalCompose
  $env:SYNC_ROOT_ENV = $resolvedRootEnv
  $env:SYNC_REMOTE_APP_DIR = $RemoteAppDir
  $env:SYNC_HOSTNAME = $Hostname
  $env:SYNC_USER = $User
  $env:SYNC_RESTART = if ($Restart) { "1" } else { "0" }
  $env:SYNC_SKIP_PULL = if ($SkipPull) { "1" } else { "0" }
  $env:SYNC_VERIFY = if ($Verify) { "1" } else { "0" }
  & $python.Source $tempScript
  if ($LASTEXITCODE -ne 0) {
    throw "sync failed with exit code $LASTEXITCODE"
  }
} finally {
  Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tempEnv -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_LOCAL_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_LOCAL_COMPOSE -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_ROOT_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_REMOTE_APP_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_HOSTNAME -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_USER -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_RESTART -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_SKIP_PULL -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_VERIFY -ErrorAction SilentlyContinue
}
