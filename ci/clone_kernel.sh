#!/usr/bin/env bash
set -euo pipefail

SRC="${1:?kernel_source required}"
BRANCH="${2:?kernel_branch required}"

# Validate inputs to prevent command injection
if [[ ! "$SRC" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(:[0-9]+)?(/[a-zA-Z0-9._-]+)+\.git$ ]] &&
   [[ ! "$SRC" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(:[0-9]+)?/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.git$ ]] &&
   [[ ! "$SRC" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*@[a-zA-Z0-9][a-zA-Z0-9._-]*:[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.git$ ]] &&
   [[ ! "$SRC" =~ ^git@[a-zA-Z0-9][a-zA-Z0-9._-]*:[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.git$ ]]; then
  echo "ERROR: Invalid git URL format: $SRC" >&2
  exit 1
fi

if [[ ! "$BRANCH" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
  echo "ERROR: Invalid branch name format: $BRANCH" >&2
  exit 1
fi

rm -rf kernel
git clone --depth=1 --branch "$BRANCH" --single-branch --no-tags "$SRC" kernel || { echo "ERROR: Git clone failed"; exit 1; }
