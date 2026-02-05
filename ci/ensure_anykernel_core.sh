#!/usr/bin/env bash
set -euo pipefail

test -f anykernel/anykernel.sh || { echo "Missing anykernel/anykernel.sh"; exit 1; }

if [ ! -f anykernel/tools/ak3-core.sh ]; then
  rm -rf anykernel_upstream
  git clone --depth=1 https://github.com/osm0sis/AnyKernel3 anykernel_upstream || { echo "ERROR: AnyKernel3 clone failed"; exit 1; }
  rsync -a --exclude 'anykernel.sh' anykernel_upstream/ anykernel/ || { echo "ERROR: rsync failed"; rm -rf anykernel_upstream; exit 1; }
  rm -rf anykernel_upstream
fi

# Verify the file exists and is legitimate before setting permissions
if [ -f anykernel/anykernel.sh ]; then
  # Check if it's a regular file (not a symlink to somewhere unsafe)
  if [ -L anykernel/anykernel.sh ] || [ ! -r anykernel/anykernel.sh ]; then
    echo "ERROR: anykernel/anykernel.sh is not a safe regular file" >&2
    exit 1
  fi
  chmod 755 anykernel/anykernel.sh || true
fi
