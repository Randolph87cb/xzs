#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

if [[ $# -ne 1 ]]; then
  die "Usage: $0 /path/to/verified/hourly/xzs-*.dump"
fi
[[ "${XZS_NEON_DR_REFRESH_CONFIRM:-}" == "REFRESH_NEON_PRODUCTION" ]] ||
  die "Neon production refresh is destructive. Set XZS_NEON_DR_REFRESH_CONFIRM=REFRESH_NEON_PRODUCTION."
[[ -n "${NEON_DR_DIRECT_URL:-}" ]] ||
  die "Set NEON_DR_DIRECT_URL to the dedicated Neon production direct connection."
[[ -n "${NEON_TEST_DIRECT_URL:-}" ]] ||
  die "Set NEON_TEST_DIRECT_URL to the dedicated Neon test direct connection used by the deny gate."

require_command docker
require_command mktemp
require_command python3
require_command realpath
require_command sha256sum
require_command stat

if [[ -n "${XZS_NEON_DR_SECRET_FILE:-}" ]]; then
  require_root_0600_file "$XZS_NEON_DR_SECRET_FILE"
fi

PRODUCTION_FINGERPRINT="${XZS_NEON_PRODUCTION_TARGET_FINGERPRINT:-}"
TEST_FINGERPRINT="${XZS_NEON_TEST_TARGET_FINGERPRINT:-}"
[[ "$PRODUCTION_FINGERPRINT" =~ ^sha256:[0-9a-f]{64}$ ]] ||
  die "Set XZS_NEON_PRODUCTION_TARGET_FINGERPRINT to the approved production target fingerprint."
[[ "$TEST_FINGERPRINT" =~ ^sha256:[0-9a-f]{64}$ ]] ||
  die "Set XZS_NEON_TEST_TARGET_FINGERPRINT so the Fly/test target can be explicitly rejected."
target_output="$(
  python3 - "$NEON_DR_DIRECT_URL" "$NEON_TEST_DIRECT_URL" <<'PY'
import hashlib
import re
import sys
import urllib.parse

def parse_target(raw_url):
    try:
        parsed = urllib.parse.urlsplit(raw_url)
        port = parsed.port or 5432
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True, strict_parsing=True)
    except (TypeError, ValueError):
        raise SystemExit("Neon target URL could not be parsed")
    if parsed.scheme not in {"postgres", "postgresql"}:
        raise SystemExit("Neon target must use a PostgreSQL URL")
    if parsed.fragment or not parsed.hostname or not parsed.username or not parsed.path.startswith("/"):
        raise SystemExit("Neon target URL is missing required identity components")
    if query.get("sslmode") != ["require"]:
        raise SystemExit("Neon target URL must set sslmode=require exactly once")
    host = parsed.hostname.lower()
    if not host.endswith(".neon.tech") or "-pooler." in host:
        raise SystemExit("Neon target must be a direct non-pooled Neon endpoint")
    endpoint_id = host.split(".", 1)[0]
    if not re.fullmatch(r"ep-[a-z0-9-]+", endpoint_id):
        raise SystemExit("Neon endpoint identity is invalid")
    database = urllib.parse.unquote(parsed.path[1:])
    role = urllib.parse.unquote(parsed.username)
    if (
        not database
        or "/" in database
        or "|" in database + role
        or any(ord(ch) < 32 for ch in database + role)
    ):
        raise SystemExit("Neon database or role identity is invalid")
    identity = f"{host}|{port}|{database}|{role}"
    fingerprint = hashlib.sha256(identity.encode("utf-8")).hexdigest()
    return f"sha256:{fingerprint}", database, role, endpoint_id

for target_url in sys.argv[1:]:
    print(*parse_target(target_url), sep="\n")
PY
)" || die "Neon target identity parsing failed."
mapfile -t target_fields <<<"$target_output"
[[ "${#target_fields[@]}" -eq 8 ]] || die "Neon target identity parsing failed."
TARGET_FINGERPRINT="${target_fields[0]}"
TARGET_DATABASE="${target_fields[1]}"
TARGET_ROLE="${target_fields[2]}"
TARGET_ENDPOINT_ID="${target_fields[3]}"
CALCULATED_TEST_FINGERPRINT="${target_fields[4]}"

[[ "$CALCULATED_TEST_FINGERPRINT" == "$TEST_FINGERPRINT" ]] ||
  die "Configured Neon test fingerprint does not match NEON_TEST_DIRECT_URL."
[[ "$PRODUCTION_FINGERPRINT" != "$CALCULATED_TEST_FINGERPRINT" ]] ||
  die "Production and test target fingerprints must be different."
