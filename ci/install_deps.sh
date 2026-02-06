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
run_apt apt-get install -y \
  bc bison build-essential ccache curl flex git \
  libelf-dev libssl-dev make python3 rsync unzip wget zip zstd \
  dwarves xz-utils perl || { printf "ERROR: apt-get install failed\n"; exit 1; }
