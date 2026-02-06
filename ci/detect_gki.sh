#!/usr/bin/env bash
set -euo pipefail

# Validate GITHUB_ENV to prevent path traversal
if [[ ! "$GITHUB_ENV" =~ ^/ ]]; then
  printf "ERROR: GITHUB_ENV must be an absolute path: %s\n" "$GITHUB_ENV" >&2
  exit 1
fi

if [[ "$GITHUB_ENV" == *".."* ]]; then
  printf "ERROR: GITHUB_ENV contains invalid characters: %s\n" "$GITHUB_ENV" >&2
  exit 1
fi

if [ -f kernel/out/.config ]; then
  if grep -q '^CONFIG_GKI=y' kernel/out/.config; then
    printf "KERNEL_TYPE=GKI\n" >> "$GITHUB_ENV"
  else
    printf "KERNEL_TYPE=NON-GKI\n" >> "$GITHUB_ENV"
  fi
else
  printf "KERNEL_TYPE=UNKNOWN (config not found)\n" >> "$GITHUB_ENV"
fi
