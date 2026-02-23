#!/usr/bin/env bash
set -euo pipefail

# GCC doesn't support Polly (it's LLVM-specific), so this patch is not needed
# Keep the file for reference but skip LLVM-specific checks
export PATH="${GITHUB_WORKSPACE}/gcc/bin:${PATH}"

# Polly is an LLVM optimization pass - not applicable to GCC builds
# This script is kept for compatibility but is now a no-op for GCC
printf "[patch_polly] Using GCC - skipping LLVM Polly patch\n"
