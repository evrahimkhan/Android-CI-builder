#!/usr/bin/env bash
set -euo pipefail

# Determine if sudo is available and works
USE_SUDO=false
if command -v sudo &>/dev/null; then
  if sudo -n true 2>/dev/null; then
    USE_SUDO=true
  fi
fi

# Function to run apt-get with or without sudo
run_apt() {
  if [ "$USE_SUDO" == "true" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

run_apt apt-get update || { printf "ERROR: apt-get update failed\n"; exit 1; }

# Install packages in groups for better error isolation
# Using --no-install-recommends for faster, cleaner installs
CORE_PACKAGES="bc bison build-essential ccache curl flex git"
KERNEL_PACKAGES="libelf-dev libssl-dev make python3 rsync"
EXTRA_PACKAGES="unzip wget zip zstd dwarves xz-utils perl"

for pkg_group in "$CORE_PACKAGES" "$KERNEL_PACKAGES" "$EXTRA_PACKAGES"; do
  run_apt apt-get install -y --no-install-recommends "$pkg_group" || {
    printf "ERROR: Failed to install packages: %s\n" "$pkg_group" >&2
    exit 1
  }
done
