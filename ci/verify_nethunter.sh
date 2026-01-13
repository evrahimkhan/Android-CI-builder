#!/usr/bin/env bash
set -euo pipefail

# NetHunter Configuration Verification Script
# This script verifies that NetHunter-specific kernel configurations are properly integrated

NETHUNTER_ENABLED="${1:-false}"

# Validate GITHUB_ENV to prevent path traversal
if [[ ! "$GITHUB_ENV" =~ ^/ ]]; then
  echo "ERROR: GITHUB_ENV must be an absolute path: $GITHUB_ENV" >&2
  exit 1
fi

if [[ "$GITHUB_ENV" == *".."* ]]; then
  echo "ERROR: GITHUB_ENV contains invalid characters: $GITHUB_ENV" >&2
  exit 1
fi

# If NetHunter is not enabled, exit successfully
if [ "$NETHUNTER_ENABLED" != "true" ]; then
  echo "NetHunter not enabled, skipping verification"
  echo "NETHUNTER_INTEGRATION_STATUS=not_enabled" >> "$GITHUB_ENV"
  exit 0
fi

echo "Verifying NetHunter configuration integration..."

# Check if kernel config exists
if [ ! -f "kernel/out/.config" ]; then
  echo "ERROR: Kernel config file not found at kernel/out/.config" >&2
  exit 1
fi

# Check for key NetHunter-related configurations
REQUIRED_CONFIGS=(
  "CONFIG_USB_NET_DRIVERS=y"
  "CONFIG_USB_USBNET=y"
  "CONFIG_CFG80211=m"
  "CONFIG_MAC80211=m"
  "CONFIG_BT=m"
  "CONFIG_NFC=m"
  "CONFIG_OVERLAY_FS=m"
  "CONFIG_FUSE_FS=m"
  "CONFIG_ANDROID_BINDERFS=y"
  "CONFIG_SECURITY_SELINUX=y"
  "CONFIG_NAMESPACES=y"
  "CONFIG_CGROUPS=y"
  "CONFIG_NETFILTER=y"
  "CONFIG_TUN=m"
)

MISSING_CONFIGS=()
for cfg in "${REQUIRED_CONFIGS[@]}"; do
  if ! grep -q "^${cfg}$" kernel/out/.config; then
    # Some configs might be set differently, check for alternatives
    key="${cfg%=*}"
    expected_value="${cfg#*=}"

    # Check if the config exists with any value
    if ! grep -q "^${key}=" kernel/out/.config; then
      MISSING_CONFIGS+=("$cfg")
    elif ! grep -q "^${cfg}$" kernel/out/.config; then
      # Config exists but with different value
      current_val=$(grep "^${key}=" kernel/out/.config | head -n1)
      echo "WARNING: ${key} has value '${current_val}' instead of expected '${cfg}'"
    fi
  fi
done

if [ ${#MISSING_CONFIGS[@]} -gt 0 ]; then
  echo "WARNING: Some expected NetHunter configurations are missing:"
  for cfg in "${MISSING_CONFIGS[@]}"; do
    echo "  - $cfg"
  done
  echo "NETHUNTER_INTEGRATION_STATUS=partial" >> "$GITHUB_ENV"
else
  echo "All expected NetHunter configurations found in kernel config"
  echo "NETHUNTER_INTEGRATION_STATUS=verified" >> "$GITHUB_ENV"
fi

# Also check for some specific NetHunter-related modules in the built kernel
echo "Checking for NetHunter-related modules in built kernel..."
if [ -d "kernel/out" ]; then
  # Look for any signs that security/penetration testing modules were built
  MODULES_FOUND=$(find kernel/out -name "*.ko" -type f | wc -l)
  if [ "$MODULES_FOUND" -gt 0 ]; then
    echo "Found $MODULES_FOUND kernel modules built"
  fi
fi

echo "NetHunter configuration verification completed"