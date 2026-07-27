#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

IMAGE=""
DATA_DIR=""
CONFIRM=""
DRY_RUN=false
ALLOW_ROOT_USB_SSD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) [[ $# -ge 2 ]] || die "--image requires a value"; IMAGE="$2"; shift 2 ;;
    --data-dir) [[ $# -ge 2 ]] || die "--data-dir requires a value"; DATA_DIR="$2"; shift 2 ;;
    --confirm) [[ $# -ge 2 ]] || die "--confirm requires a value"; CONFIRM="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --allow-root-usb-ssd) ALLOW_ROOT_USB_SSD=true; shift ;;
    *) die "Usage: $0 --image fixed-image --data-dir /opt/usb-ssd/path --confirm CUTOVER_NEON_TO_LOCAL [--allow-root-usb-ssd] [--dry-run]" ;;
  esac
done

[[ -n "$IMAGE" && -n "$DATA_DIR" ]] || die "--image and --data-dir are required."
[[ "$CONFIRM" == "CUTOVER_NEON_TO_LOCAL" ]] || die "--confirm CUTOVER_NEON_TO_LOCAL is required."
[[ "$IMAGE" != *$'\n'* && "$IMAGE" != *' '* ]] || die "Invalid application image."
image_leaf="${IMAGE##*/}"
[[ "$IMAGE" == *@sha256:* || "$image_leaf" == *:* ]] ||
  die "--image must contain an immutable digest or an explicit non-latest tag."
[[ "${image_leaf##*:}" != "latest" ]] || die "The latest tag is forbidden."

require_command docker
require_command python3
require_command curl
require_command sha256sum
require_command realpath
require_command findmnt
require_command systemctl
require_file "$ENV_FILE"
require_file "$COMPOSE_FILE"
for required_asset in \
  "${SCRIPT_DIR}/restore-postgres-backup.sh" \
  "${SCRIPT_DIR}/backup-postgres-to-zspace.sh" \
  "${SCRIPT_DIR}/test-latest-postgres-backup.sh" \
  "${SCRIPT_DIR}/xzs-postgres-backup.service" \
  "${SCRIPT_DIR}/xzs-postgres-backup.timer" \
  "${SCRIPT_DIR}/xzs-postgres-restore-test.service" \
  "${SCRIPT_DIR}/xzs-postgres-restore-test.timer"; do
  require_file "$required_asset"
done

[[ -d "$DATA_DIR" ]] || die "The prepared USB SSD data directory must already exist: $DATA_DIR"
DATA_DIR="$(realpath "$DATA_DIR")"
[[ "$DATA_DIR" == /opt/* ]] || die "--data-dir must be below /opt."
mount_target="$(findmnt -n -o TARGET -T "$DATA_DIR")"
mount_source="$(findmnt -n -o SOURCE -T "$DATA_DIR")"
[[ -n "$mount_target" && -n "$mount_source" ]] || die "Could not resolve the data filesystem."
if [[ "$mount_target" == "/" ]]; then
  "$ALLOW_ROOT_USB_SSD" ||
    die "Root-filesystem storage requires explicit --allow-root-usb-ssd."
  [[ "$mount_source" == /dev/sd* || "$mount_source" == /dev/nvme* ]] ||
    die "--allow-root-usb-ssd only accepts /dev/sd* or /dev/nvme* root devices; SD/MMC roots remain forbidden."
fi
POSTGRES_DATA_DIR="${DATA_DIR}/postgres"
BACKUP_STAGING_DIR="${DATA_DIR}/backup-staging"
NAS_ROOT="${XZS_BACKUP_ROOT:-/mnt/zspace-xzs-backup/gesp-csp-quiz}"
NAS_MOUNT="/mnt/zspace-xzs-backup"
nas_mount_target="$(findmnt -n -o TARGET -T "$NAS_MOUNT")"
[[ -n "$nas_mount_target" && "$nas_mount_target" != "/" ]] ||
  die "NAS backup mount is unavailable: $NAS_MOUNT"
[[ -d "$NAS_ROOT" && -w "$NAS_ROOT" ]] || die "NAS project root must already exist and be writable: $NAS_ROOT"
if [[ -e "$POSTGRES_DATA_DIR" ]] &&
  [[ -n "$(find "$POSTGRES_DATA_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  die "PostgreSQL target directory is not empty: $POSTGRES_DATA_DIR"
fi
docker container inspect xzs-app >/dev/null 2>&1 || die "The current xzs-app container does not exist."
[[ "$(docker inspect --format '{{.State.Running}}' xzs-app)" == "true" ]] ||
  die "The current xzs-app container is not running."
old_image="$(docker inspect --format '{{.Config.Image}}' xzs-app)"
[[ -n "$old_image" ]] || die "Could not determine the current xzs-app image."
! docker container inspect xzs-app-neon-rollback >/dev/null 2>&1 ||
  die "Rollback container name already exists: xzs-app-neon-rollback"
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "Pinned application image is not present locally: $IMAGE"
docker image inspect "$POSTGRES_IMAGE" >/dev/null 2>&1 || die "PostgreSQL image is not present locally: $POSTGRES_IMAGE"

HEALTH_URL="${XZS_HEALTH_URL:-http://127.0.0.1:8000/api/health}"
curl --fail --silent --show-error --max-time 15 "$HEALTH_URL" >/dev/null ||
  die "Current application health check failed."

validate_old_env() {
  python3 - "$ENV_FILE" <<'PY'
import shlex, sys, urllib.parse

values = {}
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    value = value.strip()
    if value[:1] in ("'", '"'):
        parsed = shlex.split(value, comments=False, posix=True)
        value = parsed[0] if parsed else ""
    values[key.strip()] = value
secret = values.get("XZS_AI_CONFIG_SECRET", "")
url = values.get("SPRING_DATASOURCE_URL", "")
if not secret or "\n" in secret or "\r" in secret:
    raise SystemExit("XZS_AI_CONFIG_SECRET is missing or invalid")
if url.startswith("jdbc:"):
    url = url[5:]
parts = urllib.parse.urlsplit(url)
if parts.scheme not in ("postgres", "postgresql") or not all(
    (parts.hostname, parts.username, parts.password, parts.path.lstrip("/"))
):
    raise SystemExit("SPRING_DATASOURCE_URL is not a complete PostgreSQL URL")
PY
}
validate_old_env

if "$DRY_RUN"; then
  printf 'Read-only cutover preflight passed. No files, containers, databases, or services were changed.\n'
  exit 0
fi

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
CUTOVER_BACKUP_DIR="${DATA_DIR}/cutover-backups"
mkdir -p "$POSTGRES_DATA_DIR" "$BACKUP_STAGING_DIR" "$CUTOVER_BACKUP_DIR" "$NAS_ROOT"/{incoming,manual}
chown -R 999:999 "$POSTGRES_DATA_DIR"
PG_ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/xzs-neon-pg.XXXXXX")"
OLD_ENV_BACKUP="${CUTOVER_BACKUP_DIR}/env-neon-${timestamp}.backup"
ROLLBACK_ENV_FILE="${CUTOVER_BACKUP_DIR}/rollback-container-${timestamp}.env"
NEW_ENV_FILE="$(mktemp "${APP_DIR}/.env.local-postgres.XXXXXX")"
cp -- "$ENV_FILE" "$OLD_ENV_BACKUP"
touch "$ROLLBACK_ENV_FILE"
chmod 0600 "$PG_ENV_FILE" "$OLD_ENV_BACKUP" "$ROLLBACK_ENV_FILE" "$NEW_ENV_FILE"

python3 - "$ENV_FILE" "$PG_ENV_FILE" "$NEW_ENV_FILE" "$ROLLBACK_ENV_FILE" "$IMAGE" \
  "$POSTGRES_DATA_DIR" "$BACKUP_STAGING_DIR" "$NAS_ROOT" "$POSTGRES_IMAGE" <<'PY'
import os, re, secrets, shlex, sys, urllib.parse

old, pg_file, new_file, rollback_file, image, data_dir, staging, nas_root, postgres_image = sys.argv[1:]
values = {}
for raw in open(old, encoding="utf-8"):
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    key, value = line.split("=", 1)
    value = value.strip()
    if value[:1] in ("'", '"'):
        parsed = shlex.split(value, comments=False, posix=True)
        value = parsed[0] if parsed else ""
    values[key.strip()] = value
url = values["SPRING_DATASOURCE_URL"]
if url.startswith("jdbc:"):
    url = url[5:]
p = urllib.parse.urlsplit(url)
query = urllib.parse.parse_qs(p.query, keep_blank_values=True)
pg = {
    "PGHOST": p.hostname,
    "PGPORT": str(p.port or 5432),
    "PGUSER": urllib.parse.unquote(p.username),
    "PGPASSWORD": urllib.parse.unquote(p.password),
    "PGDATABASE": urllib.parse.unquote(p.path.lstrip("/")),
    "PGSSLMODE": query.get("sslmode", ["require"])[-1],
}
for query_key, env_key in (
    ("channel_binding", "PGCHANNELBINDING"),
    ("options", "PGOPTIONS"),
    ("sslrootcert", "PGSSLROOTCERT"),
):
    if query_key in query:
        pg[env_key] = query[query_key][-1]
with open(pg_file, "w", encoding="utf-8") as f:
    for key, value in pg.items():
        if value is None or "\n" in value or "\r" in value:
            raise SystemExit("Invalid PostgreSQL connection field")
        f.write(f"{key}={value}\n")
os.chmod(pg_file, 0o600)

rollback_values = {
    "SPRING_PROFILES_ACTIVE": values.get("SPRING_PROFILES_ACTIVE", "prod"),
    "SERVER_PORT": values.get("SERVER_PORT", "8000"),
    "XZS_LOG_PATH": values.get("XZS_LOG_PATH", "/usr/log/xzs/"),
    "TZ": values.get("TZ", "Asia/Shanghai"),
    "JAVA_TOOL_OPTIONS": values.get("JAVA_TOOL_OPTIONS", "-Xms128m -Xmx512m -XX:+UseSerialGC"),
    "SERVER_UNDERTOW_IO_THREADS": values.get("SERVER_UNDERTOW_IO_THREADS", "2"),
    "SERVER_UNDERTOW_WORKER_THREADS": values.get("SERVER_UNDERTOW_WORKER_THREADS", "16"),
    "SERVER_UNDERTOW_BUFFER_SIZE": values.get("SERVER_UNDERTOW_BUFFER_SIZE", "512"),
    "SERVER_UNDERTOW_DIRECT_BUFFERS": values.get("SERVER_UNDERTOW_DIRECT_BUFFERS", "false"),
    "SPRING_DATASOURCE_URL": values["SPRING_DATASOURCE_URL"],
    "SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE": values.get(
        "SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE", "3"
    ),
    "SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE": values.get(
        "SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE", "1"
    ),
    "SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT": values.get(
        "SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT", "30000"
    ),
    "XZS_AI_CONFIG_SECRET": values["XZS_AI_CONFIG_SECRET"],
}
with open(rollback_file, "w", encoding="utf-8") as f:
    for key, value in rollback_values.items():
        if "\n" in value or "\r" in value:
            raise SystemExit("Invalid rollback container environment field")
        f.write(f"{key}={value}\n")
os.chmod(rollback_file, 0o600)

def dotenv(value):
    if re.fullmatch(r"[A-Za-z0-9._/@:+-]+", value):
        return value
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

new_values = {
    "XZS_IMAGE": image,
    "XZS_POSTGRES_IMAGE": postgres_image,
    "XZS_POSTGRES_DB": "xzs",
    "XZS_POSTGRES_USER": "xzs",
    "XZS_POSTGRES_PASSWORD": secrets.token_hex(32),
    "XZS_POSTGRES_DATA_DIR": data_dir,
    "XZS_BACKUP_STAGING_DIR": staging,
    "XZS_BACKUP_ROOT": nas_root,
    "XZS_AI_CONFIG_SECRET": values["XZS_AI_CONFIG_SECRET"],
}
for key in (
    "XZS_HOST_BIND", "XZS_HOST_PORT", "XZS_LOG_DIR", "JAVA_TOOL_OPTIONS",
    "SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE",
    "SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE",
    "SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT",
):
    if values.get(key):
        new_values[key] = values[key]
with open(new_file, "w", encoding="utf-8") as f:
    for key, value in new_values.items():
        f.write(f"{key}={dotenv(value)}\n")
os.chmod(new_file, 0o600)
PY

cutover_started=false
timers_enabled=false
rollback() {
  status=$?
  rm -f -- "${PG_ENV_FILE:-}" "${NEW_ENV_FILE:-}"
  if (( status != 0 )) && "$cutover_started"; then
    printf 'ERROR: cutover failed; restoring the previous Neon environment and container.\n' >&2
    if "$timers_enabled"; then
      systemctl disable --now xzs-postgres-backup.timer xzs-postgres-restore-test.timer >/dev/null 2>&1 || true
    fi
    docker rm -f xzs-postgres >/dev/null 2>&1 || true
    cp -- "$OLD_ENV_BACKUP" "$ENV_FILE" || true
    if docker container inspect xzs-app-neon-rollback >/dev/null 2>&1; then
      docker rm -f xzs-app >/dev/null 2>&1 || true
      docker start xzs-app-neon-rollback >/dev/null 2>&1 || true
    elif docker container inspect xzs-app >/dev/null 2>&1; then
      docker start xzs-app >/dev/null 2>&1 || true
    else
      docker create \
        --name xzs-app-neon-rollback \
        --restart=no \
        --env-file "$ROLLBACK_ENV_FILE" \
        --publish 8000:8000 \
        --volume "${APP_DIR}/log:/usr/log/xzs/" \
        "$old_image" >/dev/null 2>&1 || true
      docker start xzs-app-neon-rollback >/dev/null 2>&1 || true
    fi
  fi
  exit "$status"
}
trap rollback EXIT

cutover_started=true
docker stop xzs-app >/dev/null
docker rm xzs-app >/dev/null
docker create \
  --name xzs-app-neon-rollback \
  --restart=no \
  --env-file "$ROLLBACK_ENV_FILE" \
  --publish 8000:8000 \
  --volume "${APP_DIR}/log:/usr/log/xzs/" \
  "$old_image" >/dev/null

base="xzs-${timestamp}-neon-final"
dump_file="${BACKUP_STAGING_DIR}/${base}.dump"
checksum_file="${dump_file}.sha256"
manifest_file="${dump_file}.manifest.json"
partial_dump="${dump_file}.partial"
docker run --rm --env-file "$PG_ENV_FILE" "$POSTGRES_IMAGE" \
  pg_dump --format=custom --compress=6 --no-owner --no-privileges >"$partial_dump"
[[ -s "$partial_dump" ]] || die "Final Neon dump is empty."
mv -- "$partial_dump" "$dump_file"
verify_dump_archive "$dump_file"
restore_list="${dump_file}.restore-list"
create_standard_postgres_restore_list "$dump_file" "$restore_list"
checksum="$(sha256sum "$dump_file" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "$(basename "$dump_file")" >"$checksum_file"
source_version="$(docker run --rm --env-file "$PG_ENV_FILE" "$POSTGRES_IMAGE" \
  psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --command 'SHOW server_version;' | tr -d '\r')"
size_bytes="$(stat --format '%s' "$dump_file")"
{
  printf '{\n'
  printf '  "backup_time_utc": "%s",\n' "$timestamp"
  printf '  "source": "neon-production-final",\n'
  printf '  "postgres_version": "%s",\n' "$(json_escape "$source_version")"
  printf '  "application_image": "%s",\n' "$(json_escape "$IMAGE")"
  printf '  "archive": "%s",\n' "$(basename "$dump_file")"
  printf '  "size_bytes": %s,\n' "$size_bytes"
  printf '  "sha256": "%s"\n' "$checksum"
  printf '}\n'
} >"$manifest_file"

incoming="${NAS_ROOT}/incoming"
manual="${NAS_ROOT}/manual"
for source_file in "$dump_file" "$checksum_file" "$manifest_file"; do
  cp -- "$source_file" "${incoming}/$(basename "$source_file").partial"
done
[[ "$(sha256sum "${incoming}/$(basename "$dump_file").partial" | awk '{print $1}')" == "$checksum" ]] ||
  die "Final Neon NAS copy checksum verification failed."
for source_file in "$manifest_file" "$checksum_file" "$dump_file"; do
  mv -- "${incoming}/$(basename "$source_file").partial" "${manual}/$(basename "$source_file")"
done

mv -- "$NEW_ENV_FILE" "$ENV_FILE"
chmod 0600 "$ENV_FILE"
export XZS_APP_DIR="$APP_DIR"
export XZS_COMPOSE_FILE="$COMPOSE_FILE"
export XZS_ENV_FILE="$ENV_FILE"
export XZS_BACKUP_STAGING_DIR="$BACKUP_STAGING_DIR"
export XZS_BACKUP_ROOT="$NAS_ROOT"
compose up -d postgres
for _ in {1..36}; do
  if compose ps --status running postgres | grep -q postgres &&
    postgres_exec pg_isready -U xzs -d xzs >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
postgres_exec pg_isready -U xzs -d xzs >/dev/null 2>&1 || die "Local PostgreSQL did not become healthy."

rescue_file="${BACKUP_STAGING_DIR}/${base}-rescue.dump"
cp -- "$dump_file" "$rescue_file"
sleep 1
touch "$rescue_file"
printf '%s  %s\n' "$(sha256sum "$rescue_file" | awk '{print $1}')" "$(basename "$rescue_file")" \
  >"${rescue_file}.sha256"
XZS_RESTORE_CONFIRM="RESTORE:xzs" \
XZS_ALLOW_PRODUCTION_RESTORE="YES_I_HAVE_STOPPED_WRITES_AND_TAKEN_RESCUE_BACKUP" \
XZS_RESCUE_BACKUP_FILE="$rescue_file" \
  "${SCRIPT_DIR}/restore-postgres-backup.sh" --backup "$dump_file" --target-db xzs
rm -f -- "$restore_list"

compose up -d app
for _ in {1..36}; do
  curl --fail --silent --max-time 10 "$HEALTH_URL" >/dev/null 2>&1 && break
  sleep 5
done
curl --fail --silent --show-error --max-time 15 "$HEALTH_URL" >/dev/null ||
  die "Local PostgreSQL application health check failed."

"${SCRIPT_DIR}/backup-postgres-to-zspace.sh"
"${SCRIPT_DIR}/test-latest-postgres-backup.sh"

install -m 0644 "${SCRIPT_DIR}/xzs-postgres-backup.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/xzs-postgres-backup.timer" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/xzs-postgres-restore-test.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/xzs-postgres-restore-test.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now xzs-neon-dr-refresh.timer >/dev/null 2>&1 || true
timers_enabled=true
systemctl enable --now xzs-postgres-backup.timer xzs-postgres-restore-test.timer

cutover_started=false
trap - EXIT
rm -f -- "$PG_ENV_FILE"
printf 'Neon-to-local PostgreSQL cutover completed successfully. Rollback container: xzs-app-neon-rollback; previous environment backup: %s; rollback container environment: %s\n' \
  "$OLD_ENV_BACKUP" "$ROLLBACK_ENV_FILE"
