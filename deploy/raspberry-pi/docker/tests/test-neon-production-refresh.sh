#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENTRYPOINT="${OPS_DIR}/refresh-neon-dr-from-latest.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xzs-neon-refresh-tests.XXXXXX")"
[[ "$TEST_ROOT" == "${TMPDIR:-/tmp}"/xzs-neon-refresh-tests.* ]] || {
  printf 'Unsafe test directory: %s\n' "$TEST_ROOT" >&2
  exit 1
}

cleanup() {
  [[ "$TEST_ROOT" == "${TMPDIR:-/tmp}"/xzs-neon-refresh-tests.* ]] && rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

FAKE_BIN="${TEST_ROOT}/bin"
MOUNT_TARGET="${TEST_ROOT}/nas-mount"
BACKUP_ROOT="${MOUNT_TARGET}/gesp-csp-quiz"
LOCK_FILE="${TEST_ROOT}/xzs-postgres-ops.lock"
mkdir -p "$FAKE_BIN" "$BACKUP_ROOT/hourly"

cat >"${FAKE_BIN}/findmnt" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAKE_NAS_MOUNT_OK:-1}" == "1" ]] || exit 1
printf '%s %s\n' "$FAKE_MOUNT_TARGET" "${FAKE_MOUNT_FSTYPE:-cifs}"
SH

cat >"${FAKE_BIN}/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >>"$FAKE_DOCKER_CALL_LOG"
if [[ "${FAKE_ASSERT_SHARED_LOCK_HELD:-1}" == "1" ]]; then
  lock_fd="${XZS_POSTGRES_OPS_LOCK_FD:-}"
  [[ "$lock_fd" =~ ^[0-9]+$ && -e "/proc/$$/fd/${lock_fd}" ]] || {
    printf 'Shared lock descriptor was not inherited by the downstream command.\n' >&2
    exit 96
  }
  eval "exec ${lock_fd}>&-"
  if flock -n "$XZS_POSTGRES_OPS_LOCK_FILE" -c true; then
    printf 'Shared lock was not held across latest selection and downstream execution.\n' >&2
    exit 96
  fi
fi
args="$*"
if [[ "$args" == *"pg_restore --list"* ]]; then
  exit 0
fi
if [[ "$args" == *"SELECT current_database()"* ]]; then
  printf '%s|%s|f|t\n' "$FAKE_TARGET_DATABASE" "$FAKE_TARGET_ROLE"
  exit 0
fi
if [[ "$args" == *"pg_restore --dbname="* ]]; then
  [[ "${FAKE_RESTORE_FAIL:-0}" == "0" ]] || exit 42
  exit 0
fi
if [[ "$args" == *"flyway_version"* ]]; then
  cat <<'ROWS'
flyway_version|5.9.0
t_user|1
t_question|2
t_exam_paper|3
t_exam_paper_answer|4
t_exam_paper_question_customer_answer|5
t_task_exam_customer_answer|6
t_question_correction_record|7
t_question_correction_review_record|8
orphan_answer_rows|0
orphan_correction_rows|0
ROWS
  exit 0
fi
printf 'Unexpected fake docker invocation.\n' >&2
exit 97
SH
chmod +x "${FAKE_BIN}/findmnt" "${FAKE_BIN}/docker"

fingerprint_for_url() {
  python3 - "$1" <<'PY'
import hashlib
import urllib.parse
import sys

parsed = urllib.parse.urlsplit(sys.argv[1])
identity = "|".join([
    parsed.hostname.lower(),
    str(parsed.port or 5432),
    urllib.parse.unquote(parsed.path[1:]),
    urllib.parse.unquote(parsed.username),
])
print("sha256:" + hashlib.sha256(identity.encode("utf-8")).hexdigest())
PY
}

