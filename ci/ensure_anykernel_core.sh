#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# Change to repository root to ensure relative paths work
cd "${GITHUB_WORKSPACE:-$(pwd)}"

# Ensure anykernel directory exists
mkdir -p anykernel

# Validate GITHUB_WORKSPACE to prevent path traversal
if ! validate_workspace; then
  exit 1
fi

# Clone AnyKernel3 if core files not present
if [ ! -f anykernel/tools/ak3-core.sh ]; then
  rm -rf anykernel_upstream 2>/dev/null || true

  # Validate AnyKernel URL before cloning
  ANYKERNEL_URL="${ANYKERNEL_URL:-https://github.com/osm0sis/AnyKernel3}"
  if ! validate_git_url "$ANYKERNEL_URL"; then
    printf "ERROR: Invalid AnyKernel URL: %s\n" "$ANYKERNEL_URL" >&2
    exit 1
  fi

  git clone --depth=1 "$ANYKERNEL_URL" anykernel_upstream || { printf "ERROR: AnyKernel3 clone failed\n"; exit 1; }

  # Copy upstream files to anykernel/, preserving local anykernel.sh if it exists
  if ! rsync -a --exclude 'anykernel.sh' anykernel_upstream/ anykernel/; then
    printf "ERROR: rsync failed\n" >&2
    rm -rf anykernel_upstream 2>/dev/null || printf "Warning: Failed to clean up temp directory\n" >&2
    exit 1
  fi

  # If no local anykernel.sh exists, copy from upstream
  if [ ! -f anykernel/anykernel.sh ]; then
    if ! cp anykernel_upstream/anykernel.sh anykernel/anykernel.sh; then
      printf "ERROR: Failed to copy anykernel.sh\n" >&2
      rm -rf anykernel_upstream 2>/dev/null || printf "Warning: Failed to clean up temp directory\n" >&2
      exit 1
    fi
  fi

  if ! rm -rf anykernel_upstream; then
    printf "Warning: Failed to clean up temp directory\n" >&2
  fi
fi

# Verify anykernel.sh exists after setup
if [ ! -f anykernel/anykernel.sh ]; then
  printf "ERROR: Missing anykernel/anykernel.sh after setup\n" >&2
  exit 1
fi

  # Verify the file exists and is legitimate before setting permissions
  if [ -f anykernel/anykernel.sh ]; then
    # Check if it's a regular file (not a symlink to somewhere unsafe)
    if [ -L anykernel/anykernel.sh ]; then
      printf "ERROR: anykernel/anykernel.sh is a symlink, not safe\n" >&2
      exit 1
    fi
    if [ ! -r anykernel/anykernel.sh ]; then
      printf "ERROR: anykernel/anykernel.sh is not readable\n" >&2
      exit 1
    fi
    chmod 755 anykernel/anykernel.sh || log_warn "Failed to set permissions on anykernel.sh"
  fi
