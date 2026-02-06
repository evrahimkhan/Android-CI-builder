#!/usr/bin/env bash
set -euo pipefail

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

# Check if any Makefiles contain Polly flags
if grep -RIn --include='Makefile*' --include='*.mk' --include='*.make' -- '-polly-' kernel >/dev/null 2>&1; then
  printf "Found Polly flags in kernel, attempting to patch...\n"
  # Use secure temporary file creation
  temp_file=$(mktemp) || { printf "ERROR: Could not create temporary file\n" >&2; exit 1; }
  if ! clang -c -x c /dev/null -o "$temp_file" -polly-reschedule=1 >/dev/null 2>&1; then
    # Find and patch files with validation
    while IFS= read -r -d '' file; do
      # Validate path doesn't contain dangerous characters
      if [[ "$file" != *\;* ]] && [[ "$file" != *\|* ]] && [[ "$file" != *\`* ]] && [[ "$file" != \$* ]]; then
        sed -i -E \
          -e 's/[[:space:]]-mllvm[[:space:]]+-polly-[^[:space:]]+//g' \
          -e 's/[[:space:]]-polly-[^[:space:]]+//g' \
          "$file" 2>/dev/null || true
      fi
    done < <(find kernel -maxdepth 5 -type f \( -name 'Makefile' -o -name 'Makefile.*' -o -name '*.mk' -o -name '*.make' \) -print0 2>/dev/null)
  fi
  # Clean up temporary file
  rm -f "$temp_file" 2>/dev/null || true
fi
