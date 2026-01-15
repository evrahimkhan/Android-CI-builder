#!/bin/bash

# Script to fix duplicate symbol issue in mac80211 minstrel modules
# The issue occurs when both MINSTREL and MINSTREL_HT are built as separate modules
# causing duplicate symbol definitions

set -euo pipefail

echo "Fixing mac80211 minstrel duplicate symbol issue..."

# Navigate to the kernel source directory
cd /home/kali/project/Android-CI-builder/kernel

# Check if the kernel output directory exists
if [ ! -d "out" ]; then
    echo "Error: kernel output directory 'out' not found"
    exit 1
fi

# Check if .config exists
if [ ! -f "out/.config" ]; then
    echo "Error: kernel config file 'out/.config' not found"
    exit 1
fi

echo "Modifying kernel configuration to fix minstrel duplicate symbols..."

# The issue is that both CONFIG_MAC80211_RC_MINSTREL and CONFIG_MAC80211_RC_MINSTREL_HT
# are enabled as modules (or built-in), causing duplicate symbols.
# We need to ensure they're properly coordinated.

# First, let's check the current state
echo "Current minstrel configuration:"
grep -E "CONFIG_MAC80211_RC_MINSTREL" out/.config || echo "No minstrel configs found in current config"

# Fix the duplicate symbol issue by coordinating minstrel configurations
# If both are enabled, we need to handle them properly

# Option 1: Disable the standalone minstrel if HT is enabled (recommended)
sed -i 's/^CONFIG_MAC80211_RC_MINSTREL=m/# CONFIG_MAC80211_RC_MINSTREL is not set/' out/.config
sed -i 's/^CONFIG_MAC80211_RC_MINSTREL=y/# CONFIG_MAC80211_RC_MINSTREL is not set/' out/.config

# Or if we want to keep minstrel but not the HT version:
# sed -i 's/^CONFIG_MAC80211_RC_MINSTREL_HT=m/# CONFIG_MAC80211_RC_MINSTREL_HT is not set/' out/.config
# sed -i 's/^CONFIG_MAC80211_RC_MINSTREL_HT=y/# CONFIG_MAC80211_RC_MINSTREL_HT is not set/' out/.config

# Ensure minstrel_ht is enabled as module or built-in
if ! grep -q "^CONFIG_MAC80211_RC_MINSTREL_HT=" out/.config; then
    echo "# Minstrel HT rate control (to avoid duplicate symbols with base minstrel)" >> out/.config
    echo "CONFIG_MAC80211_RC_MINSTREL_HT=m" >> out/.config
fi

# Also ensure the default rate control is properly set
sed -i 's/^CONFIG_MAC80211_RC_DEFAULT=.*/# CONFIG_MAC80211_RC_DEFAULT is not set/' out/.config
echo "CONFIG_MAC80211_RC_DEFAULT=\"minstrel_ht\"" >> out/.config

echo "Minstrel configuration fixed to prevent duplicate symbols."

# Run olddefconfig to ensure all dependencies are properly resolved
echo "Running olddefconfig to resolve dependencies..."
make O=out olddefconfig

echo "Configuration fix completed successfully!"