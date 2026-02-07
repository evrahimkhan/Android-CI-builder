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

# Validate GITHUB_ENV to prevent path traversal
if ! validate_github_env; then
  exit 1
fi

if [ -f kernel/out/.config ]; then
  if grep -qE '^CONFIG_GKI=(y|n)' kernel/out/.config 2>/dev/null; then
    if grep -q '^CONFIG_GKI=y' kernel/out/.config; then
      printf "KERNEL_TYPE=GKI\n" >> "$GITHUB_ENV"
    else
      printf "KERNEL_TYPE=NON-GKI\n" >> "$GITHUB_ENV"
    fi
  else
    printf "KERNEL_TYPE=UNKNOWN (GKI config unreadable)\n" >> "$GITHUB_ENV"
  fi
else
  printf "KERNEL_TYPE=UNKNOWN (config not found)\n" >> "$GITHUB_ENV"
fi