PRODUCTION_URL='postgresql://fixture_role:fixture-password@ep-production-fixture.example.neon.tech/xzs?sslmode=require'
TEST_URL='postgresql://fixture_role:fixture-password@ep-test-fixture.example.neon.tech/xzs?sslmode=require'
WRONG_URL='postgresql://fixture_role:fixture-password@ep-wrong-fixture.example.neon.tech/xzs?sslmode=require'
TEST_URL_WITHOUT_SSL='postgresql://fixture_role:fixture-password@ep-test-fixture.example.neon.tech/xzs'
PRODUCTION_FINGERPRINT="$(fingerprint_for_url "$PRODUCTION_URL")"
TEST_FINGERPRINT="$(fingerprint_for_url "$TEST_URL")"
WRONG_FINGERPRINT="$(fingerprint_for_url "$WRONG_URL")"

CURRENT_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

create_backup_family() {
  local timestamp="$1"
  local base="xzs-${timestamp}.dump"
  local dump="${BACKUP_ROOT}/hourly/${base}"
  local checksum
  local size

  rm -rf -- "${BACKUP_ROOT}/hourly"
  mkdir -p "${BACKUP_ROOT}/hourly"
  printf 'offline custom archive fixture: %s\n' "$timestamp" >"$dump"
  checksum="$(sha256sum "$dump" | awk '{print $1}')"
  size="$(stat --format '%s' "$dump")"
  printf '%s  %s\n' "$checksum" "$base" >"${dump}.sha256"
  cat >"${dump}.manifest.json" <<JSON
{
  "backup_time_utc": "${timestamp}",
  "database": "xzs",
  "postgres_version": "18.fixture",
  "application_image": "fixture",
  "flyway_version": "5.9.0",
  "archive": "${base}",
  "size_bytes": ${size},
  "sha256": "${checksum}",
  "table_rows": {
    "t_user": 1,
    "t_question": 2,
    "t_exam_paper": 3,
    "t_exam_paper_answer": 4,
    "t_exam_paper_question_customer_answer": 5,
    "t_task_exam_customer_answer": 6,
    "t_question_correction_record": 7,
    "t_question_correction_review_record": 8
  }
}
JSON
  cat >"${BACKUP_ROOT}/latest.json" <<JSON
{
  "completed_at_utc": "${timestamp}",
  "class": "hourly",
  "archive": "hourly/${base}",
  "manifest": "hourly/${base}.manifest.json",
  "sha256": "${checksum}"
}
JSON
}

case_state_file() {
  printf '%s/state/%s.json' "$TEST_ROOT" "$1"
}

run_refresh() {
  local state_file="$1"
  mkdir -p "$(dirname "$state_file")"
  (
    export PATH="${FAKE_BIN}:$PATH"
    export XZS_BACKUP_ROOT="$BACKUP_ROOT"
    export XZS_BACKUP_EXPECTED_MOUNT_TARGET="$MOUNT_TARGET"
    export XZS_BACKUP_EXPECTED_FSTYPE=cifs
    export XZS_POSTGRES_OPS_LOCK_FILE="$LOCK_FILE"
    if [[ -n "${CASE_INHERITED_LOCK_FD:-}" ]]; then
      export XZS_POSTGRES_OPS_LOCK_FD="$CASE_INHERITED_LOCK_FD"
    else
      unset XZS_POSTGRES_OPS_LOCK_FD
    fi
    export XZS_NEON_DR_STATE_FILE="$state_file"
    export XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS=10800
    export XZS_NEON_DR_REFRESH_CONFIRM=REFRESH_NEON_PRODUCTION
    export NEON_DR_DIRECT_URL="${CASE_URL-$PRODUCTION_URL}"
    export NEON_TEST_DIRECT_URL="${CASE_TEST_URL-$TEST_URL}"
    export XZS_NEON_PRODUCTION_TARGET_FINGERPRINT="${CASE_PRODUCTION_FINGERPRINT-$PRODUCTION_FINGERPRINT}"
    export XZS_NEON_TEST_TARGET_FINGERPRINT="${CASE_TEST_FINGERPRINT-$TEST_FINGERPRINT}"
    export FAKE_MOUNT_TARGET="$MOUNT_TARGET"
    export FAKE_MOUNT_FSTYPE="${CASE_MOUNT_FSTYPE-cifs}"
    export FAKE_NAS_MOUNT_OK="${CASE_NAS_MOUNT_OK-1}"
    export FAKE_TARGET_DATABASE="${CASE_TARGET_DATABASE-xzs}"
    export FAKE_TARGET_ROLE="${CASE_TARGET_ROLE-fixture_role}"
    export FAKE_RESTORE_FAIL="${CASE_RESTORE_FAIL-0}"
    export FAKE_DOCKER_CALL_LOG="${state_file}.docker-calls"
    "$ENTRYPOINT"
  )
}

