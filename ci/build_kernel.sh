#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"
KSU_NEXT="${2:-false}"

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
  # Exit code is from `make`, not `yes`.
  set +e
  set +o pipefail
  yes "" 2>/dev/null | make O=out oldconfig
  local rc=$?
  set -o pipefail
  set -e
  return "$rc"
}

fail_gracefully() {
  # Keep pipeline behavior: write error.log, keep SUCCESS=0, exit 0 so later steps run
  local msg="${1:-Unknown error}"
  printf '%s\n' "$msg" > error.log
  exit 0
}

# ---------------------------
# Base config
# ---------------------------
make O=out "${DEFCONFIG}"

if ! run_oldconfig; then
  fail_gracefully "ERROR: oldconfig failed"
fi

# ---------------------------
# KernelSU-Next integration + compat
# ---------------------------
if [ "$KSU_NEXT" = "true" ]; then
  echo "KernelSU-Next requested: enabling + compat patches..."

  # scripts/config convenience
  if [ -f scripts/config ]; then
    chmod +x scripts/config || true
  fi

  KSU_KCONFIG="drivers/kernelsu/Kconfig"
  if [ ! -f "$KSU_KCONFIG" ]; then
    fail_gracefully "ERROR: KernelSU-Next selected but ${KSU_KCONFIG} not found."
  fi

  KSU_SYM="$(awk '/^[[:space:]]*config[[:space:]]+/ {print $2; exit}' "$KSU_KCONFIG" 2>/dev/null || true)"
  [ -z "$KSU_SYM" ] && KSU_SYM="KSU"
  echo "Detected KernelSU symbol: CONFIG_${KSU_SYM}"

  # Ensure Kconfig is sourced
  if [ -f Kconfig ] && ! grep -qF 'source "drivers/kernelsu/Kconfig"' Kconfig; then
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> Kconfig
  fi
  if [ -f drivers/Kconfig ] && ! grep -qF 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> drivers/Kconfig
  fi

  # Ensure build rule exists
  if [ -f drivers/Makefile ] && [ -d drivers/kernelsu ] && ! grep -qE 'kernelsu/' drivers/Makefile; then
    printf '\nobj-$(CONFIG_%s) += kernelsu/\n' "$KSU_SYM" >> drivers/Makefile
  fi

  if ! run_oldconfig; then
    fail_gracefully "ERROR: oldconfig after KernelSU wiring failed"
  fi

  # Enable deps + KSU (depends on KPROBES)
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
    fail_gracefully "ERROR: oldconfig after enabling KernelSU failed"
  fi

  # ------------------------------------------------------------
  # Compat patch #0: define TWA_RESUME globally for KernelSU sources
  # ------------------------------------------------------------
  if [ -d include ] && ! grep -Rqs '\bTWA_RESUME\b' include; then
    if [ -f drivers/kernelsu/Makefile ]; then
      if ! grep -q 'KSU_NEXT_CI_COMPAT_TWA_RESUME' drivers/kernelsu/Makefile; then
        {
          echo '# KSU_NEXT_CI_COMPAT_TWA_RESUME: older kernels lack TWA_RESUME; treat as "notify=1"'
          echo 'ccflags-y += -DTWA_RESUME=1'
          echo
        } | cat - drivers/kernelsu/Makefile > drivers/kernelsu/Makefile.tmp
        mv drivers/kernelsu/Makefile.tmp drivers/kernelsu/Makefile
        echo "Applied KernelSU Makefile compat: ccflags-y += -DTWA_RESUME=1"
      fi
    fi
  fi

  # ---- Compat patch #1: allowlist.c header compat (put_task_struct) ----
  if [ -f drivers/kernelsu/allowlist.c ]; then
    python3 - <<'PY'
from pathlib import Path
p = Path("drivers/kernelsu/allowlist.c")
s = p.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_ALLOWLIST"
if marker in s:
    raise SystemExit(0)

compat = r'''
/* KSU_NEXT_CI_COMPAT_ALLOWLIST: CI compatibility for older kernels.
 * Some trees need <linux/sched/task.h> for put_task_struct().
 */
#if defined(__has_include)
# if __has_include(<linux/sched/task.h>)
#  include <linux/sched/task.h>
# elif __has_include(<linux/sched.h>)
#  include <linux/sched.h>
# endif
#else
# include <linux/sched.h>
#endif
'''

lines = s.splitlines(True)
last_inc = -1
for i, line in enumerate(lines[:250]):
    if line.lstrip().startswith("#include"):
        last_inc = i
insert_at = last_inc + 1 if last_inc != -1 else 0
lines.insert(insert_at, compat + "\n")
p.write_text("".join(lines))
print("Applied allowlist.c header compat patch.")
PY
  fi

  # ---- Compat patch #2: sucompat.c (linux/pgtable.h missing) ----
  if [ -f drivers/kernelsu/sucompat.c ]; then
    python3 - <<'PY'
import re
from pathlib import Path

p = Path("drivers/kernelsu/sucompat.c")
s = p.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_PGTABLE"
if marker in s:
    raise SystemExit(0)

