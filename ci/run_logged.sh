#!/usr/bin/env bash
# Run logged script wrapper for CI operations
# Usage: ./ci/run_logged.sh <command> [args...]
# Executes command with comprehensive logging to build.log and error.log
set -euo pipefail

# Use canonical path to avoid issues with relative paths in GitHub Actions
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd -P)"
# Fix: If we're inside the Android-CI-builder directory, don't double it
if [[ "$SCRIPT_DIR" == *"Android-CI-builder/Android-CI-builder"* ]]; then
  SCRIPT_DIR="${SCRIPT_DIR/Android-CI-builder\/Android-CI-builder/Android-CI-builder}"
fi

# Source shared validation library
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
# Safe command execution without eval - pass arguments directly
"$@" 2>&1 | tee -a "$LOG"
rc="${PIPESTATUS[0]}"
set -e

if [ "$rc" -ne 0 ]; then
  {
    printf "===== [%s] ERROR rc=%s in: %s\n" "$(ts)" "$rc" "$*"
  } | tee -a "$LOG" | tee -a "$ERR"
fi

exit "$rc"
