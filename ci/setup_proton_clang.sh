#!/usr/bin/env bash
set -euo pipefail

if [ ! -x clang/bin/clang ]; then
  git clone --depth=1 --branch master --single-branch --no-tags https://github.com/kdrag0n/proton-clang clang || { echo "ERROR: Proton Clang clone failed"; exit 1; }
fi
