#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"
# shellcheck source=shadow-compose-common.sh
source "${SCRIPT_DIR}/shadow-compose-common.sh"

if [[ $# -ne 2 || "$1" != "--backup" ]]; then
  die "Usage: $0 --backup /path/to/verified/xzs-*.dump"
fi

require_command docker
require_command curl
require_command sha256sum
require_command realpath
require_command mktemp
assert_shadow_configuration

DUMP_FILE="$(realpath "$2")"
verify_dump_archive "$DUMP_FILE"
verify_checksum_sidecar "$DUMP_FILE"
MANIFEST_FILE="${DUMP_FILE}.manifest.json"
require_file "$MANIFEST_FILE"
checksum="$(sha256sum "$DUMP_FILE" | awk '{print $1}')"
grep -Fq "\"sha256\": \"${checksum}\"" "$MANIFEST_FILE" ||
  die "Backup manifest checksum does not match the selected archive."

restore_list="$(mktemp "${TMPDIR:-/tmp}/xzs-shadow-restore-list.XXXXXX")"
container_restore_list="/tmp/xzs-shadow-restore-list-$$"
cleanup_restore_list() {
  rm -f -- "$restore_list"
  shadow_postgres_exec rm -f -- "$container_restore_list" >/dev/null 2>&1 || true
}
trap cleanup_restore_list EXIT
create_standard_postgres_restore_list "$DUMP_FILE" "$restore_list"

# Never restore while a previous shadow app can write to the shadow database.
shadow_compose stop app >/dev/null 2>&1 || true
shadow_compose up -d postgres

ready=0
for _ in {1..60}; do
  if shadow_postgres_exec pg_isready \
    --username "$SHADOW_POSTGRES_USER" \
    --dbname postgres >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
(( ready == 1 )) || die "Shadow PostgreSQL did not become ready."

shadow_postgres_exec dropdb \
  --username "$SHADOW_POSTGRES_USER" \
  --if-exists \
  --force \
  "$SHADOW_POSTGRES_DB"
shadow_postgres_exec createdb \
  --username "$SHADOW_POSTGRES_USER" \
  --owner "$SHADOW_POSTGRES_USER" \
  "$SHADOW_POSTGRES_DB"
shadow_compose cp "$restore_list" "postgres:${container_restore_list}"
shadow_postgres_exec pg_restore \
  --username "$SHADOW_POSTGRES_USER" \
  --dbname "$SHADOW_POSTGRES_DB" \
  --use-list="$container_restore_list" \
  --no-owner \
  --no-privileges \
  --exit-on-error <"$DUMP_FILE"
shadow_postgres_exec rm -f -- "$container_restore_list"

shadow_postgres_exec psql \
  --username "$SHADOW_POSTGRES_USER" \
  --dbname "$SHADOW_POSTGRES_DB" \
  --no-psqlrc \
  --set ON_ERROR_STOP=1 \
  --tuples-only \
  --command 'SELECT version FROM public.flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1;' \
  >/dev/null

# Starting the current application image now exercises its JDBC driver and
# Flyway validation/migration against the restored PostgreSQL 18 shadow data.
shadow_compose up -d app

healthy=0
for _ in {1..90}; do
  if curl --fail --silent --show-error --max-time 5 \
    http://127.0.0.1:18000/api/health >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 2
done
(( healthy == 1 )) ||
  die "Shadow app did not pass http://127.0.0.1:18000/api/health. Inspect xzs-app-shadow logs without printing secrets."

printf 'Shadow restore and application health check passed at http://127.0.0.1:18000\n'
printf 'Shadow Compose project: %s\n' "$SHADOW_PROJECT_NAME"
printf 'Selected backup SHA-256: %s\n' "$checksum"
