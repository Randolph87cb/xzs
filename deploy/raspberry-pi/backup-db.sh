#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-xzs}"
DB_USER="${DB_USER:-xzs}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
BACKUP_DIR="${BACKUP_DIR:-/opt/xzs/backups}"
RETAIN_BACKUPS="${RETAIN_BACKUPS:-7}"

if [[ ! "$RETAIN_BACKUPS" =~ ^[1-9][0-9]*$ ]]; then
  echo "RETAIN_BACKUPS must be a positive integer." >&2
  exit 1
fi

require_identifier() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "$name must be a PostgreSQL identifier: $value" >&2
    exit 1
  fi
}

require_identifier "DB_NAME" "$DB_NAME"

if [[ -n "${DB_PASSWORD:-}" ]]; then
  export PGPASSWORD="$DB_PASSWORD"
fi

umask 077
mkdir -p "$BACKUP_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_file="${BACKUP_DIR}/${DB_NAME}-${timestamp}.dump"

pg_dump \
  --host "$DB_HOST" \
  --port "$DB_PORT" \
  --username "$DB_USER" \
  --dbname "$DB_NAME" \
  --format custom \
  --no-owner \
  --no-privileges \
  --file "$backup_file"

echo "Backup written to: $backup_file"

mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB_NAME}-*.dump" -printf '%T@ %p\n' | sort -rn | sed 's/^[^ ]* //')
for ((i = RETAIN_BACKUPS; i < ${#backups[@]}; i++)); do
  rm -f -- "${backups[$i]}"
  echo "Removed old backup: ${backups[$i]}"
done
