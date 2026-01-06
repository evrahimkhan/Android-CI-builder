#!/usr/bin/env bash
set -euo pipefail

SRC="${1:?kernel_source required}"
BRANCH="${2:?kernel_branch required}"

rm -rf kernel
git clone --depth=1 -b "$BRANCH" "$SRC" kernel
