#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"
# shellcheck source=shadow-compose-common.sh
source "${SCRIPT_DIR}/shadow-compose-common.sh"

DELETE_DATA=0
if [[ $# -gt 0 ]]; then
  [[ $# -eq 1 && "$1" == "--delete-data" ]] ||
    die "Usage: $0 [--delete-data]"
  DELETE_DATA=1
fi

require_command docker
require_command realpath
assert_shadow_configuration

# This removes only the fixed xzs-shadow project's containers and network.
# The bind-mounted PostgreSQL directory is retained by default.
shadow_compose down --remove-orphans

if (( DELETE_DATA == 0 )); then
  printf 'Shadow containers and network removed; shadow PostgreSQL data retained: %s\n' "$SHADOW_DATA_DIR"
  exit 0
fi

[[ "${XZS_SHADOW_DELETE_CONFIRM:-}" == "DELETE_XZS_SHADOW_DATA" ]] ||
  die "Data deletion refused. Set XZS_SHADOW_DELETE_CONFIRM=DELETE_XZS_SHADOW_DATA and retry with --delete-data."

resolved_data_dir="$(realpath -m "$SHADOW_DATA_DIR")"
[[ "$resolved_data_dir" == /* && "$resolved_data_dir" != "/" ]] ||
  die "Refusing unsafe shadow data path: $resolved_data_dir"
[[ "$resolved_data_dir" =~ (^|/)[^/]*shadow[^/]*(/|$) ]] ||
  die "Refusing to delete a path without a shadow-specific component."
[[ "$resolved_data_dir" != "$SHADOW_APP_DIR" && "$resolved_data_dir" != "$SHADOW_APP_DIR/"* ]] ||
  die "Refusing to delete the application directory or its contents."
[[ "$resolved_data_dir" != /mnt/zspace-xzs-backup/* ]] ||
  die "Refusing to delete anything in the NAS backup tree."

if [[ -e "$resolved_data_dir" ]]; then
  rm -rf -- "$resolved_data_dir"
fi
printf 'Explicitly confirmed shadow PostgreSQL data deletion completed: %s\n' "$resolved_data_dir"
