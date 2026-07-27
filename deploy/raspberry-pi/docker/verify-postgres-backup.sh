#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

if [[ $# -ne 1 ]]; then
  die "Usage: $0 /path/to/xzs-*.dump"
fi

require_command docker
require_command sha256sum

DUMP_FILE="$(realpath "$1")"
verify_dump_archive "$DUMP_FILE"
verify_checksum_sidecar "$DUMP_FILE"

MANIFEST_FILE="${DUMP_FILE}.manifest.json"
require_file "$MANIFEST_FILE"
grep -Fq "\"sha256\": \"$(sha256sum "$DUMP_FILE" | awk '{print $1}')\"" "$MANIFEST_FILE" ||
  die "Manifest checksum does not match: $MANIFEST_FILE"

printf 'Backup archive, checksum, and manifest verified: %s\n' "$DUMP_FILE"
