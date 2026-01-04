#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"
KSU_NEXT="${2:-false}"

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

# Default to failure; we set SUCCESS=1 only at the end.
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
  # Non-interactive oldconfig, ignore `yes` SIGPIPE by disabling pipefail
  set +e
  set +o pipefail
  yes "" 2>/dev/null | make O=out oldconfig
  rc=$?
  set -o pipefail
  set -e
  return "$rc"
}

make O=out "${DEFCONFIG}"

if ! run_oldconfig; then
  echo "ERROR: oldconfig failed" > error.log
  cp -f error.log kernel/error.log 2>/dev/null || true
  exit 0
fi

if [ "${KSU_NEXT}" = "true" ]; then
  echo "KernelSU-Next requested: enabling + compat patches..."

  [ -f scripts/config ] && chmod +x scripts/config || true

  KSU_KCONFIG="drivers/kernelsu/Kconfig"
  if [ ! -f "$KSU_KCONFIG" ]; then
    echo "ERROR: KernelSU-Next selected but ${KSU_KCONFIG} not found." > error.log
    cp -f error.log kernel/error.log 2>/dev/null || true
    exit 0
  fi

  KSU_SYM="$(awk '/^[[:space:]]*config[[:space:]]+/ {print $2; exit}' "$KSU_KCONFIG" 2>/dev/null || true)"
  [ -z "$KSU_SYM" ] && KSU_SYM="KSU"

  # Wire Kconfig
  if [ -f Kconfig ] && ! grep -qF 'source "drivers/kernelsu/Kconfig"' Kconfig; then
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> Kconfig
  fi
  if [ -f drivers/Kconfig ] && ! grep -qF 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> drivers/Kconfig
  fi

  # Wire Makefile
  if [ -f drivers/Makefile ] && [ -d drivers/kernelsu ] && ! grep -qE 'kernelsu/' drivers/Makefile; then
    printf '\nobj-$(CONFIG_%s) += kernelsu/\n' "$KSU_SYM" >> drivers/Makefile
  fi

  if ! run_oldconfig; then
    echo "ERROR: oldconfig after KernelSU wiring failed" > error.log
    exit 0
  fi

  # Enable deps + KSU
  if [ -f scripts/config ]; then
    ./scripts/config --file out/.config -e KPROBES || true
    ./scripts/config --file out/.config -e KALLSYMS || true
    ./scripts/config --file out/.config -e KALLSYMS_ALL || true
    ./scripts/config --file out/.config -e "${KSU_SYM}" || true
  else
    echo "CONFIG_KPROBES=y" >> out/.config
    echo "CONFIG_KALLSYMS=y" >> out/.config
    echo "CONFIG_KALLSYMS_ALL=y" >> out/.config
    echo "CONFIG_${KSU_SYM}=y" >> out/.config
  fi

  if ! run_oldconfig; then
    echo "ERROR: oldconfig after enabling KernelSU failed" > error.log
    exit 0
  fi

  # Compat patch: allowlist.c (TWA_RESUME + put_task_struct header)
  if [ -f drivers/kernelsu/allowlist.c ] && ! grep -q 'KSU_NEXT_CI_COMPAT_ALLOWLIST' drivers/kernelsu/allowlist.c; then
    perl -0777 -i -pe '
      BEGIN {
        $p = "/* KSU_NEXT_CI_COMPAT_ALLOWLIST: CI compatibility for older kernels. */\n".
             "#ifndef TWA_RESUME\n#define TWA_RESUME 1\n#endif\n\n".
             "#if defined(__has_include)\n".
             "# if __has_include(<linux/sched/task.h>)\n#  include <linux/sched/task.h>\n".
             "# elif __has_include(<linux/sched.h>)\n#  include <linux/sched.h>\n# endif\n".
             "#else\n# include <linux/sched.h>\n#endif\n\n";
      }
      $_ = $p . $_;
    ' drivers/kernelsu/allowlist.c
  fi

  # Compat patch: sucompat.c (linux/pgtable.h missing)
  if [ -f drivers/kernelsu/sucompat.c ] && ! grep -q 'KSU_NEXT_CI_COMPAT_PGTABLE' drivers/kernelsu/sucompat.c; then
    perl -0777 -i -pe '
      my $blk =
"/* KSU_NEXT_CI_COMPAT_PGTABLE: some kernels lack <linux/pgtable.h> */\n".
"#if defined(__has_include)\n".
"# if __has_include(<linux/pgtable.h>)\n#  include <linux/pgtable.h>\n".
"# elif __has_include(<asm/pgtable.h>)\n#  include <asm/pgtable.h>\n".
"# elif __has_include(<asm/pgtable_types.h>)\n#  include <asm/pgtable_types.h>\n".
"# else\n#  include <linux/mm.h>\n# endif\n".
"#else\n# include <asm/pgtable.h>\n#endif\n";
      if (s{^\s*#include\s*<linux/pgtable\.h>\s*$}{$blk}m) { }
      else { $_ = $blk . "\n" . $_; }
    ' drivers/kernelsu/sucompat.c
  fi

  # Final sanity checks
  if ! grep -q '^CONFIG_KPROBES=y' out/.config; then
    echo "ERROR: CONFIG_KPROBES is not enabled; KernelSU depends on it." > error.log
    exit 0
  fi
  if ! grep -q "^CONFIG_${KSU_SYM}=y" out/.config; then
    echo "ERROR: CONFIG_${KSU_SYM} could not be enabled (=y)." > error.log
    exit 0
  fi
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

# Make sure logs exist where later steps expect them
mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
cp -f build.log "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true
cp -f error.log "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true

ccache -s || true
exit 0
