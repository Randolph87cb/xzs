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
