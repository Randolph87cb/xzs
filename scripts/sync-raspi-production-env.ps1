param(
  [string]$LocalEnvPath = "docker/.env.production",
  [string]$RootEnvPath = ".env",
  [string]$RemoteAppDir = "/opt/apps/gesp-csp-quiz",
  [string]$Hostname = "rp.randolph87.top",
  [string]$User = "caobin",
  [switch]$Restart,
  [switch]$AllowPlaceholders
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LocalEnvPath)) {
  throw "Local production env file not found: $LocalEnvPath. Copy docker/.env.production.example to docker/.env.production and fill production values first."
}

if (-not (Test-Path -LiteralPath $RootEnvPath)) {
  throw "Root env file not found: $RootEnvPath. It must contain MY_SSH_KEY for my-rp."
}

$resolvedLocalEnv = (Resolve-Path -LiteralPath $LocalEnvPath).Path
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

$python = Get-Command python -ErrorAction Stop
$tempScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")

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
root_env = Path(os.environ["SYNC_ROOT_ENV"])
remote_app_dir = os.environ["SYNC_REMOTE_APP_DIR"]
hostname = os.environ["SYNC_HOSTNAME"]
user = os.environ["SYNC_USER"]
restart = os.environ.get("SYNC_RESTART") == "1"

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

    remote_tmp = f"/tmp/gesp-csp-quiz-env-{int(time.time())}.tmp"
    sftp = client.open_sftp()
    sftp.put(str(local_env), remote_tmp)
    sftp.close()

    restart_block = ""
    if restart:
        restart_block = r'''
docker compose --env-file .env pull app
docker compose --env-file .env up -d --remove-orphans
docker compose --env-file .env ps
'''

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
mv {shlex.quote(remote_tmp)} .env
chmod 600 .env
docker compose --env-file .env config >/dev/null
printf 'SYNCED_ENV=%s\n' "$APP_DIR/.env"
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
  Set-Content -LiteralPath $tempScript -Value $pythonSource -Encoding UTF8
  $env:SYNC_LOCAL_ENV = $resolvedLocalEnv
  $env:SYNC_ROOT_ENV = $resolvedRootEnv
  $env:SYNC_REMOTE_APP_DIR = $RemoteAppDir
  $env:SYNC_HOSTNAME = $Hostname
  $env:SYNC_USER = $User
  $env:SYNC_RESTART = if ($Restart) { "1" } else { "0" }
  & $python.Source $tempScript
  if ($LASTEXITCODE -ne 0) {
    throw "sync failed with exit code $LASTEXITCODE"
  }
} finally {
  Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_LOCAL_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_ROOT_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_REMOTE_APP_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_HOSTNAME -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_USER -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_RESTART -ErrorAction SilentlyContinue
}
