#!/usr/bin/env bash
set -euo pipefail

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

# Check if any Makefiles contain Polly flags using fixed-string search
if grep -RIn --include='Makefile*' --include='*.mk' --include='*.make' -F '-polly-' kernel >/dev/null 2>&1; then
  printf "Found Polly flags in kernel, attempting to patch...\n"
  temp_file=$(mktemp) || { printf "ERROR: Could not create temporary file\n" >&2; exit 1; }
  if ! clang -c -x c /dev/null -o "$temp_file" -polly-reschedule=1 >/dev/null 2>&1; then
    # Find and patch files with validation using positive allowlist for paths
    while IFS= read -r -d '' file; do
      # Validate path is within kernel directory and has safe characters
      if [[ "$file" == kernel/* ]] && [[ "$file" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
        sed -i -E \
          -e 's/[[:space:]]-mllvm[[:space:]]+-polly-[^[:space:]]+//g' \
          -e 's/[[:space:]]-polly-[^[:space:]]+//g' \
          "$file" 2>/dev/null || true
      fi
    done < <(find kernel -maxdepth 5 -type f \( -name 'Makefile' -o -name 'Makefile.*' -o -name '*.mk' -o -name '*.make' \) -print0 2>/dev/null)
  fi
  rm -f "$temp_file" 2>/dev/null || true
fi
