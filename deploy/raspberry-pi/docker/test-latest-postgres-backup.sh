#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

NAS_PROJECT_ROOT="${XZS_BACKUP_ROOT:-/mnt/zspace-xzs-backup/gesp-csp-quiz}"
HOURLY_DIR="${NAS_PROJECT_ROOT}/hourly"
[[ -d "$HOURLY_DIR" ]] || die "Hourly backup directory does not exist: $HOURLY_DIR"

latest_dump="$(
  find "$HOURLY_DIR" -mindepth 1 -maxdepth 1 -type f -name 'xzs-*.dump' -printf '%T@ %p\n' |
    sort -rn |
    sed -n '1s/^[^ ]* //p'
)"
[[ -n "$latest_dump" ]] || die "No hourly PostgreSQL backup found."
exec "${SCRIPT_DIR}/test-restore-postgres-backup.sh" "$latest_dump"