[[ "$TARGET_FINGERPRINT" != "$CALCULATED_TEST_FINGERPRINT" ]] ||
  die "Refusing to refresh the configured Fly/test Neon target."
[[ "$TARGET_FINGERPRINT" == "$PRODUCTION_FINGERPRINT" ]] ||
  die "Connected target does not match the approved Neon production fingerprint."

NAS_PROJECT_ROOT="$(resolve_verified_nas_project_root)"
HOURLY_DIR="$(realpath -e "${NAS_PROJECT_ROOT}/hourly")"
[[ "$HOURLY_DIR" == "${NAS_PROJECT_ROOT}/hourly" ]] ||
  die "Hourly backup directory resolves outside the NAS project root."

RAW_DUMP_FILE="$1"
RAW_MANIFEST_FILE="${RAW_DUMP_FILE}.manifest.json"
RAW_CHECKSUM_FILE="${RAW_DUMP_FILE}.sha256"
[[ ! -L "$RAW_DUMP_FILE" && ! -L "$RAW_MANIFEST_FILE" && ! -L "$RAW_CHECKSUM_FILE" ]] ||
  die "Backup family must not contain symbolic links."
DUMP_FILE="$(realpath -e "$RAW_DUMP_FILE")"
MANIFEST_FILE="$(realpath -e "$RAW_MANIFEST_FILE")"
CHECKSUM_FILE="$(realpath -e "$RAW_CHECKSUM_FILE")"
[[ "$(dirname "$DUMP_FILE")" == "$HOURLY_DIR" ]] ||
  die "Neon production refresh only accepts backups from the verified hourly directory."
[[ "$(basename "$DUMP_FILE")" =~ ^xzs-[0-9]{8}T[0-9]{6}Z\.dump$ ]] ||
  die "Backup archive name is invalid."

identity_output=""
if ! identity_output="$(
  docker run --rm \
    --env NEON_DR_DIRECT_URL \
    "$POSTGRES_IMAGE" \
    sh -eu -c 'exec psql "$NEON_DR_DIRECT_URL" --no-psqlrc --tuples-only --no-align --field-separator="|" --set ON_ERROR_STOP=1 --command "SELECT current_database(), current_user, pg_is_in_recovery(), has_database_privilege(current_user, current_database(), \$\$CREATE\$\$);"' \
    2>/dev/null | tr -d '\r'
)"; then
  die "Could not verify the live Neon production target identity."
fi
identity_output="${identity_output%$'\n'}"
[[ "$identity_output" == "${TARGET_DATABASE}|${TARGET_ROLE}|f|t" ]] ||
  die "Live database identity or write capability does not match the approved target."

verify_dump_archive "$DUMP_FILE"

ACTUAL_CHECKSUM="$(sha256sum "$DUMP_FILE" | awk '{print $1}')"
sidecar_output="$(
  python3 - "$CHECKSUM_FILE" "$(basename "$DUMP_FILE")" <<'PY'
import re
import sys

path, expected_name = sys.argv[1:]
try:
    text = open(path, "r", encoding="ascii").read()
except (OSError, UnicodeError):
    raise SystemExit("checksum sidecar is not readable ASCII")
match = re.fullmatch(r"([0-9a-f]{64})  ([^/\r\n]+)\n?", text)
if not match or match.group(2) != expected_name:
    raise SystemExit("checksum sidecar does not describe exactly the selected archive")
print(match.group(1))
PY
)" || die "Backup checksum sidecar validation failed."
[[ "$sidecar_output" == "$ACTUAL_CHECKSUM" ]] || die "Backup checksum verification failed."

