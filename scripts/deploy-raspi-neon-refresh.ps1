[CmdletBinding()]
param(
  [string]$LocalRefreshEnvPath = "docker/.env.neon-production-refresh",
  [string]$LocalOpsPath = "deploy/raspberry-pi/docker",
  [string]$RootEnvPath = ".env",
  [string]$RemoteAppDir = "/opt/apps/gesp-csp-quiz",
  [string]$Hostname = "rp.randolph87.top",
  [string]$User = "caobin",
  [switch]$Plan,
  [switch]$RunOnce,
  [switch]$EnableTimer,
  [string]$ConfirmManualRun = "",
  [string]$ConfirmEnableTimer = "",
  [switch]$ConfirmSevenDayObservationCompleted
)

$ErrorActionPreference = "Stop"

$manualRunConfirmation = "REFRESH_NEON_PRODUCTION_AND_RESET_TEST"
$enableTimerConfirmation = "ENABLE_DAILY_NEON_PRODUCTION_REFRESH_AND_TEST_RESET"

if ($RunOnce -and $EnableTimer) {
  throw "-RunOnce and -EnableTimer must be separate invocations so the first manual cycle can be observed before scheduling."
}
if ($RunOnce -and $ConfirmManualRun -cne $manualRunConfirmation) {
  throw "-RunOnce requires -ConfirmManualRun $manualRunConfirmation."
}
if (-not $RunOnce -and $ConfirmManualRun) {
  throw "-ConfirmManualRun is only valid with -RunOnce."
}
if ($EnableTimer) {
  if ($ConfirmEnableTimer -cne $enableTimerConfirmation) {
    throw "-EnableTimer requires -ConfirmEnableTimer $enableTimerConfirmation."
  }
  if (-not $ConfirmSevenDayObservationCompleted) {
    throw "-EnableTimer requires -ConfirmSevenDayObservationCompleted."
  }
}
if (-not $EnableTimer -and ($ConfirmEnableTimer -or $ConfirmSevenDayObservationCompleted)) {
  throw "Timer confirmations are only valid with -EnableTimer."
}

if ($Plan) {
  if ($RunOnce -or $EnableTimer -or $ConfirmManualRun -or $ConfirmEnableTimer -or $ConfirmSevenDayObservationCompleted) {
    throw "-Plan cannot be combined with execution or confirmation parameters."
  }
  Write-Output "MODE=plan"
  Write-Output "NETWORK_ACCESS=none"
  Write-Output "SECRET_READ=none"
  Write-Output "DEFAULT_ACTION=install assets and dedicated root 0600 environment; run offline preflight; keep timer disabled"
  Write-Output "MANUAL_ACTION=run production refresh, then reset test with --preserve-current through the manual oneshot unit"
  Write-Output "MANUAL_PARAMETERS=-RunOnce -ConfirmManualRun $manualRunConfirmation"
  Write-Output "ENABLE_ACTION=-EnableTimer -ConfirmEnableTimer $enableTimerConfirmation -ConfirmSevenDayObservationCompleted"
  return
}

function Resolve-RepositoryPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  $repositoryRoot = Split-Path -Parent $PSScriptRoot
  return Join-Path $repositoryRoot $Path
}

function Read-SimpleEnvValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Key
  )

  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*)\s*$')) {
      $value = $Matches[1].Trim()
      if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
          ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      return $value
    }
  }
  return $null
}

