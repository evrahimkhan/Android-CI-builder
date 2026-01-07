#!/usr/bin/env bash
set -euo pipefail

if [ -f kernel/out/.config ] && grep -q '^CONFIG_GKI=y' kernel/out/.config; then
  echo "KERNEL_TYPE=GKI" >> "$GITHUB_ENV"
else
  echo "KERNEL_TYPE=NON-GKI" >> "$GITHUB_ENV"
fi
