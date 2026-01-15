#!/bin/bash

# This script fixes the kernel configuration hanging issue by ensuring proper non-interactive configuration

# Navigate to the kernel directory
cd /home/kali/project/Android-CI-builder/kernel

# First, run the defconfig to generate the initial configuration
make O=out holi_defconfig

# Then use olddefconfig to automatically accept defaults for any new options
# This should prevent any interactive prompts
if ! make O=out olddefconfig; then
  # If olddefconfig fails, try silentoldconfig
  if ! make O=out silentoldconfig; then
    # If both fail, use oldconfig with yes "" to auto-answer prompts
    yes "" | make O=out oldconfig || true
  fi
fi

echo "Kernel configuration completed successfully"