function Test-RefreshEnvironmentFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $requiredKeys = @(
    "NEON_DR_DIRECT_URL",
    "XZS_NEON_PRODUCTION_TARGET_FINGERPRINT",
    "XZS_NEON_TEST_TARGET_FINGERPRINT",
    "XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS",
    "NEON_API_KEY",
    "NEON_PROJECT_ID",
    "NEON_SOURCE_BRANCH_NAME",
    "NEON_TARGET_BRANCH_NAME",
    "NEON_EXPECTED_TEST_ENDPOINT_ID",
    "NEON_TEST_DIRECT_URL",
    "NEON_TEST_FLY_BASE_URL",
    "NEON_TEST_PRESERVE_PREFIX",
    "XZS_BACKUP_ROOT",
    "XZS_BACKUP_EXPECTED_MOUNT_TARGET",
    "XZS_BACKUP_EXPECTED_FSTYPE",
    "XZS_POSTGRES_OPS_LOCK_FILE"
  )
  $entries = @{}
  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $lineNumber++
    if ($line -match '^\s*(#.*)?$') {
      continue
    }
    if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      throw "Dedicated Neon refresh env has invalid syntax at line $lineNumber."
    }
    $key = $Matches[1]
    $value = $Matches[2].Trim()
    if ($entries.ContainsKey($key)) {
      throw "Dedicated Neon refresh env contains a duplicate key: $key."
    }
    if (-not $value) {
      throw "Dedicated Neon refresh env contains an empty value for: $key."
    }
    if ($value -match '<[^>]+>') {
      throw "Dedicated Neon refresh env still contains a placeholder for: $key."
    }
    $entries[$key] = $value
  }
  foreach ($key in $requiredKeys) {
    if (-not $entries.ContainsKey($key)) {
      throw "Dedicated Neon refresh env is missing required key: $key."
    }
  }
  if ($entries["XZS_NEON_PRODUCTION_TARGET_FINGERPRINT"] -notmatch '^sha256:[0-9a-f]{64}$' -or
      $entries["XZS_NEON_TEST_TARGET_FINGERPRINT"] -notmatch '^sha256:[0-9a-f]{64}$') {
    throw "Dedicated Neon refresh env contains an invalid target fingerprint."
  }
  if ($entries["XZS_NEON_PRODUCTION_TARGET_FINGERPRINT"] -ceq $entries["XZS_NEON_TEST_TARGET_FINGERPRINT"]) {
    throw "Production and test target fingerprints must be different."
  }
  if ($entries["NEON_SOURCE_BRANCH_NAME"] -ceq $entries["NEON_TARGET_BRANCH_NAME"]) {
    throw "Neon source and target branch names must be different."
  }
}

$resolvedRefreshEnv = Resolve-RepositoryPath $LocalRefreshEnvPath
$resolvedOps = Resolve-RepositoryPath $LocalOpsPath
$resolvedRootEnv = Resolve-RepositoryPath $RootEnvPath

if (-not (Test-Path -LiteralPath $resolvedRefreshEnv -PathType Leaf)) {
  throw "Dedicated Neon refresh env file not found. Copy docker/.env.neon-production-refresh.example to docker/.env.neon-production-refresh and fill it first."
}
if (-not (Test-Path -LiteralPath $resolvedOps -PathType Container)) {
  throw "Local PostgreSQL operations directory not found: $LocalOpsPath"
}
if (-not (Test-Path -LiteralPath $resolvedRootEnv -PathType Leaf)) {
  throw "Root env file not found: $RootEnvPath. It must contain MY_SSH_KEY for my-rp."
}
if ($RemoteAppDir -notmatch '^/[A-Za-z0-9._/-]+$') {
  throw "RemoteAppDir must be a safe absolute Unix path."
}
if ($Hostname -notmatch '^[A-Za-z0-9.-]+$' -or $User -notmatch '^[A-Za-z_][A-Za-z0-9_-]*$') {
  throw "Hostname or User contains unsupported characters."
}

$assetNames = @(
  "postgres-ops-common.sh",
  "refresh-neon-disaster-recovery.sh",
  "refresh-neon-dr-from-latest.sh",
  "reset-neon-test-from-production.py",
  "xzs-neon-dr-refresh-manual.service",
  "xzs-neon-dr-refresh.service",
  "xzs-neon-dr-refresh.timer"
)
foreach ($assetName in $assetNames) {
  $assetPath = Join-Path $resolvedOps $assetName
  if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
    throw "Required Neon refresh deployment asset not found: $assetName"
  }
}

