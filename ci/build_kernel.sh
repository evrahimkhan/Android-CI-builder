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
  set +e
  set +o pipefail
  yes "" 2>/dev/null | make O=out oldconfig
  local rc=$?
  set -o pipefail
  set -e
  return "$rc"
}

fail_gracefully() {
  # Preserve CI flow: write error.log, keep SUCCESS=0, exit 0 so Telegram/artifacts still run
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

  # Enable deps + KSU (KSU depends on KPROBES)
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
    if [ -f drivers/kernelsu/Makefile ] && ! grep -q 'KSU_NEXT_CI_COMPAT_TWA_RESUME' drivers/kernelsu/Makefile; then
      {
        echo '# KSU_NEXT_CI_COMPAT_TWA_RESUME: older kernels lack TWA_RESUME; treat as "notify=1"'
        echo 'ccflags-y += -DTWA_RESUME=1'
        echo
      } | cat - drivers/kernelsu/Makefile > drivers/kernelsu/Makefile.tmp
      mv drivers/kernelsu/Makefile.tmp drivers/kernelsu/Makefile
      echo "Applied KernelSU Makefile compat: ccflags-y += -DTWA_RESUME=1"
    fi
  fi

  # ------------------------------------------------------------
  # Compat patch #1: pgtable include fallback for ALL KernelSU sources
  # Fixes multiple files missing <linux/pgtable.h> on vendor trees
  # ------------------------------------------------------------
  if [ -d drivers/kernelsu ] && [ -d include ] && [ ! -f include/linux/pgtable.h ]; then
    python3 - <<'PY'
import re
from pathlib import Path

root = Path("drivers/kernelsu")
files = list(root.rglob("*.c")) + list(root.rglob("*.h"))

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

pat = re.compile(r'^\s*#include\s*<linux/pgtable\.h>\s*$', re.M)

changed = 0
for p in files:
    s = p.read_text(errors="ignore")
    if "KSU_NEXT_CI_COMPAT_PGTABLE" in s:
        continue
    if not pat.search(s):
        continue
    s2 = pat.sub(block, s, count=1)
    p.write_text(s2)
    changed += 1

print(f"Applied pgtable compat patch to {changed} file(s).")
PY
  fi

  # ------------------------------------------------------------
  # Compat patch #2: seccomp_cache.c (SECCOMP_ARCH_NATIVE_NR missing)
  # ------------------------------------------------------------
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

  # ------------------------------------------------------------
  # Compat patch #3: pkg_observer.c (fsnotify API mismatch)
  # ------------------------------------------------------------
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

  # ------------------------------------------------------------
  # Compat patch #4: sepolicy.c (SELinux filename transition API mismatch)
  # Your kernel's policydb.h lacks fields/types KernelSU expects.
  # We stub ONLY the top-level function(s) that touch filename_trans_* APIs.
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/selinux/sepolicy.c ] && [ -f security/selinux/ss/policydb.h ]; then
    # Heuristic: older policydb.h lacks these newer members/struct layouts
    if ! grep -q 'compat_filename_trans_count' security/selinux/ss/policydb.h; then
      python3 - <<'PY'
from pathlib import Path
import re

p = Path("drivers/kernelsu/selinux/sepolicy.c")
s = p.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_SELINUX_FILENAME_TRANS"

if marker in s:
    raise SystemExit(0)

# Only patch if this file references filename transition internals
tokens = [
    "filename_trans_key",
    "filename_trans_datum",
    "policydb_filenametr_search",
    "compat_filename_trans_count",
    "filenametr_key_params",
]
if not any(t in s for t in tokens):
    raise SystemExit(0)

lines = s.splitlines(True)

def brace_delta(line: str) -> int:
    # naive but works for typical kernel C formatting
    return line.count("{") - line.count("}")

# compute depth_before and depth_after
depth_before = []
depth = 0
for ln in lines:
    depth_before.append(depth)
    depth += brace_delta(ln)

# find all target lines that mention filename transition internals
target_idxs = [i for i, ln in enumerate(lines) if any(t in ln for t in tokens)]

# map each target to a top-level block (depth 0 -> depth 1)
blocks = []
for idx in target_idxs:
    # find nearest previous line that starts a top-level brace block
    start = None
    d = depth_before[idx]
    # We want the enclosing block that began at depth 0
    for i in range(idx, -1, -1):
        if depth_before[i] == 0 and "{" in lines[i]:
            # ensure this line actually increases depth to 1
            if brace_delta(lines[i]) > 0:
                start = i
                break
    if start is None:
        continue

    # find end where we return to depth 0 after leaving this block
    depth = 0
    # recompute from start
    for j in range(start, len(lines)):
        depth += brace_delta(lines[j])
        if depth == 0:
            end = j
            blocks.append((start, end))
            break

# dedupe blocks
blocks = sorted(set(blocks))

def guess_return(sig: str) -> str:
    # crude return-type guess from signature text
    if re.search(r'\bvoid\b', sig):
        return ""
    if re.search(r'\bbool\b', sig):
        return "  return false;\n"
    if re.search(r'\bint\b', sig) or re.search(r'\blong\b', sig) or re.search(r'\bssize_t\b', sig):
        return "  return 0;\n"
    # default: return 0
    return "  return 0;\n"

out = []
i = 0
patched_any = False

for (start, end) in blocks:
    # emit lines up to start
    out.extend(lines[i:start])

    block_text = "".join(lines[start:end+1])
    # only stub blocks that actually contain our tokens
    if not any(t in block_text for t in tokens):
        out.extend(lines[start:end+1])
        i = end + 1
        continue

    # Extract signature up to first '{' in the block
    # Keep the original signature lines so prototypes match
    sig_lines = []
    brace_line_idx = None
    for k in range(start, end+1):
        sig_lines.append(lines[k])
        if "{" in lines[k]:
            brace_line_idx = k
            break

    sig_text = "".join(sig_lines)
    ret = guess_return(sig_text)

    stub = []
    stub.append("/* " + marker + ": kernel SELinux policydb filename transition APIs differ on this tree.\n")
    stub.append(" * Stubbing this helper to keep KernelSU-Next building on older/vendor kernels.\n")
    stub.append(" */\n")
    stub.extend(sig_lines)
    stub.append("  /* unsupported policydb filename transition layout on this kernel */\n")
    stub.append(ret if ret else "")
    stub.append("}\n")

    out.extend(stub)
    patched_any = True
    i = end + 1

# emit remainder
out.extend(lines[i:])

if patched_any:
    p.write_text("".join(out))
    print("Applied sepolicy.c filename transition compat stubs.")
else:
    print("No sepolicy.c blocks needed patching.")
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
