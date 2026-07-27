#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=postgres-ops-common.sh
source "${SCRIPT_DIR}/postgres-ops-common.sh"

if [[ $# -ne 1 ]]; then
  die "Usage: $0 /path/to/verified/xzs-*.dump"
fi
[[ "${XZS_NEON_DR_REFRESH_CONFIRM:-}" == "REFRESH_NEON_DR" ]] ||
  die "Neon DR refresh is destructive. Set XZS_NEON_DR_REFRESH_CONFIRM=REFRESH_NEON_DR."
[[ -n "${NEON_DR_DIRECT_URL:-}" ]] ||
  die "Set NEON_DR_DIRECT_URL to the dedicated Neon DR direct (non-pooled) connection."
[[ "$NEON_DR_DIRECT_URL" != *-pooler.* ]] ||
  die "NEON_DR_DIRECT_URL appears to be pooled; pg_restore must use a direct Neon connection."
[[ "$NEON_DR_DIRECT_URL" == postgresql://* || "$NEON_DR_DIRECT_URL" == postgres://* ]] ||
  die "NEON_DR_DIRECT_URL must be a PostgreSQL URL."

require_command docker
require_command sha256sum
DUMP_FILE="$(realpath "$1")"
verify_dump_archive "$DUMP_FILE"
verify_checksum_sidecar "$DUMP_FILE"

docker run --rm --interactive \
  --env NEON_DR_DIRECT_URL \
  "$POSTGRES_IMAGE" \
  sh -eu -c 'exec pg_restore --dbname="$NEON_DR_DIRECT_URL" --clean --if-exists --no-owner --no-privileges --exit-on-error' \
  <"$DUMP_FILE"

docker run --rm \
  --env NEON_DR_DIRECT_URL \
  "$POSTGRES_IMAGE" \
  sh -eu -c 'exec psql "$NEON_DR_DIRECT_URL" --no-psqlrc --set ON_ERROR_STOP=1 --tuples-only --command "
    SELECT version FROM public.flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1;
    SELECT count(*) FROM public.t_user;
    SELECT count(*) FROM public.t_question;
    SELECT count(*) FROM public.t_exam_paper;
    SELECT count(*) FROM public.t_exam_paper_answer;
    SELECT count(*) FROM public.t_exam_paper_question_customer_answer;
    SELECT count(*) FROM public.t_question_correction_record;
  "' \
  >/dev/null

printf 'Verified backup refreshed to the explicitly confirmed Neon DR target.\n'
