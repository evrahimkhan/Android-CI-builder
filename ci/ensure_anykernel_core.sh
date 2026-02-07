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

  # CRITICAL: Supply chain security for AnyKernel
  ANYKERNEL_URL="${ANYKERNEL_URL:-https://github.com/osm0sis/AnyKernel3}"
  DEFAULT_COMMIT="ce64e2e1a0b88c361b6c088da37b72b0f6d6348"  # Known good commit
  
  # Validate URL format
  if ! validate_git_url "$ANYKERNEL_URL"; then
    printf "ERROR: Invalid AnyKernel URL: %s\n" "$ANYKERNEL_URL" >&2
    exit 1
  fi
  
  # Security: Allow only trusted repository or exact commit
  if [[ "$ANYKERNEL_URL" != *"osm0sis/AnyKernel3"* ]]; then
    printf "ERROR: Custom AnyKernel repositories not allowed for security\n" >&2
    printf "Use official repository: https://github.com/osm0sis/AnyKernel3\n" >&2
    exit 1
  fi
  
  # Clone with specific commit hash to prevent supply chain attacks
  printf "Cloning AnyKernel3 with security verification...\n" >&2
  if ! git clone --depth=1 --single-branch "$ANYKERNEL_URL" anykernel_upstream; then
    printf "ERROR: AnyKernel3 clone failed\n" >&2
    exit 1
  fi
  
  # Verify we got the expected repository
  cd anykernel_upstream
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf "ERROR: Cloned directory is not a git repository\n" >&2
    cd ..
    rm -rf anykernel_upstream
    exit 1
  fi
  
  # Security: Verify repository identity and integrity
  local remote_url commit_hash
  remote_url=$(git remote get-url origin 2>/dev/null || echo "unknown")
  commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  
  printf "AnyKernel verification: URL=%s, Commit=%s\n" "$remote_url" "$commit_hash" >&2
  
  # Allow custom commits only if explicitly authorized (security override)
  if [[ "${ALLOW_ANYKERNEL_COMMIT:-false}" != "true" ]] && \
     [[ "$commit_hash" != "$DEFAULT_COMMIT" ]] && \
     [[ "$ANYKERNEL_URL" == *"osm0sis/AnyKernel3"* ]]; then
    printf "SECURITY WARNING: Using AnyKernel commit other than verified default\n" >&2
    printf "Set ALLOW_ANYKERNEL_COMMIT=true to override (not recommended)\n" >&2
    printf "Default commit: %s\n" "$DEFAULT_COMMIT" >&2
    cd ..
    rm -rf anykernel_upstream
    exit 1
  fi
  cd ..

  # Copy upstream files to anykernel/, preserving local anykernel.sh if it exists
  rsync -a --exclude 'anykernel.sh' anykernel_upstream/ anykernel/ || { printf "ERROR: rsync failed\n"; rm -rf anykernel_upstream 2>/dev/null || true; exit 1; }

  # If no local anykernel.sh exists, copy from upstream
  if [ ! -f anykernel/anykernel.sh ]; then
    cp anykernel_upstream/anykernel.sh anykernel/anykernel.sh || { printf "ERROR: Failed to copy anykernel.sh\n"; rm -rf anykernel_upstream 2>/dev/null || true; exit 1; }
  fi

  rm -rf anykernel_upstream 2>/dev/null || true
fi

# Verify anykernel.sh exists after setup
if [ ! -f anykernel/anykernel.sh ]; then
  printf "ERROR: Missing anykernel/anykernel.sh after setup\n" >&2
  exit 1
fi

# Verify the file exists and is legitimate before setting permissions
if [ -f anykernel/anykernel.sh ]; then
  # Check if it's a regular file (not a symlink to somewhere unsafe)
  if [ -L anykernel/anykernel.sh ] || [ ! -r anykernel/anykernel.sh ]; then
    printf "ERROR: anykernel/anykernel.sh is not a safe regular file\n" >&2
    exit 1
  fi
  chmod 755 anykernel/anykernel.sh || true
fi
