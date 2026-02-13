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

# Validate GITHUB_ENV to prevent path traversal
if ! validate_github_env; then
  exit 1
fi

# Determine kernel directory
KERNEL_DIR="${KERNEL_DIR:-${GITHUB_WORKSPACE:-.}/kernel}"
CONFIG_FILE="${KERNEL_DIR}/out/.config"

if [ -f "$CONFIG_FILE" ]; then
  # Use grep -F for fixed-string matching to avoid regex issues
  if grep -qF 'CONFIG_GKI=y' "$CONFIG_FILE" 2>/dev/null; then
    printf "KERNEL_TYPE=GKI\n" >> "$GITHUB_ENV"
  elif grep -qF 'CONFIG_GKI=n' "$CONFIG_FILE" 2>/dev/null; then
    printf "KERNEL_TYPE=NON-GKI\n" >> "$GITHUB_ENV"
  else
    printf "KERNEL_TYPE=UNKNOWN (GKI config unreadable)\n" >> "$GITHUB_ENV"
  fi
else
  printf "KERNEL_TYPE=UNKNOWN (config not found at %s)\n" "$CONFIG_FILE" >> "$GITHUB_ENV"
fi
