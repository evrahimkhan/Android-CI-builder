#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

SRC="${1:?kernel_source required}"
BRANCH="${2:?kernel_branch required}"

# Validate inputs to prevent command injection
# Only accept HTTPS URLs for security (no HTTP)
if ! validate_git_url "$SRC"; then
  exit 1
fi

if ! validate_branch_name "$BRANCH"; then
  exit 1
fi

rm -rf kernel
git clone --depth=1 --branch "$BRANCH" --single-branch --tags "$SRC" kernel || { printf "ERROR: Git clone failed\n"; exit 1; }
