#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update || { echo "ERROR: apt-get update failed"; exit 1; }
sudo apt-get install -y \
  bc bison build-essential ccache curl flex git \
  libelf-dev libssl-dev make python3 rsync unzip wget zip zstd \
  dwarves xz-utils perl || { echo "ERROR: apt-get install failed"; exit 1; }
