param(
  [string]$LocalEnvPath = "docker/.env.production",
  [string]$LocalComposePath = "docker/docker-compose.yml",
  [string]$LocalShadowEnvExamplePath = "docker/.env.shadow.example",
  [string]$LocalOpsPath = "deploy/raspberry-pi/docker",
  [string]$RootEnvPath = ".env",
  [string]$RemoteAppDir = "/opt/apps/gesp-csp-quiz",
  [string]$Hostname = "rp.randolph87.top",
  [string]$User = "caobin",
  [switch]$Restart,
  [switch]$SkipPull,
  [switch]$Verify,
  [switch]$AllowPlaceholders,
  [switch]$ShadowAssetsOnly
)

$ErrorActionPreference = "Stop"

if ($ShadowAssetsOnly -and ($Restart -or $SkipPull -or $Verify -or $AllowPlaceholders)) {
  throw "-ShadowAssetsOnly cannot be combined with -Restart, -SkipPull, -Verify, or -AllowPlaceholders."
}

if (-not $ShadowAssetsOnly -and -not (Test-Path -LiteralPath $LocalEnvPath)) {
  throw "Local production env file not found: $LocalEnvPath. Copy docker/.env.production.example to docker/.env.production and fill production values first."
}

if (-not (Test-Path -LiteralPath $LocalComposePath)) {
  throw "Local compose file not found: $LocalComposePath"
}

if (-not (Test-Path -LiteralPath $LocalShadowEnvExamplePath)) {
  throw "Local shadow env example not found: $LocalShadowEnvExamplePath"
}

if (-not (Test-Path -LiteralPath $LocalOpsPath -PathType Container)) {
  throw "Local PostgreSQL operations directory not found: $LocalOpsPath"
}

if (-not (Test-Path -LiteralPath $RootEnvPath)) {
  throw "Root env file not found: $RootEnvPath. It must contain MY_SSH_KEY for my-rp."
}

$resolvedLocalEnv = if ($ShadowAssetsOnly) { $null } else { (Resolve-Path -LiteralPath $LocalEnvPath).Path }
$resolvedLocalCompose = (Resolve-Path -LiteralPath $LocalComposePath).Path
$resolvedLocalShadowEnvExample = (Resolve-Path -LiteralPath $LocalShadowEnvExamplePath).Path
$resolvedLocalOps = (Resolve-Path -LiteralPath $LocalOpsPath).Path
$resolvedRootEnv = (Resolve-Path -LiteralPath $RootEnvPath).Path