assert_log_is_sanitized() {
  local log_file="$1"
  if grep -Fq 'fixture-password' "$log_file" || grep -Eq 'postgres(ql)?://' "$log_file"; then
    printf 'FAIL: log leaked a connection secret\n' >&2
    sed 's/.*/[redacted test output]/' "$log_file" >&2
    exit 1
  fi
}

expect_failure() {
  local name="$1"
  local state_file
  local log_file="${TEST_ROOT}/${name}.log"
  state_file="$(case_state_file "$name")"
  if run_refresh "$state_file" >"$log_file" 2>&1; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  [[ ! -e "$state_file" ]] || {
    printf 'FAIL: %s wrote success state on failure\n' "$name" >&2
    exit 1
  }
  assert_log_is_sanitized "$log_file"
  printf 'PASS: %s\n' "$name"
}

expect_success() {
  local name="$1"
  local state_file
  local log_file="${TEST_ROOT}/${name}.log"
  state_file="$(case_state_file "$name")"
  if ! run_refresh "$state_file" >"$log_file" 2>&1; then
    printf 'FAIL: %s did not succeed\n' "$name" >&2
    sed -e 's/fixture-password/[redacted]/g' -e 's#postgres\(ql\)\?://[^[:space:]]*#[redacted-url]#g' "$log_file" >&2
    exit 1
  fi
  assert_log_is_sanitized "$log_file"
  python3 - "$state_file" "$PRODUCTION_FINGERPRINT" <<'PY'
import json
import sys

path, expected_fingerprint = sys.argv[1:]
with open(path, "r", encoding="utf-8") as stream:
    state = json.load(stream)
assert state["schema_version"] == 1
assert state["result"] == "passed"
assert state["target_fingerprint"] == expected_fingerprint
assert state["source_archive"].startswith("xzs-")
assert state["source_sha256"] and len(state["source_sha256"]) == 64
assert state["orphan_answer_rows"] == 0
assert state["orphan_correction_rows"] == 0
assert len(state["table_rows"]) == 8
serialized = json.dumps(state)
assert "fixture-password" not in serialized
assert "postgresql://" not in serialized
PY
  printf 'PASS: %s\n' "$name"
}

expect_failure_before_docker() {
  local name="$1"
  local state_file
  local log_file="${TEST_ROOT}/${name}.log"
  state_file="$(case_state_file "$name")"
  if run_refresh "$state_file" >"$log_file" 2>&1; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  [[ ! -e "$state_file" && ! -e "${state_file}.docker-calls" ]] || {
    printf 'FAIL: %s reached Docker or wrote success state\n' "$name" >&2
    exit 1
  }
  assert_log_is_sanitized "$log_file"
  printf 'PASS: %s\n' "$name"
}

expect_failure_preserves_existing_success() {
  local name="$1"
  local state_file
  local expected_file="${TEST_ROOT}/${name}.expected.json"
  local log_file="${TEST_ROOT}/${name}.log"
  state_file="$(case_state_file "$name")"
  mkdir -p "$(dirname "$state_file")"
  printf '{"schema_version":1,"result":"passed","source_sha256":"prior-success"}\n' >"$state_file"
  cp -- "$state_file" "$expected_file"
  if run_refresh "$state_file" >"$log_file" 2>&1; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  cmp --silent "$expected_file" "$state_file" || {
    printf 'FAIL: %s overwrote the prior success state\n' "$name" >&2
    exit 1
  }
  assert_log_is_sanitized "$log_file"
  printf 'PASS: %s\n' "$name"
}

create_backup_family "$CURRENT_TIMESTAMP"
CASE_PRODUCTION_FINGERPRINT='' expect_failure target_identity_missing

create_backup_family "$CURRENT_TIMESTAMP"
CASE_PRODUCTION_FINGERPRINT="$WRONG_FINGERPRINT" expect_failure target_identity_wrong

