#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
