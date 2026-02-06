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

# Clone to a temporary directory first, then move
# This prevents partial deletion if clone fails
TEMP_KERNEL_DIR="kernel_temp_$$"
if git clone --depth=1 --branch "$BRANCH" --single-branch --tags "$SRC" "$TEMP_KERNEL_DIR"; then
  rm -rf kernel
  mv "$TEMP_KERNEL_DIR" kernel
else
  rm -rf "$TEMP_KERNEL_DIR" 2>/dev/null || true
  printf "ERROR: Git clone failed\n" >&2
  exit 1
fi
