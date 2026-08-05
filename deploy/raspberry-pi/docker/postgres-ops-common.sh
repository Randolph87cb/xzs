#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${XZS_APP_DIR:-/opt/apps/gesp-csp-quiz}"
COMPOSE_FILE="${XZS_COMPOSE_FILE:-${APP_DIR}/docker-compose.yml}"
ENV_FILE="${XZS_ENV_FILE:-${APP_DIR}/.env}"
POSTGRES_IMAGE="${XZS_POSTGRES_IMAGE:-postgres:18.4-bookworm}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_file() {
  [[ -r "$1" ]] || die "Required file is not readable: $1"
}

require_root_0600_file() {
  local file="$1"
  local owner_id
  local mode

  require_file "$file"
  [[ ! -L "$file" ]] || die "Secret environment file must not be a symbolic link."
  owner_id="$(stat --format '%u' "$file")"
  mode="$(stat --format '%a' "$file")"
  [[ "$owner_id" == "0" && "$mode" == "600" ]] ||
    die "Secret environment file must be owned by root with mode 0600."
}

acquire_postgres_ops_lock() {
  require_command flock
  require_command readlink
  require_command realpath
  local lock_file="${XZS_POSTGRES_OPS_LOCK_FILE:-/run/lock/xzs-postgres-ops.lock}"
  local lock_dir
  local inherited_fd="${XZS_POSTGRES_OPS_LOCK_FD:-}"
  local resolved_lock_file
  local resolved_inherited_target
  lock_dir="$(dirname "$lock_file")"
  [[ -d "$lock_dir" ]] || die "PostgreSQL operations lock directory does not exist: $lock_dir"

  if [[ -n "$inherited_fd" ]]; then
    [[ "$inherited_fd" =~ ^[0-9]+$ && -e "/proc/$$/fd/${inherited_fd}" ]] ||
      die "Inherited PostgreSQL operations lock descriptor is invalid."
    resolved_lock_file="$(realpath -e "$lock_file")"
    resolved_inherited_target="$(readlink -f "/proc/$$/fd/${inherited_fd}")"
    [[ "$resolved_inherited_target" == "$resolved_lock_file" ]] ||
      die "Inherited PostgreSQL operations lock descriptor points to the wrong file."
    flock -n "$inherited_fd" ||
      die "Another XZS PostgreSQL backup, restore, or Neon refresh operation is already running."
    return
  fi

  exec {XZS_POSTGRES_OPS_LOCK_FD}>"$lock_file"
  flock -n "$XZS_POSTGRES_OPS_LOCK_FD" ||
    die "Another XZS PostgreSQL backup, restore, or Neon refresh operation is already running."
  export XZS_POSTGRES_OPS_LOCK_FD
}

acquire_shared_lock_for_operational_entrypoint() {
  local caller
  caller="$(basename "$0")"
  case "$caller" in
    backup-postgres-to-zspace.sh | \
      restore-postgres-backup.sh | \
      test-restore-postgres-backup.sh | \
      refresh-neon-dr-from-latest.sh | \
      refresh-neon-disaster-recovery.sh)
      acquire_postgres_ops_lock
      ;;
  esac
}

