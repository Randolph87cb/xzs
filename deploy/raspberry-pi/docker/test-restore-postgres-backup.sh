#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

if [[ $# -ne 1 ]]; then
  die "Usage: $0 /path/to/xzs-*.dump"
fi

require_command docker
require_command sha256sum
require_command realpath
require_command mktemp

DUMP_FILE="$(realpath "$1")"
verify_dump_archive "$DUMP_FILE"
verify_checksum_sidecar "$DUMP_FILE"

NAS_PROJECT_ROOT="${XZS_BACKUP_ROOT:-/mnt/zspace-xzs-backup/gesp-csp-quiz}"
REPORT_DIR="${NAS_PROJECT_ROOT}/restore-tests"
mkdir -p "$REPORT_DIR"
NAS_PROJECT_ROOT="$(realpath "$NAS_PROJECT_ROOT")"
REPORT_DIR="$(realpath "$REPORT_DIR")"
[[ "$NAS_PROJECT_ROOT" == /mnt/zspace-xzs-backup/* && "$REPORT_DIR" == "${NAS_PROJECT_ROOT}/restore-tests" ]] ||
  die "Restore report directory must be under the NAS project backup root."

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
container_name="xzs-postgres-restore-test-${run_id,,}"
volume_name="${container_name}-data"
database_name="xzs_restore_test"
test_password="$(head -c 48 /dev/urandom | base64 | tr -d '\n')"
started_epoch="$(date +%s)"
restore_list=""

cleanup() {
  [[ -z "$restore_list" ]] || rm -f -- "$restore_list"
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  docker volume rm "$volume_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$volume_name" >/dev/null
docker run --detach --name "$container_name" \
  --env POSTGRES_DB="$database_name" \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD="$test_password" \
  --volume "${volume_name}:/var/lib/postgresql" \
  "$POSTGRES_IMAGE" >/dev/null

ready=0
for _ in {1..60}; do
  if docker exec "$container_name" pg_isready --username postgres --dbname "$database_name" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
(( ready == 1 )) || die "Isolated PostgreSQL restore container did not become ready."

restore_list="$(mktemp "${TMPDIR:-/tmp}/xzs-restore-test-list.XXXXXX")"
create_standard_postgres_restore_list "$DUMP_FILE" "$restore_list"
docker cp "$DUMP_FILE" "${container_name}:/tmp/restore.dump"
docker cp "$restore_list" "${container_name}:/tmp/restore.list"
docker exec "$container_name" pg_restore \
  --username postgres \
  --dbname "$database_name" \
  --use-list=/tmp/restore.list \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  /tmp/restore.dump >/dev/null

test_query() {
  docker exec "$container_name" psql \
    --username postgres \
    --dbname "$database_name" \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --command "$1" |
    tr -d '\r' |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

flyway_version="$(test_query "SELECT COALESCE((SELECT version FROM public.flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1), 'none');")"
tables=(
  t_user
  t_question
  t_exam_paper
  t_exam_paper_answer
  t_exam_paper_question_customer_answer
  t_task_exam_customer_answer
  t_question_correction_record
  t_question_correction_review_record
)

row_json=""
for table in "${tables[@]}"; do
  count="$(test_query "SELECT count(*) FROM public.\"${table}\";")"
  [[ "$count" =~ ^[0-9]+$ ]] || die "Invalid row count returned for $table."
  [[ -n "$row_json" ]] && row_json+=","
  row_json+="\"${table}\":${count}"
done

orphan_answers="$(test_query '
  SELECT count(*)
  FROM public.t_exam_paper_question_customer_answer a
  LEFT JOIN public.t_exam_paper_answer p ON p.id = a.exam_paper_answer_id
  WHERE a.exam_paper_answer_id IS NOT NULL AND p.id IS NULL;
')"
orphan_corrections="$(test_query '
  SELECT count(*)
  FROM public.t_question_correction_record c
  LEFT JOIN public.t_user u ON u.id = c.user_id
  LEFT JOIN public.t_question q ON q.id = c.question_id
  LEFT JOIN public.t_exam_paper_question_customer_answer a ON a.id = c.customer_answer_id
  WHERE u.id IS NULL OR q.id IS NULL OR a.id IS NULL;
')"
[[ "$orphan_answers" == "0" ]] || die "Restore validation found orphan answer rows: $orphan_answers"
[[ "$orphan_corrections" == "0" ]] || die "Restore validation found orphan correction rows: $orphan_corrections"

finished_epoch="$(date +%s)"
duration_seconds="$((finished_epoch - started_epoch))"
checksum="$(sha256sum "$DUMP_FILE" | awk '{print $1}')"
report_name="restore-test-${run_id}.json"
report_partial="${REPORT_DIR}/${report_name}.partial"
{
  printf '{\n'
  printf '  "completed_at_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "backup": "%s",\n' "$(json_escape "$DUMP_FILE")"
  printf '  "sha256": "%s",\n' "$checksum"
  printf '  "postgres_image": "%s",\n' "$(json_escape "$POSTGRES_IMAGE")"
  printf '  "flyway_version": "%s",\n' "$(json_escape "$flyway_version")"
  printf '  "duration_seconds": %s,\n' "$duration_seconds"
  printf '  "orphan_answer_rows": %s,\n' "$orphan_answers"
  printf '  "orphan_correction_rows": %s,\n' "$orphan_corrections"
  printf '  "table_rows": {%s},\n' "$row_json"
  printf '  "result": "passed"\n'
  printf '}\n'
} >"$report_partial"
mv -- "$report_partial" "${REPORT_DIR}/${report_name}"

printf 'Isolated restore test passed; report: %s\n' "${REPORT_DIR}/${report_name}"
