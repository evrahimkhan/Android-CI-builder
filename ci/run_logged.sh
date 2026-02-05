#!/usr/bin/env bash
set -euo pipefail

# Validate GITHUB_WORKSPACE to prevent path traversal
if [[ ! "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  echo "ERROR: GITHUB_WORKSPACE must be an absolute path: $GITHUB_WORKSPACE" >&2
  exit 1
fi

# Prevent directory traversal in the path
if [[ "$GITHUB_WORKSPACE" == *".."* ]]; then
  echo "ERROR: GITHUB_WORKSPACE contains invalid characters: $GITHUB_WORKSPACE" >&2
  exit 1
fi

mkdir -p "${GITHUB_WORKSPACE}/kernel"
LOG="${GITHUB_WORKSPACE}/kernel/build.log"
ERR="${GITHUB_WORKSPACE}/kernel/error.log"

ts() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }

echo "===== [$(ts)] RUN: $*" | tee -a "$LOG"

set +e
(eval "$@") 2>&1 | tee -a "$LOG"
rc="${PIPESTATUS[0]}"
set -e

if [ "$rc" -ne 0 ]; then
  {
    echo "===== [$(ts)] ERROR rc=${rc} in: $*"
  } | tee -a "$LOG" | tee -a "$ERR" >/dev/null
fi

exit "$rc"
