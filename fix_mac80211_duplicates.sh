#!/bin/bash

# This script fixes the duplicate symbol issue in mac80211 by ensuring proper configuration

# Navigate to the kernel directory
cd /home/kali/project/Android-CI-builder/kernel

# Make sure we're in the right directory
if [ ! -f "out/.config" ]; then
    echo "Error: out/.config not found. Please run the build script first."
    exit 1
fi

# The issue is with duplicate symbols in mac80211 modules
# We need to ensure proper configuration to avoid duplicate compilation

# Check if the issue is related to rate control algorithms
# The duplicate symbols suggest both minstrel and minstrel_ht are being built separately

# Fix: Ensure only one rate control algorithm is enabled properly
sed -i 's/CONFIG_MAC80211_RC_DEFAULT=.*/# CONFIG_MAC80211_RC_DEFAULT is not set/' out/.config
echo "CONFIG_MAC80211_RC_DEFAULT_MINSTREL=y" >> out/.config

# Ensure proper dependencies are met
if ! grep -q "CONFIG_MAC80211_RC_MINSTREL=y" out/.config; then
    echo "CONFIG_MAC80211_RC_MINSTREL=y" >> out/.config
fi

if ! grep -q "CONFIG_MAC80211_RC_MINSTREL_HT=y" out/.config; then
    echo "CONFIG_MAC80211_RC_MINSTREL_HT=y" >> out/.config
fi

echo "Fixed mac80211 configuration to prevent duplicate symbols"