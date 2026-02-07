#!/usr/bin/env bash
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

SRC="${1:?kernel_source required}"
BRANCH="${2:?kernel_branch required}"
TEMP_KERNEL_DIR="${GITHUB_WORKSPACE:-/tmp}/.kernel_clone_$$"

# Validate inputs to prevent command injection
# Only accept HTTPS URLs for security (no HTTP)
if ! validate_git_url "$SRC"; then
  exit 1
fi

if ! validate_branch_name "$BRANCH"; then
  exit 1
fi

# Validate BRANCH parameter to prevent command injection
# Sanitize branch name to prevent shell injection attacks
if [[ -z "$BRANCH" ]]; then
  printf "ERROR: Branch name cannot be empty\n" >&2
  exit 1
fi

# Additional security validation - prevent branch injection via --config parameter
if [[ "$BRANCH" =~ ^\-+ ]] || [[ "$BRANCH" =~ ^\-\- ]]; then
  printf "ERROR: Branch name contains dangerous flags\n" >&2
  exit 1
fi

# Additional validation - prevent ref/log path injection
if [[ "$BRANCH" =~ ^(\.\./|\.\.\.|\.\.\.) ]] || [[ "$BRANCH" =~ (\;|\&&|\|\|) ]]; then
  printf "ERROR: Branch name contains path traversal characters\n" >&2
  exit 1
fi

# Clean up any previous temp directory
rm -rf "$TEMP_KERNEL_DIR" 2>/dev/null || true

# Use argument array to prevent injection
# Clone with --tags to include tags in the repository
if git clone --depth=1 --branch "${BRANCH}" --single-branch --tags "${SRC}" "${TEMP_KERNEL_DIR}" 2>/dev/null; then
  rm -rf kernel
  mv "$TEMP_KERNEL_DIR" kernel
else
  rm -rf "$TEMP_KERNEL_DIR" 2>/dev/null || true
  printf "ERROR: Git clone failed\n" >&2
  exit 1
fi
