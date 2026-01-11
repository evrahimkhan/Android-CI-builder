#!/usr/bin/env bash
set -euo pipefail

# Validate GITHUB_ENV to prevent path traversal
if [[ ! "$GITHUB_ENV" =~ ^/ ]]; then
  echo "ERROR: GITHUB_ENV must be an absolute path: $GITHUB_ENV" >&2
  exit 1
fi

if [[ "$GITHUB_ENV" == *".."* ]]; then
  echo "ERROR: GITHUB_ENV contains invalid characters: $GITHUB_ENV" >&2
  exit 1
fi

if [ -f kernel/out/.config ] && grep -q '^CONFIG_GKI=y' kernel/out/.config; then
  echo "KERNEL_TYPE=GKI" >> "$GITHUB_ENV"
else
  echo "KERNEL_TYPE=NON-GKI" >> "$GITHUB_ENV"
fi
