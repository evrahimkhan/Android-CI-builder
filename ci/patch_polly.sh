#!/usr/bin/env bash
set -euo pipefail

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

# Check if any Makefiles contain Polly flags
if grep -RIn --include='Makefile*' --include='*.mk' --include='*.make' -- '-polly-' kernel >/dev/null 2>&1; then
  echo "Found Polly flags in kernel, attempting to patch..."
  # Use secure temporary file creation
  local temp_file
  temp_file=$(mktemp) || { echo "ERROR: Could not create temporary file" >&2; exit 1; }
  if ! clang -c -x c /dev/null -o "$temp_file" -polly-reschedule=1 >/dev/null 2>&1; then
    find kernel -type f \( -name 'Makefile' -o -name 'Makefile.*' -o -name '*.mk' -o -name '*.make' \) -print0 \
      | xargs -0 sed -i -E \
        -e 's/[[:space:]]-mllvm[[:space:]]+-polly-[^[:space:]]+//g' \
        -e 's/[[:space:]]-polly-[^[:space:]]+//g'
  fi
  # Clean up temporary file
  rm -f "$temp_file" 2>/dev/null || true
fi
