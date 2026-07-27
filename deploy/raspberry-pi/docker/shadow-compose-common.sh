#!/usr/bin/env bash
set -euo pipefail

SHADOW_APP_DIR="${XZS_APP_DIR:-/opt/apps/gesp-csp-quiz}"
SHADOW_COMPOSE_FILE="${XZS_SHADOW_COMPOSE_FILE:-${SHADOW_APP_DIR}/docker-compose.yml}"
SHADOW_ENV_FILE="${XZS_SHADOW_ENV_FILE:-${SHADOW_APP_DIR}/.env.shadow}"
SHADOW_PROJECT_NAME="xzs-shadow"

read_env_value() {
  local file="$1"
  local key="$2"
  local line
  line="$(grep -m 1 -E "^[[:space:]]*${key}[[:space:]]*=" "$file" || true)"
  [[ -n "$line" ]] || return 1
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ "$line" == \"*\" && "$line" == *\" ]]; then
    line="${line:1:${#line}-2}"
  elif [[ "$line" == \'*\' && "$line" == *\' ]]; then
    line="${line:1:${#line}-2}"
  fi
  printf '%s' "$line"
}

shadow_compose() {
  docker compose \
    --project-name "$SHADOW_PROJECT_NAME" \
    --project-directory "$SHADOW_APP_DIR" \
    --env-file "$SHADOW_ENV_FILE" \
    -f "$SHADOW_COMPOSE_FILE" \
    "$@"
}

assert_shadow_configuration() {
  require_file "$SHADOW_COMPOSE_FILE"
  require_file "$SHADOW_ENV_FILE"

  [[ "$(read_env_value "$SHADOW_ENV_FILE" COMPOSE_PROJECT_NAME)" == "$SHADOW_PROJECT_NAME" ]] ||
    die "Shadow env must set COMPOSE_PROJECT_NAME=xzs-shadow."
  [[ "$(read_env_value "$SHADOW_ENV_FILE" XZS_POSTGRES_CONTAINER_NAME)" == "xzs-postgres-shadow" ]] ||
    die "Shadow PostgreSQL container name must be xzs-postgres-shadow."
  [[ "$(read_env_value "$SHADOW_ENV_FILE" XZS_APP_CONTAINER_NAME)" == "xzs-app-shadow" ]] ||
    die "Shadow app container name must be xzs-app-shadow."
  [[ "$(read_env_value "$SHADOW_ENV_FILE" XZS_HOST_BIND)" == "127.0.0.1" ]] ||
    die "Shadow app must bind only to 127.0.0.1."
  [[ "$(read_env_value "$SHADOW_ENV_FILE" XZS_HOST_PORT)" == "18000" ]] ||
    die "Shadow app host port must be 18000."

  shadow_data_configured="$(read_env_value "$SHADOW_ENV_FILE" XZS_POSTGRES_DATA_DIR)"
  [[ "$shadow_data_configured" == /* ]] || die "Shadow PostgreSQL data directory must be absolute."
  SHADOW_DATA_DIR="$(realpath -m "$shadow_data_configured")"
  [[ "$SHADOW_DATA_DIR" =~ (^|/)[^/]*shadow[^/]*(/|$) ]] ||
    die "Shadow data path must contain a path component identifying it as shadow data."
  [[ "$SHADOW_DATA_DIR" != /mnt/zspace-xzs-backup/* ]] ||
    die "Shadow PostgreSQL data must not be stored in the NAS backup tree."

  production_env="${SHADOW_APP_DIR}/.env"
  if [[ -r "$production_env" ]]; then
    production_data_dir="$(read_env_value "$production_env" XZS_POSTGRES_DATA_DIR || true)"
    if [[ -n "$production_data_dir" ]]; then
      production_data_dir="$(realpath -m "$production_data_dir")"
      [[ "$production_data_dir" != "$SHADOW_DATA_DIR" ]] ||
        die "Shadow and production PostgreSQL data directories must be different."
    fi
  fi

  SHADOW_POSTGRES_USER="$(read_env_value "$SHADOW_ENV_FILE" XZS_POSTGRES_USER)"
  SHADOW_POSTGRES_DB="$(read_env_value "$SHADOW_ENV_FILE" XZS_POSTGRES_DB)"
  [[ "$SHADOW_POSTGRES_USER" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
    die "Shadow PostgreSQL user must be a PostgreSQL identifier."
  [[ "$SHADOW_POSTGRES_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
    die "Shadow PostgreSQL database must be a PostgreSQL identifier."
  [[ "$SHADOW_POSTGRES_DB" != "xzs" ]] ||
    die "Shadow database name must not be the production database name xzs."

  POSTGRES_IMAGE="$(read_env_value "$SHADOW_ENV_FILE" XZS_POSTGRES_IMAGE)"
  export POSTGRES_IMAGE
}

shadow_postgres_exec() {
  shadow_compose exec -T postgres "$@"
}
