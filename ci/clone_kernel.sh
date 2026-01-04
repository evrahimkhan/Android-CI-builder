#!/usr/bin/env bash
set -euo pipefail

KERNEL_SOURCE="${1:?kernel_source required}"
KERNEL_BRANCH="${2:?kernel_branch required}"

rm -rf kernel
git clone --depth=1 -b "${KERNEL_BRANCH}" "${KERNEL_SOURCE}" kernel
