#!/usr/bin/env bash
# Proton Clang setup script for kernel compilation
# Usage: ./ci/setup_proton_clang.sh [git_url] [branch]
# Downloads and sets up Proton Clang toolchain for building Android kernels
set -euo pipefail

# Use canonical path to avoid issues with relative paths in GitHub Actions
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd -P)"
# Fix: If we're inside the Android-CI-builder directory, don't double it
if [[ "$SCRIPT_DIR" == *"Android-CI-builder/Android-CI-builder"* ]]; then
  SCRIPT_DIR="${SCRIPT_DIR/Android-CI-builder\/Android-CI-builder/Android-CI-builder}"
fi

# Source shared validation library
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

PROTON_CLANG_URL="${1:-https://github.com/kdrag0n/proton-clang}"
PROTON_CLANG_BRANCH="${2:-master}"

if ! validate_git_url "$PROTON_CLANG_URL"; then
  printf "ERROR: Invalid Proton Clang URL: %s\n" "$PROTON_CLANG_URL" >&2
  exit 1
fi

if ! validate_branch_name "$PROTON_CLANG_BRANCH"; then
  printf "ERROR: Invalid Proton Clang branch: %s\n" "$PROTON_CLANG_BRANCH" >&2
  exit 1
fi

if [ ! -x clang/bin/clang ]; then
  git clone --depth=1 --branch "$PROTON_CLANG_BRANCH" --single-branch --tags "$PROTON_CLANG_URL" clang || { printf "ERROR: Proton Clang clone failed\n"; exit 1; }
fi
