#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update || { printf "ERROR: apt-get update failed\n"; exit 1; }
sudo apt-get install -y \
  bc bison build-essential ccache curl flex git \
  libelf-dev libssl-dev make python3 rsync unzip wget zip zstd \
  dwarves xz-utils perl || { printf "ERROR: apt-get install failed\n"; exit 1; }
