#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

# Default to failure; set to 1 only on successful final make
echo "SUCCESS=0" >> "$GITHUB_ENV"

ccache -M 5G || true
ccache -z || true

export CC="ccache clang"
export CXX="ccache clang++"
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip

cd kernel
mkdir -p out

run_oldconfig() {
  # Non-interactive oldconfig; ignore `yes` SIGPIPE by disabling pipefail.
  set +e
  set +o pipefail
  yes "" 2>/dev/null | make O=out oldconfig
  local rc=$?
  set -o pipefail
  set -e
  return "$rc"
}

# Generate .config
make O=out "${DEFCONFIG}"

# Prevent interactive prompts / EOF on new Kconfig questions
if ! run_oldconfig; then
  echo "SUCCESS=0" >> "$GITHUB_ENV"
  echo "ERROR: oldconfig failed" > error.log
  exit 0
fi

START="$(date +%s)"
if make -j"$(nproc)" O=out LLVM=1 LLVM_IAS=1 2>&1 | tee build.log; then
  echo "SUCCESS=1" >> "$GITHUB_ENV"
else
  echo "SUCCESS=0" >> "$GITHUB_ENV"
  cp -f build.log error.log
fi
END="$(date +%s)"
echo "BUILD_TIME=$((END-START))" >> "$GITHUB_ENV"

KVER="$(make -s kernelversion | tr -d '\n' || true)"
CLANG_VER="$(clang --version | head -n1 | tr -d '\n' || true)"
printf "KERNEL_VERSION=%s\n" "${KVER:-unknown}" >> "$GITHUB_ENV"
printf "CLANG_VERSION=%s\n" "${CLANG_VER:-unknown}" >> "$GITHUB_ENV"

# Ensure logs exist where workflow expects them
mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
cp -f build.log "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true
cp -f error.log "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true

ccache -s || true

# Do not hard-fail here; workflow uses env.SUCCESS for later steps.
exit 0