Test-RefreshEnvironmentFile -Path $resolvedRefreshEnv

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$refreshEnvFullPath = (Resolve-Path -LiteralPath $resolvedRefreshEnv).Path
$repositoryFullPath = (Resolve-Path -LiteralPath $repositoryRoot).Path.TrimEnd('\')
if ($refreshEnvFullPath.StartsWith($repositoryFullPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  $relativeRefreshEnv = $refreshEnvFullPath.Substring($repositoryFullPath.Length + 1).Replace('\', '/')
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $git) {
    throw "git is required to prove that the local dedicated secret file is ignored."
  }
  Push-Location $repositoryFullPath
  try {
    & $git.Source check-ignore --quiet -- $relativeRefreshEnv
    if ($LASTEXITCODE -ne 0) {
      throw "The local dedicated Neon refresh env file is not ignored by Git."
    }
  } finally {
    Pop-Location
  }
}

$sshPassword = Read-SimpleEnvValue -Path $resolvedRootEnv -Key "MY_SSH_KEY"
if (-not $sshPassword) {
  throw "MY_SSH_KEY not found in root env file."
}
$sshPassword = $null

$python = Get-Command python -ErrorAction Stop
$tempScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")

$pythonSource = @'
import contextlib
import os
import re
import secrets
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


ASSET_NAMES = (
    "postgres-ops-common.sh",
    "refresh-neon-disaster-recovery.sh",
    "refresh-neon-dr-from-latest.sh",
    "reset-neon-test-from-production.py",
    "xzs-neon-dr-refresh-manual.service",
    "xzs-neon-dr-refresh.service",
    "xzs-neon-dr-refresh.timer",
)


def read_env_value(path, key):
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=\s*(.*)\s*$")
    for raw_line in Path(path).read_text(encoding="utf-8", errors="strict").splitlines():
        match = pattern.match(raw_line)
        if not match:
            continue
        value = match.group(1).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        return value
    return None


def free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


local_env = Path(os.environ["NEON_REFRESH_LOCAL_ENV"])
local_ops = Path(os.environ["NEON_REFRESH_LOCAL_OPS"])
root_env = Path(os.environ["NEON_REFRESH_ROOT_ENV"])
remote_app_dir = os.environ["NEON_REFRESH_REMOTE_APP_DIR"]
hostname = os.environ["NEON_REFRESH_HOSTNAME"]
user = os.environ["NEON_REFRESH_USER"]
run_once = os.environ.get("NEON_REFRESH_RUN_ONCE") == "1"
enable_timer = os.environ.get("NEON_REFRESH_ENABLE_TIMER") == "1"

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

client = None
try:
    deadline = time.time() + 20
    while time.time() < deadline:
        if cloudflared.poll() is not None:
            raise SystemExit("cloudflared exited before the local tunnel opened")
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

    nonce = secrets.token_hex(12)
    remote_stage = f"/tmp/xzs-neon-refresh-assets-{nonce}"
    remote_env = f"/tmp/xzs-neon-refresh-env-{nonce}"
    sftp = client.open_sftp()
    try:
        sftp.mkdir(remote_stage, mode=0o700)
        for name in ASSET_NAMES:
            sftp.put(str(local_ops / name), f"{remote_stage}/{name}")
        sftp.put(str(local_env), remote_env)
        sftp.chmod(remote_env, 0o600)
    finally:
        sftp.close()

    script = f'''set -euo pipefail
APP_DIR={shlex.quote(remote_app_dir)}
STAGE={shlex.quote(remote_stage)}
UPLOADED_ENV={shlex.quote(remote_env)}
RUN_ONCE={"1" if run_once else "0"}
ENABLE_TIMER={"1" if enable_timer else "0"}
timer_enable_pending=0
cleanup() {{
  cleanup_rc=$?
  trap - EXIT
  if [ "$timer_enable_pending" = "1" ]; then
    systemctl disable --now xzs-neon-dr-refresh.timer >/dev/null 2>&1 || true
  fi
  rm -rf -- "$STAGE" || true
  rm -f -- "$UPLOADED_ENV" || true
  exit "$cleanup_rc"
}}
trap cleanup EXIT

systemctl disable --now xzs-neon-dr-refresh.timer >/dev/null 2>&1 || true
if systemctl is-active --quiet xzs-neon-dr-refresh.service || systemctl is-active --quiet xzs-neon-dr-refresh-manual.service; then
  printf 'DEPLOY_FAIL=refresh_service_active\n' >&2
  exit 1
fi

install -d -o root -g root -m 0755 "$APP_DIR" "$APP_DIR/ops" /etc/xzs
install -o root -g root -m 0750 "$STAGE/postgres-ops-common.sh" "$APP_DIR/ops/postgres-ops-common.sh"
install -o root -g root -m 0750 "$STAGE/refresh-neon-disaster-recovery.sh" "$APP_DIR/ops/refresh-neon-disaster-recovery.sh"
install -o root -g root -m 0750 "$STAGE/refresh-neon-dr-from-latest.sh" "$APP_DIR/ops/refresh-neon-dr-from-latest.sh"
install -o root -g root -m 0750 "$STAGE/reset-neon-test-from-production.py" "$APP_DIR/ops/reset-neon-test-from-production.py"
install -o root -g root -m 0600 "$UPLOADED_ENV" /etc/xzs/neon-production-refresh.env
install -o root -g root -m 0644 "$STAGE/xzs-neon-dr-refresh-manual.service" /etc/systemd/system/xzs-neon-dr-refresh-manual.service
install -o root -g root -m 0644 "$STAGE/xzs-neon-dr-refresh.service" /etc/systemd/system/xzs-neon-dr-refresh.service
install -o root -g root -m 0644 "$STAGE/xzs-neon-dr-refresh.timer" /etc/systemd/system/xzs-neon-dr-refresh.timer

test ! -L /etc/xzs/neon-production-refresh.env
test "$(stat --format '%u:%g:%a' /etc/xzs/neon-production-refresh.env)" = "0:0:600"
bash -n "$APP_DIR/ops/postgres-ops-common.sh"
bash -n "$APP_DIR/ops/refresh-neon-disaster-recovery.sh"
bash -n "$APP_DIR/ops/refresh-neon-dr-from-latest.sh"
python3 - "$APP_DIR/ops/reset-neon-test-from-production.py" <<'PY_VALIDATE'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
PY_VALIDATE
python3 - /etc/xzs/neon-production-refresh.env <<'PY_ENV'
from pathlib import Path
import re
import sys

required = {{
    "NEON_DR_DIRECT_URL", "XZS_NEON_PRODUCTION_TARGET_FINGERPRINT",
    "XZS_NEON_TEST_TARGET_FINGERPRINT", "XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS",
    "NEON_API_KEY", "NEON_PROJECT_ID", "NEON_SOURCE_BRANCH_NAME",
    "NEON_TARGET_BRANCH_NAME", "NEON_EXPECTED_TEST_ENDPOINT_ID",
    "NEON_TEST_DIRECT_URL", "NEON_TEST_FLY_BASE_URL", "NEON_TEST_PRESERVE_PREFIX",
    "XZS_BACKUP_ROOT", "XZS_BACKUP_EXPECTED_MOUNT_TARGET",
    "XZS_BACKUP_EXPECTED_FSTYPE", "XZS_POSTGRES_OPS_LOCK_FILE",
}}
seen = set()
for number, raw in enumerate(Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(), 1):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    match = re.fullmatch(r"\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.+)\\s*", raw)
    if not match or match.group(1) in seen or re.search(r"<[^>]+>", match.group(2)):
        raise SystemExit("dedicated environment validation failed")
    seen.add(match.group(1))
if not required.issubset(seen):
    raise SystemExit("dedicated environment validation failed")
PY_ENV

for command in docker findmnt flock realpath sha256sum; do
  command -v "$command" >/dev/null
done
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/xzs-neon-dr-refresh-manual.service /etc/systemd/system/xzs-neon-dr-refresh.service /etc/systemd/system/xzs-neon-dr-refresh.timer >/dev/null

timer_state="$(systemctl is-enabled xzs-neon-dr-refresh.timer 2>/dev/null || true)"
test "$timer_state" = "disabled"
printf 'INSTALL=ok\n'
printf 'OFFLINE_PREFLIGHT=ok\n'
printf 'TIMER_STATE=disabled\n'

verify_success_states() {{
  python3 - /var/lib/xzs-neon-dr-refresh/last-success.json /var/lib/xzs-neon-dr-refresh/test-reset-state.json <<'PY_STATE'
import json
from pathlib import Path
import re
import sys

production = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
test = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if production.get("schema_version") != 1 or production.get("result") != "passed":
    raise SystemExit("production refresh success state is invalid")
backup_time = production.get("source_backup_time_utc")
checksum = production.get("source_sha256")
if not isinstance(backup_time, str) or not re.fullmatch(r"[0-9]{{8}}T[0-9]{{6}}Z", backup_time):
    raise SystemExit("production refresh success state is invalid")
if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{{64}}", checksum):
    raise SystemExit("production refresh success state is invalid")
if test.get("schema_version") != 1 or test.get("status") != "success":
    raise SystemExit("test reset success state is invalid")
if test.get("generation") != f"{{backup_time}}:{{checksum}}":
    raise SystemExit("production refresh and test reset generations do not match")
PY_STATE
}}

enable_refresh_timer() {{
  timer_enable_pending=1
  if ! systemctl enable --now xzs-neon-dr-refresh.timer >/dev/null; then
    printf 'TIMER_ENABLE_FAIL=enable_or_start\n' >&2
    return 1
  fi
  if [ "$(systemctl is-enabled xzs-neon-dr-refresh.timer 2>/dev/null || true)" != "enabled" ]; then
    printf 'TIMER_ENABLE_FAIL=not_enabled\n' >&2
    return 1
  fi
  if ! systemctl is-active --quiet xzs-neon-dr-refresh.timer; then
    printf 'TIMER_ENABLE_FAIL=not_active\n' >&2
    return 1
  fi
  printf 'TIMER_STATE=enabled\n'
  timer_enable_pending=0
}}

if [ "$RUN_ONCE" = "1" ]; then
  systemctl reset-failed xzs-neon-dr-refresh-manual.service >/dev/null 2>&1 || true
  systemctl start xzs-neon-dr-refresh-manual.service
  verify_success_states
  test "$(systemctl is-enabled xzs-neon-dr-refresh.timer 2>/dev/null || true)" = "disabled"
  printf 'MANUAL_RUN=ok\n'
  printf 'TIMER_STATE=disabled\n'
fi

if [ "$ENABLE_TIMER" = "1" ]; then
  verify_success_states
  enable_refresh_timer
fi
'''

    sudo_marker = "XZS_SUDO_STDIN_" + secrets.token_hex(16)
    sudo_wrapper = 'while IFS= read -r line; do [ "$line" = "$1" ] && break; done; exec bash -s'
    sudo_command = "sudo -S -k -p '' bash -c " + shlex.quote(sudo_wrapper) + " bash " + shlex.quote(sudo_marker)
    try:
        stdin, stdout, stderr = client.exec_command(sudo_command)
        stdin.write(password + "\n")
        stdin.write(sudo_marker + "\n")
        stdin.write(script)
        stdin.flush()
        stdin.channel.shutdown_write()
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        rc = stdout.channel.recv_exit_status()
    finally:
        cleanup_sftp = client.open_sftp()
        try:
            with contextlib.suppress(OSError):
                cleanup_sftp.remove(remote_env)
            for name in ASSET_NAMES:
                with contextlib.suppress(OSError):
                    cleanup_sftp.remove(f"{remote_stage}/{name}")
            with contextlib.suppress(OSError):
                cleanup_sftp.rmdir(remote_stage)
        finally:
            cleanup_sftp.close()
    print(out, end="")
    if err:
        print(err, end="", file=sys.stderr)
    if rc:
        raise SystemExit(rc)
finally:
    password = None
    if client is not None:
        client.close()
    cloudflared.terminate()
    try:
        cloudflared.wait(timeout=5)
    except subprocess.TimeoutExpired:
        cloudflared.kill()
'@

try {
  Set-Content -LiteralPath $tempScript -Value $pythonSource -Encoding UTF8
  $env:NEON_REFRESH_LOCAL_ENV = (Resolve-Path -LiteralPath $resolvedRefreshEnv).Path
  $env:NEON_REFRESH_LOCAL_OPS = (Resolve-Path -LiteralPath $resolvedOps).Path
  $env:NEON_REFRESH_ROOT_ENV = (Resolve-Path -LiteralPath $resolvedRootEnv).Path
  $env:NEON_REFRESH_REMOTE_APP_DIR = $RemoteAppDir
  $env:NEON_REFRESH_HOSTNAME = $Hostname
  $env:NEON_REFRESH_USER = $User
  $env:NEON_REFRESH_RUN_ONCE = if ($RunOnce) { "1" } else { "0" }
  $env:NEON_REFRESH_ENABLE_TIMER = if ($EnableTimer) { "1" } else { "0" }
  & $python.Source $tempScript
  if ($LASTEXITCODE -ne 0) {
    throw "Neon refresh deployment failed with exit code $LASTEXITCODE."
  }
} finally {
  Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_LOCAL_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_LOCAL_OPS -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_ROOT_ENV -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_REMOTE_APP_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_HOSTNAME -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_USER -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_RUN_ONCE -ErrorAction SilentlyContinue
  Remove-Item Env:\NEON_REFRESH_ENABLE_TIMER -ErrorAction SilentlyContinue
}