$localEnvText = if ($ShadowAssetsOnly) { $null } else { Get-Content -Raw -LiteralPath $resolvedLocalEnv }
if (-not $ShadowAssetsOnly -and -not $AllowPlaceholders) {
  $placeholderPatterns = @(
    '<local-postgres-strong-password>',
    '<usb-ssd-mount>',
    '<dr-user>',
    '<dr-password>',
    '<direct-dr-host>',
    '<dr-database>',
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
$tempEnv = if ($ShadowAssetsOnly) { $null } else { [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".env") }

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


shadow_assets_only = os.environ.get("SYNC_SHADOW_ASSETS_ONLY") == "1"
local_env_value = os.environ.get("SYNC_LOCAL_ENV")
local_env = Path(local_env_value) if local_env_value else None
local_compose = Path(os.environ["SYNC_LOCAL_COMPOSE"])
local_shadow_env_example = Path(os.environ["SYNC_LOCAL_SHADOW_ENV_EXAMPLE"])
local_ops = Path(os.environ["SYNC_LOCAL_OPS"])
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
    remote_env_tmp = None
    if not shadow_assets_only:
        remote_env_tmp = f"/tmp/gesp-csp-quiz-env-{stamp}.tmp"
    remote_compose_tmp = f"/tmp/gesp-csp-quiz-compose-{stamp}.tmp"
    remote_shadow_env_example_tmp = f"/tmp/gesp-csp-quiz-shadow-env-example-{stamp}.tmp"
    remote_ops_tmp = f"/tmp/gesp-csp-quiz-ops-{stamp}"
    sftp = client.open_sftp()
    if not shadow_assets_only:
        if local_env is None or remote_env_tmp is None:
            raise SystemExit("production env path is required outside shadow-assets-only mode")
        sftp.put(str(local_env), remote_env_tmp)
    sftp.put(str(local_compose), remote_compose_tmp)
    sftp.put(str(local_shadow_env_example), remote_shadow_env_example_tmp)
    sftp.mkdir(remote_ops_tmp)
    for source in sorted(local_ops.iterdir()):
        if source.is_file():
            sftp.put(str(source), f"{remote_ops_tmp}/{source.name}")
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

    production_env_backup_block = ""
    production_env_install_block = ""
    production_env_result_block = ""
    compose_check_block = r'''
docker compose --env-file .env config >/dev/null
'''
    if shadow_assets_only:
        compose_check_block = r'''
shadow_check_env=$(mktemp)
production_check_env=$(mktemp)
trap 'rm -f -- "$shadow_check_env" "$production_check_env"' EXIT
sed \
  -e 's|^XZS_POSTGRES_PASSWORD=.*|XZS_POSTGRES_PASSWORD=compose-check-only|' \
  -e 's|^XZS_POSTGRES_DATA_DIR=.*|XZS_POSTGRES_DATA_DIR=/tmp/xzs-shadow-compose-check/data|' \
  -e 's|^XZS_AI_CONFIG_SECRET=.*|XZS_AI_CONFIG_SECRET=compose-check-only-32-characters|' \
  .env.shadow.example >"$shadow_check_env"
docker compose \
  --project-name xzs-shadow \
  --env-file "$shadow_check_env" \
  config >/dev/null
sed \
  -e 's|^COMPOSE_PROJECT_NAME=.*|COMPOSE_PROJECT_NAME=xzs-production-check|' \
  -e 's|^XZS_POSTGRES_CONTAINER_NAME=.*|XZS_POSTGRES_CONTAINER_NAME=xzs-postgres|' \
  -e 's|^XZS_APP_CONTAINER_NAME=.*|XZS_APP_CONTAINER_NAME=xzs-app|' \
  -e 's|^XZS_HOST_BIND=.*|XZS_HOST_BIND=0.0.0.0|' \
  -e 's|^XZS_HOST_PORT=.*|XZS_HOST_PORT=8000|' \
  -e 's|^XZS_POSTGRES_DB=.*|XZS_POSTGRES_DB=xzs|' \
  -e 's|^XZS_POSTGRES_USER=.*|XZS_POSTGRES_USER=xzs|' \
  -e 's|^XZS_POSTGRES_DATA_DIR=.*|XZS_POSTGRES_DATA_DIR=/tmp/xzs-production-compose-check/data|' \
  "$shadow_check_env" >"$production_check_env"
docker compose \
  --project-name xzs-production-check \
  --env-file "$production_check_env" \
  config >/dev/null
'''
    else:
        production_env_backup_block = r'''
if [ -f .env ]; then
  cp -a .env "$backup_dir/.env"
  chmod 600 "$backup_dir/.env"
fi
'''
        production_env_install_block = f'''
mv {shlex.quote(remote_env_tmp)} .env
chmod 600 .env
'''
        production_env_result_block = r'''
printf 'SYNCED_ENV=%s\n' "$APP_DIR/.env"
'''

    script = f'''
set -eu
APP_DIR={shlex.quote(remote_app_dir)}
cd "$APP_DIR"
stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="backups/deploy-$stamp"
mkdir -p "$backup_dir"
{production_env_backup_block}
if [ -f docker-compose.yml ]; then
  cp -a docker-compose.yml "$backup_dir/docker-compose.yml"
fi
if [ -f .env.shadow.example ]; then
  cp -a .env.shadow.example "$backup_dir/.env.shadow.example"
fi
if [ -d ops ]; then
  cp -a ops "$backup_dir/ops"
fi
{production_env_install_block}
mv {shlex.quote(remote_compose_tmp)} docker-compose.yml
mv {shlex.quote(remote_shadow_env_example_tmp)} .env.shadow.example
rm -rf -- ops
mv {shlex.quote(remote_ops_tmp)} ops
chmod 640 .env.shadow.example
chmod 750 ops/*.sh
chmod 640 ops/*.service ops/*.timer
{compose_check_block}
{production_env_result_block}
printf 'SYNCED_COMPOSE=%s\n' "$APP_DIR/docker-compose.yml"
printf 'SYNCED_SHADOW_ENV_EXAMPLE=%s\n' "$APP_DIR/.env.shadow.example"
printf 'SYNCED_OPS=%s\n' "$APP_DIR/ops"
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
  if (-not $ShadowAssetsOnly) {
    ConvertTo-ComposeSafeEnv -SourcePath $resolvedLocalEnv -TargetPath $tempEnv
  }
  Set-Content -LiteralPath $tempScript -Value $pythonSource -Encoding UTF8
  if (-not $ShadowAssetsOnly) {
    $env:SYNC_LOCAL_ENV = $tempEnv
  }
  $env:SYNC_LOCAL_COMPOSE = $resolvedLocalCompose
  $env:SYNC_LOCAL_SHADOW_ENV_EXAMPLE = $resolvedLocalShadowEnvExample
  $env:SYNC_LOCAL_OPS = $resolvedLocalOps
  $env:SYNC_ROOT_ENV = $resolvedRootEnv
  $env:SYNC_REMOTE_APP_DIR = $RemoteAppDir
  $env:SYNC_HOSTNAME = $Hostname
  $env:SYNC_USER = $User
  $env:SYNC_RESTART = if ($Restart) { "1" } else { "0" }
  $env:SYNC_SKIP_PULL = if ($SkipPull) { "1" } else { "0" }
  $env:SYNC_VERIFY = if ($Verify) { "1" } else { "0" }
  $env:SYNC_SHADOW_ASSETS_ONLY = if ($ShadowAssetsOnly) { "1" } else { "0" }
  & $python.Source $tempScript
  if ($LASTEXITCODE -ne 0) {
    throw "sync failed with exit code $LASTEXITCODE"
  }
} finally {
  Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
  if ($null -ne $tempEnv) {
    Remove-Item -LiteralPath $tempEnv -Force -ErrorAction SilentlyContinue
  }
  Remove-Item Env:\SYNC_LOCAL_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_LOCAL_COMPOSE -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_LOCAL_SHADOW_ENV_EXAMPLE -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_LOCAL_OPS -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_ROOT_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_REMOTE_APP_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_HOSTNAME -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_USER -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_RESTART -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_SKIP_PULL -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_VERIFY -ErrorAction SilentlyContinue
  Remove-Item Env:\SYNC_SHADOW_ASSETS_ONLY -ErrorAction SilentlyContinue
}