resolve_verified_nas_project_root() {
  local project_root="${XZS_BACKUP_ROOT:-/mnt/zspace-xzs-backup/gesp-csp-quiz}"
  local expected_mount_target="${XZS_BACKUP_EXPECTED_MOUNT_TARGET:-}"
  local expected_fstype="${XZS_BACKUP_EXPECTED_FSTYPE:-cifs}"
  local findmnt_output
  local actual_mount_target
  local actual_fstype
  local extra

  require_command findmnt
  require_command realpath
  [[ "$project_root" == /* ]] || die "Backup project root must be an absolute path."
  [[ "$expected_mount_target" == /* ]] ||
    die "Set XZS_BACKUP_EXPECTED_MOUNT_TARGET to the mount target containing the NAS backup root."
  [[ "$expected_fstype" =~ ^[A-Za-z0-9._+-]+$ ]] ||
    die "XZS_BACKUP_EXPECTED_FSTYPE is invalid."

  project_root="$(realpath -e "$project_root")"
  expected_mount_target="$(realpath -e "$expected_mount_target")"
  if ! findmnt_output="$(
    findmnt --noheadings --raw --target "$project_root" --output TARGET,FSTYPE
  )"; then
    die "Could not identify the filesystem carrying the NAS backup root."
  fi
  read -r actual_mount_target actual_fstype extra <<<"$findmnt_output"
  [[ -n "$actual_mount_target" && -n "$actual_fstype" && -z "${extra:-}" ]] ||
    die "Filesystem identity for the NAS backup root is ambiguous."
  actual_mount_target="$(realpath -e "$actual_mount_target")"
  [[ "$actual_mount_target" != "/" ]] ||
    die "NAS backup root is carried by the root filesystem, not the expected remote mount."
  [[ "$actual_mount_target" == "$expected_mount_target" && "$actual_fstype" == "$expected_fstype" ]] ||
    die "NAS backup root is not carried by the approved mount target and filesystem type."
  [[ "$project_root" == "$actual_mount_target"/* ]] ||
    die "Backup project root must be below the verified NAS mount target."
  printf '%s' "$project_root"
}

compose() {
  docker compose --project-directory "$APP_DIR" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

postgres_exec() {
  compose exec -T postgres "$@"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "$value"
}

read_compose_env_value() {
  local key="$1"
  local value
  value="$(
    compose exec -T postgres sh -eu -c '
      key="$1"
      eval "value=\${$key-}"
      printf "%s" "$value"
    ' sh "$key"
  )"
  [[ -n "$value" ]] || die "Container environment variable is empty: $key"
  printf '%s' "$value"
}

verify_dump_archive() {
  local dump_file="$1"
  require_file "$dump_file"
  [[ -s "$dump_file" ]] || die "Backup archive is empty: $dump_file"
  docker run --rm --volume "${dump_file}:/backup.dump:ro" "$POSTGRES_IMAGE" \
    pg_restore --list /backup.dump >/dev/null
}

create_standard_postgres_restore_list() {
  local dump_file="$1"
  local restore_list="$2"
  local raw_list="${restore_list}.raw.$$"
  local filtered_list="${restore_list}.partial.$$"

  require_file "$dump_file"
  if ! docker run --rm --volume "${dump_file}:/backup.dump:ro" "$POSTGRES_IMAGE" \
    pg_restore --list /backup.dump >"$raw_list"; then
    rm -f -- "$raw_list" "$filtered_list"
    die "Could not read the PostgreSQL archive TOC: $dump_file"
  fi

  if ! awk '
    BEGIN {
      extension_pattern = "^[0-9]+;[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+EXTENSION[[:space:]]+-[[:space:]]+pg_session_jwt([[:space:]]|$)"
      comment_pattern = "^[0-9]+;[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+COMMENT[[:space:]]+-[[:space:]]+EXTENSION[[:space:]]+pg_session_jwt([[:space:]]|$)"
    }
    $0 ~ extension_pattern {
      extension_count++
      print ";" $0
      next
    }
    $0 ~ comment_pattern {
      comment_count++
      print ";" $0
      next
    }
    {
      print
    }
    END {
      if (!((extension_count == 0 && comment_count == 0) ||
            (extension_count == 1 && comment_count == 1))) {
        exit 42
      }
    }
  ' "$raw_list" >"$filtered_list"; then
    rm -f -- "$raw_list" "$filtered_list"
    die "Archive TOC must contain either no pg_session_jwt entries or exactly its EXTENSION and COMMENT entries."
  fi

  mv -- "$filtered_list" "$restore_list"
  rm -f -- "$raw_list"
}

verify_checksum_sidecar() {
  local dump_file="$1"
  local checksum_file="${dump_file}.sha256"
  require_file "$checksum_file"
  (
    cd "$(dirname "$dump_file")"
    sha256sum --check "$(basename "$checksum_file")" >/dev/null
  )
}

query_scalar() {
  local sql="$1"
  postgres_exec psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --command "$sql" |
    tr -d '\r' |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

load_postgres_identity() {
  POSTGRES_USER="$(read_compose_env_value POSTGRES_USER)"
  POSTGRES_DB="$(read_compose_env_value POSTGRES_DB)"
}

acquire_shared_lock_for_operational_entrypoint