create_backup_family "$CURRENT_TIMESTAMP"
CASE_URL="$TEST_URL" expect_failure test_target_rejected

create_backup_family "$CURRENT_TIMESTAMP"
CASE_URL="$TEST_URL" CASE_TEST_FINGERPRINT="$WRONG_FINGERPRINT" \
  expect_failure_before_docker test_url_deny_fingerprint_mismatch

create_backup_family "$CURRENT_TIMESTAMP"
CASE_TEST_URL="$TEST_URL_WITHOUT_SSL" expect_failure_before_docker test_url_requires_sslmode

create_backup_family "$CURRENT_TIMESTAMP"
CASE_INHERITED_LOCK_FD=999 expect_failure_before_docker forged_lock_descriptor_rejected

create_backup_family "$CURRENT_TIMESTAMP"
python3 - "${BACKUP_ROOT}/latest.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["archive"] = "../manual/xzs-20000101T000000Z.dump"
data["manifest"] = data["archive"] + ".manifest.json"
with open(path, "w", encoding="utf-8") as stream:
    json.dump(data, stream)
PY
expect_failure latest_metadata_path_escape

create_backup_family '20000101T000000Z'
expect_failure latest_metadata_expired

create_backup_family "$CURRENT_TIMESTAMP"
rm -- "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.sha256"
expect_failure backup_sidecar_missing

create_backup_family "$CURRENT_TIMESTAMP"
mv -- "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump" \
  "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.real"
ln -s "xzs-${CURRENT_TIMESTAMP}.dump.real" \
  "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump"
expect_failure_before_docker archive_symlink_rejected

create_backup_family "$CURRENT_TIMESTAMP"
mv -- "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.manifest.json" \
  "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.manifest.json.real"
ln -s "xzs-${CURRENT_TIMESTAMP}.dump.manifest.json.real" \
  "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.manifest.json"
expect_failure_before_docker manifest_symlink_rejected

create_backup_family "$CURRENT_TIMESTAMP"
mv -- "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.sha256" \
  "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.sha256.real"
ln -s "xzs-${CURRENT_TIMESTAMP}.dump.sha256.real" \
  "${BACKUP_ROOT}/hourly/xzs-${CURRENT_TIMESTAMP}.dump.sha256"
expect_failure_before_docker checksum_symlink_rejected

create_backup_family "$CURRENT_TIMESTAMP"
CASE_NAS_MOUNT_OK=0 expect_failure nas_filesystem_not_verified

create_backup_family "$CURRENT_TIMESTAMP"
CASE_MOUNT_FSTYPE=ext4 expect_failure nas_wrong_filesystem_type

create_backup_family "$CURRENT_TIMESTAMP"
LOCK_READY="${TEST_ROOT}/lock-ready"
flock "$LOCK_FILE" sh -c 'touch "$1"; sleep 2' sh "$LOCK_READY" &
LOCK_HOLDER_PID=$!
for _ in {1..50}; do
  [[ -e "$LOCK_READY" ]] && break
  sleep 0.1
done
[[ -e "$LOCK_READY" ]] || {
  printf 'FAIL: shared lock fixture did not become ready\n' >&2
  exit 1
}
rm -- "${BACKUP_ROOT}/latest.json"
expect_failure_before_docker shared_lock_conflict_before_latest_read
grep -Fq 'Another XZS PostgreSQL backup, restore, or Neon refresh operation' \
  "${TEST_ROOT}/shared_lock_conflict_before_latest_read.log" || {
  printf 'FAIL: shared lock conflict did not win before latest metadata validation\n' >&2
  exit 1
}
wait "$LOCK_HOLDER_PID"

create_backup_family "$CURRENT_TIMESTAMP"
CASE_RESTORE_FAIL=1 expect_failure restore_failure_has_no_success_state

create_backup_family "$CURRENT_TIMESTAMP"
CASE_RESTORE_FAIL=1 expect_failure_preserves_existing_success restore_failure_preserves_prior_success

create_backup_family "$CURRENT_TIMESTAMP"
expect_success complete_restore_and_validation

printf 'All offline Neon production refresh failure-gate tests passed.\n'
