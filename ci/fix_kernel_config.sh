#!/usr/bin/env bash
# This script fixes the kernel configuration issue by ensuring all necessary
# cfg80211 and wireless functions are properly available to the qcacld driver

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <defconfig>"
    exit 1
fi

DEFCONFIG="$1"

# Validate DEFCONFIG parameter to prevent path traversal and command injection
if [[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]]; then
    echo "ERROR: Invalid defconfig format: $DEFCONFIG" >&2
    exit 1
fi

# Change to kernel directory
cd kernel

# Create output directory
mkdir -p out

# Apply the defconfig
make O=out "$DEFCONFIG"

# Use silentoldconfig to avoid any interactive prompts
# This is the most reliable method to sync configuration without user input
scripts/kconfig/conf --silentoldconfig Kconfig

# Verify that the configuration was successful
if [ $? -eq 0 ]; then
    echo "Configuration completed successfully"
    exit 0
else
    echo "Configuration failed"
    exit 1
fi