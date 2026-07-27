#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

LABEL=""
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == "--label" ]] || die "Usage: $0 [--label manual-reason]"
  [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] ||
    die "Backup label must contain only letters, digits, dot, underscore, or hyphen (max 64)."
  LABEL="$2"
fi

require_command docker
require_command flock
require_command sha256sum
require_command stat
require_command realpath

STAGING_DIR="${XZS_BACKUP_STAGING_DIR:?set XZS_BACKUP_STAGING_DIR to the USB SSD staging directory}"
NAS_PROJECT_ROOT="${XZS_BACKUP_ROOT:-/mnt/zspace-xzs-backup/gesp-csp-quiz}"
MAX_USE_PERCENT="${XZS_BACKUP_STAGING_MAX_USE_PERCENT:-80}"
[[ "$MAX_USE_PERCENT" =~ ^[1-9][0-9]?$ ]] || die "XZS_BACKUP_STAGING_MAX_USE_PERCENT must be 1-99."

mkdir -p "$STAGING_DIR" "$NAS_PROJECT_ROOT"/{incoming,hourly,daily,weekly,monthly,manual,restore-tests}
STAGING_DIR="$(realpath "$STAGING_DIR")"
NAS_PROJECT_ROOT="$(realpath "$NAS_PROJECT_ROOT")"
[[ "$STAGING_DIR" != "$NAS_PROJECT_ROOT"* ]] || die "Backup staging must not be inside the NAS project root."
[[ "$NAS_PROJECT_ROOT" == /mnt/zspace-xzs-backup/* ]] ||
  die "XZS_BACKUP_ROOT must be a project directory below /mnt/zspace-xzs-backup."

LOCK_FILE="${STAGING_DIR}/.xzs-postgres-backup.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || die "Another PostgreSQL backup is already running."

used_percent="$(df -P "$STAGING_DIR" | awk 'NR==2 {gsub("%","",$5); print $5}')"
[[ "$used_percent" =~ ^[0-9]+$ ]] || die "Could not determine staging filesystem usage."
(( used_percent < MAX_USE_PERCENT )) ||
  die "Staging filesystem usage is ${used_percent}%, threshold is ${MAX_USE_PERCENT}%."

load_postgres_identity
compose ps --status running postgres | grep -q postgres || die "PostgreSQL container is not running."

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
base_name="xzs-${timestamp}"
if [[ -n "$LABEL" ]]; then
  base_name="${base_name}-${LABEL}"
fi
dump_file="${STAGING_DIR}/${base_name}.dump"
checksum_file="${dump_file}.sha256"
manifest_file="${dump_file}.manifest.json"
tmp_dump="${dump_file}.partial"
tmp_manifest="${manifest_file}.partial"
trap 'rm -f -- "${tmp_dump:-}" "${tmp_manifest:-}"' EXIT

postgres_exec pg_dump \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --format custom \
  --compress=6 \
  --no-owner \
  --no-privileges >"$tmp_dump"
[[ -s "$tmp_dump" ]] || die "pg_dump created an empty archive."
mv -- "$tmp_dump" "$dump_file"
verify_dump_archive "$dump_file"

checksum="$(sha256sum "$dump_file" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "$(basename "$dump_file")" >"$checksum_file"
size_bytes="$(stat --format '%s' "$dump_file")"
postgres_version="$(query_scalar 'SHOW server_version;')"
flyway_version="$(query_scalar "SELECT COALESCE((SELECT version FROM public.flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1), 'none');")"
app_image="$(docker inspect --format '{{.Config.Image}}' xzs-app 2>/dev/null || true)"
[[ -n "$app_image" ]] || app_image="unknown"

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

{
  printf '{\n'
  printf '  "backup_time_utc": "%s",\n' "$timestamp"
  printf '  "database": "%s",\n' "$(json_escape "$POSTGRES_DB")"
  printf '  "postgres_version": "%s",\n' "$(json_escape "$postgres_version")"
  printf '  "application_image": "%s",\n' "$(json_escape "$app_image")"
  printf '  "flyway_version": "%s",\n' "$(json_escape "$flyway_version")"
  printf '  "archive": "%s",\n' "$(basename "$dump_file")"
  printf '  "size_bytes": %s,\n' "$size_bytes"
  printf '  "sha256": "%s",\n' "$checksum"
  printf '  "table_rows": {\n'
  for ((i = 0; i < ${#tables[@]}; i++)); do
    table="${tables[$i]}"
    count="$(query_scalar "SELECT count(*) FROM public.\"${table}\";")"
    comma=","
    (( i == ${#tables[@]} - 1 )) && comma=""
    printf '    "%s": %s%s\n' "$table" "$count" "$comma"
  done
  printf '  }\n'
  printf '}\n'
} >"$tmp_manifest"
mv -- "$tmp_manifest" "$manifest_file"

target_class="hourly"
[[ -n "$LABEL" ]] && target_class="manual"
incoming="${NAS_PROJECT_ROOT}/incoming"
target_dir="${NAS_PROJECT_ROOT}/${target_class}"
for source_file in "$dump_file" "$checksum_file" "$manifest_file"; do
  partial="${incoming}/$(basename "$source_file").partial"
  cp -- "$source_file" "$partial"
done
nas_partial_dump="${incoming}/$(basename "$dump_file").partial"
[[ "$(sha256sum "$nas_partial_dump" | awk '{print $1}')" == "$checksum" ]] ||
  die "NAS copy checksum verification failed."

for source_file in "$manifest_file" "$checksum_file" "$dump_file"; do
  mv -- "${incoming}/$(basename "$source_file").partial" "${target_dir}/$(basename "$source_file")"
done

promote_family() {
  local destination="$1"
  local source_file
  for source_file in "$dump_file" "$checksum_file" "$manifest_file"; do
    promoted_partial="${incoming}/$(basename "$source_file").${destination}.partial"
    cp -- "${target_dir}/$(basename "$source_file")" "$promoted_partial"
  done
  for source_file in "$manifest_file" "$checksum_file" "$dump_file"; do
    promoted_partial="${incoming}/$(basename "$source_file").${destination}.partial"
    mv -- "$promoted_partial" "${NAS_PROJECT_ROOT}/${destination}/$(basename "$source_file")"
  done
}

if [[ "$target_class" == "hourly" ]]; then
  [[ "$(date +%H)" == "00" ]] && promote_family daily
  [[ "$(date +%u)" == "7" && "$(date +%H)" == "00" ]] && promote_family weekly
  [[ "$(date +%d)" == "01" && "$(date +%H)" == "00" ]] && promote_family monthly
fi

latest_tmp="${incoming}/latest.json.partial"
{
  printf '{\n'
  printf '  "completed_at_utc": "%s",\n' "$timestamp"
  printf '  "class": "%s",\n' "$target_class"
  printf '  "archive": "%s/%s",\n' "$target_class" "$(basename "$dump_file")"
  printf '  "manifest": "%s/%s",\n' "$target_class" "$(basename "$manifest_file")"
  printf '  "sha256": "%s"\n' "$checksum"
  printf '}\n'
} >"$latest_tmp"
mv -- "$latest_tmp" "${NAS_PROJECT_ROOT}/latest.json"
printf '%s\n' "$timestamp" >"${incoming}/last-success.utc.partial"
mv -- "${incoming}/last-success.utc.partial" "${NAS_PROJECT_ROOT}/last-success.utc"

remove_expired_families() {
  local class="$1"
  local days="$2"
  local directory="${NAS_PROJECT_ROOT}/${class}"
  [[ "$(realpath "$directory")" == "${NAS_PROJECT_ROOT}/"* ]] || die "Unsafe retention directory: $directory"
  while IFS= read -r -d '' old_dump; do
    rm -f -- "$old_dump" "${old_dump}.sha256" "${old_dump}.manifest.json"
  done < <(find "$directory" -mindepth 1 -maxdepth 1 -type f -name 'xzs-*.dump' -mtime "+${days}" -print0)
}

remove_expired_families hourly 6
remove_expired_families daily 29
remove_expired_families weekly 83
remove_expired_families monthly 364

mapfile -d '' -t local_dumps < <(find "$STAGING_DIR" -mindepth 1 -maxdepth 1 -type f -name 'xzs-*.dump' -printf '%T@ %p\0' | sort -zrn)
for ((i = 48; i < ${#local_dumps[@]}; i++)); do
  old_dump="${local_dumps[$i]#* }"
  rm -f -- "$old_dump" "${old_dump}.sha256" "${old_dump}.manifest.json"
done

trap - EXIT
printf 'Verified PostgreSQL backup published: %s/%s\n' "$target_class" "$(basename "$dump_file")"
