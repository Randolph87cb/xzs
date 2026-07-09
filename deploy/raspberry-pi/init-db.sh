#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-xzs}"
DB_USER="${DB_USER:-xzs}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
SQL_FILE="${SQL_FILE:-/opt/xzs/sql/xzs-postgresql.sql}"
DB_PASSWORD="${DB_PASSWORD:-}"

if [[ -z "$DB_PASSWORD" ]]; then
  echo "Set DB_PASSWORD before running this script." >&2
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

sql_literal() {
  local value="${1//\'/\'\'}"
  printf "%s" "$value"
}

psql_as_postgres() {
  if [[ "$(id -un)" == "postgres" ]]; then
    psql -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -v ON_ERROR_STOP=1 "$@"
  fi
}

psql_as_app_user() {
  PGPASSWORD="$DB_PASSWORD" psql \
    -v ON_ERROR_STOP=1 \
    --host "$DB_HOST" \
    --port "$DB_PORT" \
    --username "$DB_USER" \
    "$@"
}

require_identifier "DB_NAME" "$DB_NAME"
require_identifier "DB_USER" "$DB_USER"

if [[ ! -r "$SQL_FILE" ]]; then
  echo "SQL file is not readable: $SQL_FILE" >&2
  exit 1
fi

DB_PASSWORD_SQL="$(sql_literal "$DB_PASSWORD")"
DB_NAME_SQL="$(sql_literal "$DB_NAME")"

echo "Creating or updating PostgreSQL role '$DB_USER' and database '$DB_NAME'."
psql_as_postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE "${DB_USER}" LOGIN PASSWORD '${DB_PASSWORD_SQL}';
  ELSE
    ALTER ROLE "${DB_USER}" WITH LOGIN PASSWORD '${DB_PASSWORD_SQL}';
  END IF;
END
\$\$;
SQL

if [[ "$(psql_as_postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME_SQL}'" | tr -d '[:space:]')" != "1" ]]; then
  psql_as_postgres -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";"
else
  psql_as_postgres -c "ALTER DATABASE \"${DB_NAME}\" OWNER TO \"${DB_USER}\";"
fi

psql_as_postgres -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON DATABASE \"${DB_NAME}\" TO \"${DB_USER}\";"

echo "Importing schema and seed data from '$SQL_FILE'."
psql_as_app_user --dbname "$DB_NAME" --file "$SQL_FILE"

echo "Database initialization completed."
