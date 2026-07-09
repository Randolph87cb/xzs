#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/xzs-backup.dump" >&2
  exit 1
fi

BACKUP_FILE="$1"
DB_NAME="${DB_NAME:-xzs}"
DB_USER="${DB_USER:-xzs}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"

if [[ ! -r "$BACKUP_FILE" ]]; then
  echo "Backup file is not readable: $BACKUP_FILE" >&2
  exit 1
fi

cat >&2 <<EOF
Destructive restore requested.
Target database: $DB_NAME
Backup file: $BACKUP_FILE

This will clean existing objects in the target database before restoring.
Set XZS_RESTORE_CONFIRM=YES to continue.
EOF

if [[ "${XZS_RESTORE_CONFIRM:-}" != "YES" ]]; then
  echo "Restore aborted." >&2
  exit 1
fi

if [[ -n "${DB_PASSWORD:-}" ]]; then
  export PGPASSWORD="$DB_PASSWORD"
fi

pg_restore \
  --host "$DB_HOST" \
  --port "$DB_PORT" \
  --username "$DB_USER" \
  --dbname "$DB_NAME" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  "$BACKUP_FILE"

echo "Restore completed from: $BACKUP_FILE"
