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

# Clone directly to final directory, then clean up on failure
# This prevents race condition where rm -rf kernel could leave workspace broken
TEMP_KERNEL_DIR="kernel_temp_$$"
FINAL_KERNEL_DIR="kernel"

# Cleanup function for temp directory
cleanup_temp() {
  if ! rm -rf "$TEMP_KERNEL_DIR" 2>/dev/null; then
    printf "Warning: Failed to clean up temp directory: %s\n" "$TEMP_KERNEL_DIR" >&2
  fi
}

trap cleanup_temp EXIT

# Clone to temporary directory first
if git clone --depth=1 --branch "$BRANCH" "$SRC" "$TEMP_KERNEL_DIR" 2>/dev/null; then
  # Only remove old kernel AFTER successful clone
  rm -rf "$FINAL_KERNEL_DIR"
  mv "$TEMP_KERNEL_DIR" "$FINAL_KERNEL_DIR"
  trap - EXIT
else
  printf "ERROR: Git clone failed\n" >&2
  exit 1
fi
