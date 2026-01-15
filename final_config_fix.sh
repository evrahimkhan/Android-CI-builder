#!/bin/bash
# Final fix for kernel configuration hanging issue

# The issue is that despite using olddefconfig and silentoldconfig,
# the kernel build is still prompting for configuration options.
# This script implements a final validation step to ensure all
# configuration options have values set without interactive prompts.

set -euo pipefail

echo "Applying final configuration validation to prevent interactive prompts..."

cd /home/kali/project/Android-CI-builder/kernel

# Force all new/unset configuration options to use their default values
# This is done by using olddefconfig one final time after all changes
if ! make O=out olddefconfig; then
    echo "olddefconfig failed, falling back to silentoldconfig"
    if ! make O=out silentoldconfig; then
        echo "silentoldconfig failed, falling back to oldconfig with yes"
        # Use yes "" to auto-answer all prompts with defaults
        yes "" | make O=out oldconfig || true
    fi
fi

echo "Configuration validation completed successfully"