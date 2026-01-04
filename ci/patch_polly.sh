#!/usr/bin/env bash
set -euo pipefail

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

if grep -RIn --include='Makefile*' --include='*.mk' --include='*.make' -- '-polly-' kernel >/dev/null 2>&1; then
  if ! clang -c -x c /dev/null -o /tmp/polly_test.o -polly-reschedule=1 >/dev/null 2>&1; then
    find kernel -type f \( -name 'Makefile' -o -name 'Makefile.*' -o -name '*.mk' -o -name '*.make' \) -print0 \
      | xargs -0 sed -i -E \
        -e 's/[[:space:]]-mllvm[[:space:]]+-polly-[^[:space:]]+//g' \
        -e 's/[[:space:]]-polly-[^[:space:]]+//g'
  fi
fi
