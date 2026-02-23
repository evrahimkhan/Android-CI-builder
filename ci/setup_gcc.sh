#!/usr/bin/env bash
set -euo pipefail

# GCC ARM64 Toolchain Setup Script
# Clones GCC ARM64 toolchain for Android kernel building

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# Default GCC ARM64 toolchain - using rakeshraimca GCC 7.5
GCC_URL="${1:-https://github.com/rakeshraimca/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-7.5.0}"
GCC_BRANCH="${2:-9.0}"

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

# Check if GCC is already installed (check multiple possible locations)
for gcc_bin in gcc/bin/aarch64-linux-gnu-gcc gcc/bin/aarch64-linux-android-gcc gcc/bin/aarch64-elf-gcc; do
  if [ -x "$gcc_bin" ]; then
    printf "GCC ARM64 toolchain already exists at %s\n" "$gcc_bin"
    exit 0
  fi
done

# Clone GCC ARM64 toolchain
printf "Cloning GCC ARM64 toolchain from: %s\n" "$GCC_URL"
printf "Branch: %s\n" "$GCC_BRANCH"

if ! timeout 300 git clone --depth=1 --branch "$GCC_BRANCH" "$GCC_URL" gcc 2>&1; then
  printf "ERROR: GCC ARM64 toolchain clone failed (timeout or network error)\n" >&2
  exit 1
fi

# Verify GCC exists (check multiple possible names)
for gcc_bin in gcc/bin/aarch64-linux-gnu-gcc gcc/bin/aarch64-linux-android-gcc gcc/bin/aarch64-elf-gcc; do
  if [ -x "$gcc_bin" ]; then
    # Verify GCC version
    GCC_VERSION=$("$gcc_bin" --version | head -n1)
    printf "GCC ARM64 toolchain installed successfully!\n"
    printf "Version: %s\n" "$GCC_VERSION"
    printf "Location: %s\n" "$gcc_bin"
    exit 0
  fi
done

printf "ERROR: GCC not found in expected locations\n" >&2
ls -la gcc/bin/ || true
exit 1
