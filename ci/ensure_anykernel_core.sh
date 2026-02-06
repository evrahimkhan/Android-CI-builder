#!/usr/bin/env bash
set -euo pipefail

# Ensure anykernel directory exists
mkdir -p anykernel

# Clone AnyKernel3 if core files not present
if [ ! -f anykernel/tools/ak3-core.sh ]; then
  rm -rf anykernel_upstream
  git clone --depth=1 https://github.com/osm0sis/AnyKernel3 anykernel_upstream || { echo "ERROR: AnyKernel3 clone failed"; exit 1; }
  
  # Copy upstream files to anykernel/, preserving local anykernel.sh if it exists
  rsync -a --exclude 'anykernel.sh' anykernel_upstream/ anykernel/ || { echo "ERROR: rsync failed"; rm -rf anykernel_upstream; exit 1; }
  
  # If no local anykernel.sh exists, copy from upstream
  if [ ! -f anykernel/anykernel.sh ]; then
    cp anykernel_upstream/anykernel.sh anykernel/anykernel.sh || { echo "ERROR: Failed to copy anykernel.sh"; rm -rf anykernel_upstream; exit 1; }
  fi
  
  rm -rf anykernel_upstream
fi

# Verify anykernel.sh exists after setup
if [ ! -f anykernel/anykernel.sh ]; then
  echo "ERROR: Missing anykernel/anykernel.sh after setup" >&2
  exit 1
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
