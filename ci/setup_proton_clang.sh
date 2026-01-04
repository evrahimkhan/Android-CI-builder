#!/usr/bin/env bash
set -euo pipefail

if [ ! -x clang/bin/clang ]; then
  git clone --depth=1 https://github.com/kdrag0n/proton-clang clang
fi