block = r'''/* KSU_NEXT_CI_COMPAT_PGTABLE: some kernels lack <linux/pgtable.h> */
#if defined(__has_include)
# if __has_include(<linux/pgtable.h>)
#  include <linux/pgtable.h>
# elif __has_include(<asm/pgtable.h>)
#  include <asm/pgtable.h>
# elif __has_include(<asm/pgtable_types.h>)
#  include <asm/pgtable_types.h>
# else
#  include <linux/mm.h>
# endif
#else
# include <asm/pgtable.h>
#endif
'''

pat = r'^\s*#include\s*<linux/pgtable\.h>\s*$'
s2, n = re.subn(pat, block, s, flags=re.M)

if n == 0:
    lines = s.splitlines(True)
    last_inc = -1
    for i, line in enumerate(lines[:250]):
        if line.lstrip().startswith("#include"):
            last_inc = i
    insert_at = last_inc + 1 if last_inc != -1 else 0
    lines.insert(insert_at, block + "\n")
    s2 = "".join(lines)

p.write_text(s2)
print("Applied sucompat.c pgtable compat patch.")
PY
  fi

  # ---- Compat patch #3: pkg_observer.c (fsnotify API mismatch) ----
  if [ -f drivers/kernelsu/pkg_observer.c ] && [ -f include/linux/fsnotify_backend.h ]; then
    if grep -q 'handle_event' include/linux/fsnotify_backend.h && ! grep -q 'handle_inode_event' include/linux/fsnotify_backend.h; then
      if grep -q '\.handle_inode_event' drivers/kernelsu/pkg_observer.c; then
        python3 - <<'PY'
from pathlib import Path
import re

p = Path("drivers/kernelsu/pkg_observer.c")
s = p.read_text(errors="ignore")

marker = "KSU_NEXT_CI_COMPAT_FSNOTIFY"
if marker not in s:
    wrapper = r'''
/* KSU_NEXT_CI_COMPAT_FSNOTIFY: adapt KernelSU fsnotify code for kernels
 * where fsnotify_ops uses .handle_event (not .handle_inode_event).
 */
#include <linux/fsnotify_backend.h>

static int ksu_handle_inode_event(struct fsnotify_mark *mark, u32 mask,
                                  struct inode *inode, struct inode *dir,
                                  const struct qstr *file_name, u32 cookie);

static int ksu_handle_event(struct fsnotify_group *group,
                            struct inode *inode, u32 mask,
                            const void *data, int data_type,
                            const struct qstr *file_name, u32 cookie,
                            struct fsnotify_iter_info *iter_info)
{
  (void)group; (void)data; (void)data_type; (void)iter_info;
  return ksu_handle_inode_event(NULL, mask, inode, NULL, file_name, cookie);
}
'''
    lines = s.splitlines(True)
    last_inc = -1
    for i, line in enumerate(lines[:250]):
        if line.lstrip().startswith("#include"):
            last_inc = i
    insert_at = last_inc + 1 if last_inc != -1 else 0
    lines.insert(insert_at, wrapper + "\n")
    s = "".join(lines)

s = re.sub(r'\.handle_inode_event\s*=\s*ksu_handle_inode_event',
           '.handle_event = ksu_handle_event', s)

p.write_text(s)
print("Applied pkg_observer.c fsnotify compat patch.")
PY
      fi
    fi
  fi

  # ---- Compat patch #4: seccomp_cache.c (SECCOMP_ARCH_NATIVE_NR missing) ----
  # Older kernels may not define SECCOMP_ARCH_NATIVE_NR; KernelSU uses it for bitmap sizing.
  if [ -f drivers/kernelsu/seccomp_cache.c ] && [ -d include ]; then
    if ! grep -Rqs '\bSECCOMP_ARCH_NATIVE_NR\b' include; then
      python3 - <<'PY'
from pathlib import Path
p = Path("drivers/kernelsu/seccomp_cache.c")
s = p.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_SECCOMP_ARCH_NATIVE_NR"
if marker in s:
    raise SystemExit(0)

compat = r'''
/* KSU_NEXT_CI_COMPAT_SECCOMP_ARCH_NATIVE_NR:
 * Some older/vendor kernels do not define SECCOMP_ARCH_NATIVE_NR.
 * Treat native-arch count as 1 in that case.
 */
#ifndef SECCOMP_ARCH_NATIVE_NR
#define SECCOMP_ARCH_NATIVE_NR 1
#endif
'''

lines = s.splitlines(True)
last_inc = -1
for i, line in enumerate(lines[:200]):
    if line.lstrip().startswith("#include"):
        last_inc = i
insert_at = last_inc + 1 if last_inc != -1 else 0
lines.insert(insert_at, compat + "\n")
p.write_text("".join(lines))
print("Applied seccomp_cache.c SECCOMP_ARCH_NATIVE_NR compat patch.")
PY
    fi
  fi

  # Sanity checks (KSU must be built-in and deps satisfied)
  if ! grep -q '^CONFIG_KPROBES=y' out/.config; then
    fail_gracefully "ERROR: CONFIG_KPROBES is not enabled; KernelSU depends on it."
  fi
  if ! grep -q "^CONFIG_${KSU_SYM}=y" out/.config; then
    fail_gracefully "ERROR: CONFIG_${KSU_SYM} could not be enabled (=y)."
  fi
fi

# ---------------------------
# Build
# ---------------------------
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

ccache -s || true

# Never hard-fail here; the workflow uses env.SUCCESS to decide next steps.
exit 0
