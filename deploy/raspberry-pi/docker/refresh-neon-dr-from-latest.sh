#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

require_command python3
require_command realpath

MAX_BACKUP_AGE_SECONDS="${XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS:-10800}"
[[ "$MAX_BACKUP_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
  die "XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS must be a positive integer."
(( MAX_BACKUP_AGE_SECONDS <= 86400 )) ||
  die "XZS_NEON_DR_MAX_BACKUP_AGE_SECONDS must not exceed 86400."

NAS_PROJECT_ROOT="$(resolve_verified_nas_project_root)"

HOURLY_DIR="$(realpath -e "${NAS_PROJECT_ROOT}/hourly")"
[[ "$HOURLY_DIR" == "${NAS_PROJECT_ROOT}/hourly" ]] ||
  die "Hourly backup directory resolves outside the NAS project root."

LATEST_FILE="${NAS_PROJECT_ROOT}/latest.json"
require_file "$LATEST_FILE"
[[ ! -L "$LATEST_FILE" ]] || die "latest.json must not be a symbolic link."

latest_output="$({
  python3 - "$LATEST_FILE" "$MAX_BACKUP_AGE_SECONDS" <<'PY'
import datetime
import json
import re
import sys

path, max_age_text = sys.argv[1:]
try:
    with open(path, "r", encoding="utf-8") as stream:
        data = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit("latest.json is not valid readable UTF-8 JSON")

required = {"completed_at_utc", "class", "archive", "manifest", "sha256"}
if set(data) != required:
    raise SystemExit("latest.json must contain exactly the required fields")
if data["class"] != "hourly":
    raise SystemExit("latest.json does not point to an hourly backup")
archive = data["archive"]
manifest = data["manifest"]
if not isinstance(archive, str) or not re.fullmatch(r"hourly/xzs-[0-9]{8}T[0-9]{6}Z\.dump", archive):
    raise SystemExit("latest.json archive is outside the permitted hourly backup family")
if manifest != archive + ".manifest.json":
    raise SystemExit("latest.json manifest does not match its archive")
checksum = data["sha256"]
if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
    raise SystemExit("latest.json sha256 is invalid")
completed = data["completed_at_utc"]
if not isinstance(completed, str) or not re.fullmatch(r"[0-9]{8}T[0-9]{6}Z", completed):
    raise SystemExit("latest.json completed_at_utc is invalid")
completed_at = datetime.datetime.strptime(completed, "%Y%m%dT%H%M%SZ").replace(
    tzinfo=datetime.timezone.utc
)
age = (datetime.datetime.now(datetime.timezone.utc) - completed_at).total_seconds()
if age < -300:
    raise SystemExit("latest.json completion time is implausibly in the future")
if age > int(max_age_text):
    raise SystemExit("latest hourly backup is older than the configured maximum age")

print(archive)
print(manifest)
print(checksum)
print(completed)
PY
})" || die "Atomic latest backup metadata validation failed."
mapfile -t latest_fields <<<"$latest_output"
[[ "${#latest_fields[@]}" -eq 4 ]] || die "Atomic latest backup metadata validation failed."

archive_relative="${latest_fields[0]}"
manifest_relative="${latest_fields[1]}"
expected_checksum="${latest_fields[2]}"
completed_at_utc="${latest_fields[3]}"

RAW_DUMP_FILE="${NAS_PROJECT_ROOT}/${archive_relative}"
RAW_MANIFEST_FILE="${NAS_PROJECT_ROOT}/${manifest_relative}"
RAW_CHECKSUM_FILE="${NAS_PROJECT_ROOT}/${archive_relative}.sha256"
[[ ! -L "$RAW_DUMP_FILE" && ! -L "$RAW_MANIFEST_FILE" && ! -L "$RAW_CHECKSUM_FILE" ]] ||
  die "Latest backup family must not contain symbolic links."
DUMP_FILE="$(realpath -e "$RAW_DUMP_FILE")"
MANIFEST_FILE="$(realpath -e "$RAW_MANIFEST_FILE")"
CHECKSUM_FILE="$(realpath -e "$RAW_CHECKSUM_FILE")"
[[ "$(dirname "$DUMP_FILE")" == "$HOURLY_DIR" ]] ||
  die "Latest backup archive resolves outside the hourly directory."
[[ "$MANIFEST_FILE" == "${DUMP_FILE}.manifest.json" && "$CHECKSUM_FILE" == "${DUMP_FILE}.sha256" ]] ||
  die "Latest backup sidecars do not belong to the selected archive."

export XZS_NEON_DR_LATEST_CHECKSUM="$expected_checksum"
export XZS_NEON_DR_LATEST_COMPLETED_AT="$completed_at_utc"
exec "${SCRIPT_DIR}/refresh-neon-disaster-recovery.sh" "$DUMP_FILE"
