#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

BACKUP_FILE=""
TARGET_DB=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup)
      [[ $# -ge 2 ]] || die "--backup requires a file"
      BACKUP_FILE="$2"
      shift 2
      ;;
    --target-db)
      [[ $# -ge 2 ]] || die "--target-db requires a database name"
      TARGET_DB="$2"
      shift 2
      ;;
    *)
      die "Usage: $0 --backup /path/to/xzs-*.dump --target-db database_name"
      ;;
  esac
done

[[ -n "$BACKUP_FILE" && -n "$TARGET_DB" ]] ||
  die "Both --backup and --target-db are required."
[[ "$TARGET_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
  die "Target database must be a PostgreSQL identifier."
[[ "${XZS_RESTORE_CONFIRM:-}" == "RESTORE:${TARGET_DB}" ]] ||
  die "Set XZS_RESTORE_CONFIRM=RESTORE:${TARGET_DB} to confirm destructive replacement of the target database."

require_command docker
require_command sha256sum
BACKUP_FILE="$(realpath "$BACKUP_FILE")"
verify_dump_archive "$BACKUP_FILE"
verify_checksum_sidecar "$BACKUP_FILE"
load_postgres_identity

if [[ "$TARGET_DB" == "$POSTGRES_DB" ]]; then
  [[ "${XZS_ALLOW_PRODUCTION_RESTORE:-}" == "YES_I_HAVE_STOPPED_WRITES_AND_TAKEN_RESCUE_BACKUP" ]] ||
    die "Production restore refused. Stop application writes, create a labelled rescue backup, and set XZS_ALLOW_PRODUCTION_RESTORE=YES_I_HAVE_STOPPED_WRITES_AND_TAKEN_RESCUE_BACKUP."
  if compose ps --status running app | grep -q xzs-app; then
    die "Production application is still running; stop it before restore."
  fi
  [[ -n "${XZS_RESCUE_BACKUP_FILE:-}" ]] ||
    die "Set XZS_RESCUE_BACKUP_FILE to the verified rescue backup made after writes stopped."
  rescue_file="$(realpath "$XZS_RESCUE_BACKUP_FILE")"
  [[ "$rescue_file" != "$BACKUP_FILE" ]] ||
    die "The rescue backup must be different from the restore source."
  verify_dump_archive "$rescue_file"
  verify_checksum_sidecar "$rescue_file"
  [[ "$rescue_file" -nt "$BACKUP_FILE" ]] ||
    die "The rescue backup must be newer than the restore source."
fi

postgres_exec pg_restore \
  --username "$POSTGRES_USER" \
  --dbname "$TARGET_DB" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --exit-on-error <"$BACKUP_FILE"

printf 'Destructive restore completed for explicitly confirmed target database: %s\n' "$TARGET_DB"
