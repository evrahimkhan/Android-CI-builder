#!/usr/bin/env bash
set -euo pipefail

cd kernel
curl -LSs https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh | bash -
git status --porcelain || true
