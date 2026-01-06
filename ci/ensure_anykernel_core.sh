#!/usr/bin/env bash
set -euo pipefail

test -f anykernel/anykernel.sh || { echo "Missing anykernel/anykernel.sh"; exit 1; }

if [ ! -f anykernel/tools/ak3-core.sh ]; then
  rm -rf anykernel_upstream
  git clone --depth=1 https://github.com/osm0sis/AnyKernel3 anykernel_upstream
  rsync -a --exclude 'anykernel.sh' anykernel_upstream/ anykernel/
  rm -rf anykernel_upstream
fi

chmod 755 anykernel/anykernel.sh || true
