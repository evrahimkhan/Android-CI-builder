#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# Validate GITHUB_WORKSPACE to prevent path traversal
if ! validate_workspace; then
  exit 1
fi

mkdir -p "${GITHUB_WORKSPACE}/kernel"
LOG="${GITHUB_WORKSPACE}/kernel/build.log"
ERR="${GITHUB_WORKSPACE}/kernel/error.log"

ts() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }

printf "===== [%s] RUN: %s\n" "$(ts)" "$*" | tee -a "$LOG"

  set +e
  # Execute command directly without eval - pass arguments safely
  # Simplified status capture that avoids unbound variable issues
  local rc=0
  "$@" 2>&1 | tee -a "$LOG" || rc=$?
  set -e

if [ "$rc" -ne 0 ]; then
  # Write error message to both log files
  printf "===== [%s] ERROR rc=%s in: %s\n" "$(ts)" "$rc" "$*" | tee -a "$LOG" | tee -a "$ERR" || true
fi

exit "$rc"