MAX_BACKUP_AGE_SECONDS="${XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS:-10800}"
[[ "$MAX_BACKUP_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
  die "XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS must be a positive integer."
(( MAX_BACKUP_AGE_SECONDS <= 86400 )) ||
  die "XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS must not exceed 86400."

manifest_output="$(
  python3 - "$MANIFEST_FILE" "$(basename "$DUMP_FILE")" "$ACTUAL_CHECKSUM" \
    "$(stat --format '%s' "$DUMP_FILE")" "$MAX_BACKUP_AGE_SECONDS" <<'PY'
import datetime
import json
import re
import sys

path, archive_name, checksum, size_text, max_age_text = sys.argv[1:]
try:
    with open(path, "r", encoding="utf-8") as stream:
        data = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit("manifest is not valid readable UTF-8 JSON")

required = {
    "backup_time_utc", "database", "postgres_version", "application_image",
    "flyway_version", "archive", "size_bytes", "sha256", "table_rows"
}
if set(data) != required:
    raise SystemExit("manifest must contain exactly the required fields")
if data["archive"] != archive_name or data["sha256"] != checksum:
    raise SystemExit("manifest archive or checksum does not match")
if data["size_bytes"] != int(size_text):
    raise SystemExit("manifest archive size does not match")
for key in ("database", "postgres_version", "application_image", "flyway_version"):
    if not isinstance(data[key], str) or not data[key] or any(ord(ch) < 32 for ch in data[key]):
        raise SystemExit(f"manifest field is invalid: {key}")

backup_time = data["backup_time_utc"]
if not isinstance(backup_time, str) or not re.fullmatch(r"[0-9]{8}T[0-9]{6}Z", backup_time):
    raise SystemExit("manifest backup time is invalid")
backup_at = datetime.datetime.strptime(backup_time, "%Y%m%dT%H%M%SZ").replace(
    tzinfo=datetime.timezone.utc
)
age = (datetime.datetime.now(datetime.timezone.utc) - backup_at).total_seconds()
if age < -300:
    raise SystemExit("manifest backup time is implausibly in the future")
if age > int(max_age_text):
    raise SystemExit("backup is older than the configured maximum age")

tables = [
    "t_user",
    "t_question",
    "t_exam_paper",
    "t_exam_paper_answer",
    "t_exam_paper_question_customer_answer",
    "t_task_exam_customer_answer",
    "t_question_correction_record",
    "t_question_correction_review_record",
]
rows = data["table_rows"]
if not isinstance(rows, dict) or set(rows) != set(tables):
    raise SystemExit("manifest table row set is incomplete")
if any(isinstance(rows[name], bool) or not isinstance(rows[name], int) or rows[name] < 0 for name in tables):
    raise SystemExit("manifest table row count is invalid")

print(backup_time)
print(data["flyway_version"])
for name in tables:
    print(f"{name}|{rows[name]}")
PY
)" || die "Backup manifest validation failed."
mapfile -t manifest_fields <<<"$manifest_output"
[[ "${#manifest_fields[@]}" -eq 10 ]] || die "Backup manifest validation failed."
SOURCE_BACKUP_TIME="${manifest_fields[0]}"
EXPECTED_FLYWAY_VERSION="${manifest_fields[1]}"

if [[ -n "${XZS_NEON_DR_LATEST_CHECKSUM:-}" || -n "${XZS_NEON_DR_LATEST_COMPLETED_AT:-}" ]]; then
  [[ "${XZS_NEON_DR_LATEST_CHECKSUM:-}" == "$ACTUAL_CHECKSUM" &&
    "${XZS_NEON_DR_LATEST_COMPLETED_AT:-}" == "$SOURCE_BACKUP_TIME" ]] ||
    die "Selected backup no longer matches atomic latest.json metadata."
fi

declare -A EXPECTED_ROWS=()
for entry in "${manifest_fields[@]:2}"; do
  table="${entry%%|*}"
  count="${entry#*|}"
  EXPECTED_ROWS["$table"]="$count"
done

docker run --rm \
  --env NEON_DR_DIRECT_URL \
  --volume "${DUMP_FILE}:/backup.dump:ro" \
  "$POSTGRES_IMAGE" \
  sh -eu -c 'exec pg_restore --dbname="$NEON_DR_DIRECT_URL" --clean --if-exists --no-owner --no-privileges --exit-on-error --single-transaction /backup.dump'

validation_output=""
if ! validation_output="$(
  docker run --rm \
    --env NEON_DR_DIRECT_URL \
    "$POSTGRES_IMAGE" \
    sh -eu -c 'exec psql "$NEON_DR_DIRECT_URL" --no-psqlrc --tuples-only --no-align --field-separator="|" --set ON_ERROR_STOP=1 --command "
      SELECT \$\$flyway_version\$\$, COALESCE((SELECT version FROM public.flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1), \$\$none\$\$)
      UNION ALL SELECT \$\$t_user\$\$, count(*)::text FROM public.t_user
      UNION ALL SELECT \$\$t_question\$\$, count(*)::text FROM public.t_question
      UNION ALL SELECT \$\$t_exam_paper\$\$, count(*)::text FROM public.t_exam_paper
      UNION ALL SELECT \$\$t_exam_paper_answer\$\$, count(*)::text FROM public.t_exam_paper_answer
      UNION ALL SELECT \$\$t_exam_paper_question_customer_answer\$\$, count(*)::text FROM public.t_exam_paper_question_customer_answer
      UNION ALL SELECT \$\$t_task_exam_customer_answer\$\$, count(*)::text FROM public.t_task_exam_customer_answer
      UNION ALL SELECT \$\$t_question_correction_record\$\$, count(*)::text FROM public.t_question_correction_record
      UNION ALL SELECT \$\$t_question_correction_review_record\$\$, count(*)::text FROM public.t_question_correction_review_record
      UNION ALL SELECT \$\$orphan_answer_rows\$\$, count(*)::text
        FROM public.t_exam_paper_question_customer_answer a
        LEFT JOIN public.t_exam_paper_answer p ON p.id = a.exam_paper_answer_id
        WHERE a.exam_paper_answer_id IS NOT NULL AND p.id IS NULL
      UNION ALL SELECT \$\$orphan_correction_rows\$\$, count(*)::text
        FROM public.t_question_correction_record c
        LEFT JOIN public.t_user u ON u.id = c.user_id
        LEFT JOIN public.t_question q ON q.id = c.question_id
        LEFT JOIN public.t_exam_paper_question_customer_answer a ON a.id = c.customer_answer_id
        WHERE u.id IS NULL OR q.id IS NULL OR a.id IS NULL;
    "' 2>/dev/null | tr -d '\r'
)"; then
  die "Post-restore validation query failed."
