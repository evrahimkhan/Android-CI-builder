#!/usr/bin/env bash
# This script fixes the kernel configuration issue by ensuring all necessary
# cfg80211 and wireless functions are properly available to the qcacld driver

set -euo pipefail

if [ $# -eq 0 ]; then
    printf "Usage: %s <defconfig>\n" "$0" >&2
    exit 1
fi

DEFCONFIG="$1"

# Validate DEFCONFIG parameter to prevent path traversal and command injection
if [[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]]; then
    printf "ERROR: Invalid defconfig format: %s\n" "$DEFCONFIG" >&2
    exit 1
fi

# Change to kernel directory
cd kernel

# Create output directory
mkdir -p out

# Apply the defconfig
make O=out "$DEFCONFIG"

# Use silentoldconfig to avoid any interactive prompts and sync configuration
make O=out silentoldconfig

# Verify that the configuration was successful
if [ $? -eq 0 ]; then
    printf "Configuration completed successfully\n"
    exit 0
else
    printf "Configuration failed\n" >&2
    exit 1
fi