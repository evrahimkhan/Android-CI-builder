#!/usr/bin/env bash
set -euo pipefail

# GCC ARM64 Toolchain Setup Script
# Clones GCC ARM64 toolchain for Android kernel building

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

GCC_URL="${1:-https://github.com/mvaisakh/gcc-arm64}"
GCC_BRANCH="${2:-gcc-master}"

# Validate git URL
if ! validate_git_url "$GCC_URL"; then
  printf "ERROR: Invalid GCC URL: %s\n" "$GCC_URL" >&2
  exit 1
fi

# Validate branch name
if ! validate_branch_name "$GCC_BRANCH"; then
  printf "ERROR: Invalid GCC branch: %s\n" "$GCC_BRANCH" >&2
  exit 1
fi

# Check if GCC is already installed
if [ -x gcc/bin/aarch64-linux-gnu-gcc ]; then
  printf "GCC ARM64 toolchain already exists at gcc/bin/aarch64-linux-gnu-gcc\n"
  exit 0
fi

# Clone GCC ARM64 toolchain
printf "Cloning GCC ARM64 toolchain from: %s\n" "$GCC_URL"
printf "Branch: %s\n" "$GCC_BRANCH"

if ! timeout 300 git clone --depth=1 --branch "$GCC_BRANCH" "$GCC_URL" gcc 2>&1; then
  printf "ERROR: GCC ARM64 toolchain clone failed (timeout or network error)\n" >&2
  exit 1
fi

# Verify GCC exists
if [ ! -x gcc/bin/aarch64-linux-gnu-gcc ]; then
  printf "ERROR: GCC not found at gcc/bin/aarch64-linux-gnu-gcc\n" >&2
  exit 1
fi

# Verify GCC version
GCC_VERSION=$(gcc/bin/aarch64-linux-gnu-gcc --version | head -n1)
printf "GCC ARM64 toolchain installed successfully!\n"
printf "Version: %s\n" "$GCC_VERSION"