fi

declare -A ACTUAL_VALUES=()
while IFS='|' read -r key value extra; do
  [[ -n "$key" && -n "$value" && -z "${extra:-}" && -z "${ACTUAL_VALUES[$key]+x}" ]] ||
    die "Post-restore validation returned malformed or duplicate results."
  ACTUAL_VALUES["$key"]="$value"
done <<<"$validation_output"

[[ "${#ACTUAL_VALUES[@]}" -eq 11 ]] || die "Post-restore validation result set is incomplete."
[[ "${ACTUAL_VALUES[flyway_version]:-}" == "$EXPECTED_FLYWAY_VERSION" ]] ||
  die "Post-restore Flyway version does not match the backup manifest."
for table in "${!EXPECTED_ROWS[@]}"; do
  [[ "${ACTUAL_VALUES[$table]:-}" == "${EXPECTED_ROWS[$table]}" ]] ||
    die "Post-restore row count does not match the backup manifest for $table."
done
[[ "${ACTUAL_VALUES[orphan_answer_rows]:-}" == "0" ]] ||
  die "Post-restore validation found orphan answer rows."
[[ "${ACTUAL_VALUES[orphan_correction_rows]:-}" == "0" ]] ||
  die "Post-restore validation found orphan correction rows."

STATE_FILE="${XZS_NEON_DR_STATE_FILE:-/var/lib/xzs-neon-dr-refresh/last-success.json}"
[[ "$STATE_FILE" == /* ]] || die "XZS_NEON_DR_STATE_FILE must be an absolute path."
STATE_DIR="$(dirname "$STATE_FILE")"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
STATE_TMP="$(mktemp "${STATE_DIR}/.last-success.XXXXXX")"
cleanup_state_tmp() {
  rm -f -- "${STATE_TMP:-}"
}
trap cleanup_state_tmp EXIT
chmod 600 "$STATE_TMP"
{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "completed_at_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "source_backup_time_utc": "%s",\n' "$SOURCE_BACKUP_TIME"
  printf '  "source_archive": "%s",\n' "$(basename "$DUMP_FILE")"
  printf '  "source_sha256": "%s",\n' "$ACTUAL_CHECKSUM"
  printf '  "target_fingerprint": "%s",\n' "$TARGET_FINGERPRINT"
  printf '  "target_endpoint_id": "%s",\n' "$TARGET_ENDPOINT_ID"
  printf '  "flyway_version": "%s",\n' "$(json_escape "$EXPECTED_FLYWAY_VERSION")"
  printf '  "table_rows": {\n'
  tables=(t_user t_question t_exam_paper t_exam_paper_answer t_exam_paper_question_customer_answer t_task_exam_customer_answer t_question_correction_record t_question_correction_review_record)
  for ((i = 0; i < ${#tables[@]}; i++)); do
    table="${tables[$i]}"
    comma=","
    (( i == ${#tables[@]} - 1 )) && comma=""
    printf '    "%s": %s%s\n' "$table" "${EXPECTED_ROWS[$table]}" "$comma"
  done
  printf '  },\n'
  printf '  "orphan_answer_rows": 0,\n'
  printf '  "orphan_correction_rows": 0,\n'
  printf '  "result": "passed"\n'
  printf '}\n'
} >"$STATE_TMP"
mv -- "$STATE_TMP" "$STATE_FILE"
trap - EXIT

printf 'Verified backup refreshed to the approved Neon production target; success state updated.\n'
