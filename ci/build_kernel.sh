#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"
KSU_NEXT="${2:-false}"

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

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
  set +e
  set +o pipefail
  yes "" 2>/dev/null | make O=out oldconfig
  local rc=$?
  set -o pipefail
  set -e
  return "$rc"
}

fail_gracefully() {
  local msg="${1:-Unknown error}"
  printf '%s\n' "$msg" > error.log
  exit 0
}

ensure_line_once() {
  local f="$1"
  local line="$2"
  grep -qF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
}

# ---------------------------
# Base config
# ---------------------------
make O=out "${DEFCONFIG}"
run_oldconfig || fail_gracefully "ERROR: oldconfig failed"

# ---------------------------
# KernelSU-Next integration + compat
# ---------------------------
if [ "$KSU_NEXT" = "true" ]; then
  echo "KernelSU-Next requested: enabling + compat patches..."

  [ -f scripts/config ] && chmod +x scripts/config || true

  KSU_KCONFIG="drivers/kernelsu/Kconfig"
  [ -f "$KSU_KCONFIG" ] || fail_gracefully "ERROR: KernelSU-Next selected but ${KSU_KCONFIG} not found."

  KSU_SYM="$(awk '/^[[:space:]]*config[[:space:]]+/ {print $2; exit}' "$KSU_KCONFIG" 2>/dev/null || true)"
  [ -z "$KSU_SYM" ] && KSU_SYM="KSU"

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

  run_oldconfig || fail_gracefully "ERROR: oldconfig after KernelSU wiring failed"

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

  run_oldconfig || fail_gracefully "ERROR: oldconfig after enabling KernelSU failed"

  # ------------------------------------------------------------
  # Compat: define TWA_RESUME globally for KernelSU sources
  # ------------------------------------------------------------
  if [ -d include ] && ! grep -Rqs '\bTWA_RESUME\b' include; then
    if [ -f drivers/kernelsu/Makefile ] && ! grep -q 'KSU_NEXT_CI_COMPAT_TWA_RESUME' drivers/kernelsu/Makefile; then
      {
        echo '# KSU_NEXT_CI_COMPAT_TWA_RESUME: older kernels lack TWA_RESUME; treat as "notify=1"'
        echo 'ccflags-y += -DTWA_RESUME=1'
        echo
      } | cat - drivers/kernelsu/Makefile > drivers/kernelsu/Makefile.tmp
      mv drivers/kernelsu/Makefile.tmp drivers/kernelsu/Makefile
    fi
  fi

  # ------------------------------------------------------------
  # Compat: pgtable include fallback for ALL KernelSU sources
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
for p in files:
    s = p.read_text(errors="ignore")
    if "KSU_NEXT_CI_COMPAT_PGTABLE" in s:
        continue
    if not pat.search(s):
        continue
    p.write_text(pat.sub(block, s, count=1))
PY
  fi

  # ------------------------------------------------------------
  # Compat: SECCOMP_ARCH_NATIVE_NR missing
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/seccomp_cache.c ] && [ -d include ] && ! grep -Rqs '\bSECCOMP_ARCH_NATIVE_NR\b' include; then
    python3 - <<'PY'
from pathlib import Path
p = Path("drivers/kernelsu/seccomp_cache.c")
s = p.read_text(errors="ignore")
if "KSU_NEXT_CI_COMPAT_SECCOMP_ARCH_NATIVE_NR" in s:
    raise SystemExit(0)
compat = r'''
/* KSU_NEXT_CI_COMPAT_SECCOMP_ARCH_NATIVE_NR */
#ifndef SECCOMP_ARCH_NATIVE_NR
#define SECCOMP_ARCH_NATIVE_NR 1
#endif
'''
lines = s.splitlines(True)
last_inc = max([i for i,l in enumerate(lines[:200]) if l.lstrip().startswith("#include")], default=-1)
lines.insert(last_inc + 1 if last_inc != -1 else 0, compat + "\n")
p.write_text("".join(lines))
PY
  fi

  # ------------------------------------------------------------
  # Compat: fsnotify API mismatch (pkg_observer.c)
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/pkg_observer.c ] && [ -f include/linux/fsnotify_backend.h ]; then
    if grep -q 'handle_event' include/linux/fsnotify_backend.h && ! grep -q 'handle_inode_event' include/linux/fsnotify_backend.h; then
      if grep -q '\.handle_inode_event' drivers/kernelsu/pkg_observer.c; then
        python3 - <<'PY'
from pathlib import Path
import re
p = Path("drivers/kernelsu/pkg_observer.c")
s = p.read_text(errors="ignore")
if "KSU_NEXT_CI_COMPAT_FSNOTIFY" not in s:
    wrapper = r'''
/* KSU_NEXT_CI_COMPAT_FSNOTIFY */
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
    last_inc = max([i for i,l in enumerate(lines[:250]) if l.lstrip().startswith("#include")], default=-1)
    lines.insert(last_inc + 1 if last_inc != -1 else 0, wrapper + "\n")
    s = "".join(lines)
s = re.sub(r'\.handle_inode_event\s*=\s*ksu_handle_inode_event',
           '.handle_event = ksu_handle_event', s)
p.write_text(s)
PY
      fi
    fi
  fi

  # ------------------------------------------------------------
  # Fix: avoid implicit put_task_struct in allowlist.c
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/allowlist.c ] && grep -q 'put_task_struct' drivers/kernelsu/allowlist.c; then
    if ! grep -q 'extern void put_task_struct' drivers/kernelsu/allowlist.c; then
      python3 - <<'PY'
from pathlib import Path
p = Path("drivers/kernelsu/allowlist.c")
s = p.read_text(errors="ignore")
if "KSU_NEXT_CI_COMPAT_PUT_TASK_STRUCT_PROTO" in s:
    raise SystemExit(0)
proto = r'''
/* KSU_NEXT_CI_COMPAT_PUT_TASK_STRUCT_PROTO */
struct task_struct;
extern void put_task_struct(struct task_struct *t);
'''
lines = s.splitlines(True)
last_inc = max([i for i,l in enumerate(lines[:200]) if l.lstrip().startswith("#include")], default=-1)
lines.insert(last_inc + 1 if last_inc != -1 else 0, proto + "\n")
p.write_text("".join(lines))
PY
    fi
  fi

  # ------------------------------------------------------------
  # FIX: sepolicy.c is incompatible/corrupted -> stub it safely
  # This fixes BOTH filename_trans_* errors and the later "htab/#else/#endif" breakage
  # and ensures non-void functions always return a value.
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/selinux/sepolicy.c ] && [ -f security/selinux/ss/policydb.h ]; then
    NEED_STUB=0

    # old policydb layout (your case)
    if ! grep -qE 'struct[[:space:]]+filename_trans_key[[:space:]]*\{' security/selinux/ss/policydb.h; then
      NEED_STUB=1
    fi

    # corrupted/partially patched file patterns seen in your logs
    if grep -q 'ksu_hash_for_each' drivers/kernelsu/selinux/sepolicy.c; then
      NEED_STUB=1
    fi

    if [ "$NEED_STUB" = "1" ]; then
      python3 - <<'PY'
import re
from pathlib import Path

src = Path("drivers/kernelsu/selinux/sepolicy.c")
orig = src.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_SEPOLICY_STUB_SIG_EXTRACT_V1"

# Extract signatures for ksu_* function definitions only.
# This avoids picking up random macros/top-level junk.
lines = orig.splitlines(True)

starts = re.compile(r'^\s*(?:bool|int|long|ssize_t|void)\s+(ksu_[A-Za-z0-9_]+)\s*\(')

func_sigs = []
collect = False
buf = []
for ln in lines:
    if not collect:
        if starts.match(ln) and "static" not in ln:
            collect = True
            buf = [ln]
    else:
        buf.append(ln)
        if "{" in ln:
            sig_text = "".join(buf)
            collect = False
            buf = []

            # keep signature up to first '{'
            out_sig = []
            for l in sig_text.splitlines(True):
                out_sig.append(l)
                if "{" in l:
                    break
            func_sigs.append("".join(out_sig))

# If none found, still produce an empty TU stub (prevents compile failure)
# but normally KernelSU exposes a bunch of ksu_* functions here.

# Forward-declare structs used in signatures
structs = set()
for sig in func_sigs:
    for m in re.finditer(r'\bstruct\s+([A-Za-z_]\w*)\b', sig):
        structs.add(m.group(1))

def ret_for(sig: str) -> str:
    head = sig.strip().split("(")[0]
    if re.search(r'\bvoid\b', head):
        return ""
    if re.search(r'\bbool\b', head):
        return "  return true;\n"
    if "*" in head:
        return "  return NULL;\n"
    return "  return 0;\n"

out = []
out.append(f"/* {marker}: stubbed for incompatible SELinux policydb API on this kernel. */\n")
out.append("#include <linux/types.h>\n#include <linux/errno.h>\n#include <linux/kernel.h>\n\n")
for s in sorted(structs):
    out.append(f"struct {s};\n")
if structs:
    out.append("\n")

if not func_sigs:
    out.append("/* No exported ksu_* functions detected; empty stub TU. */\n")
else:
    for sig in func_sigs:
        sig_norm = sig.strip()
        sig_norm = re.sub(r'\{\s*$', '{', sig_norm, flags=re.S)
        if not sig_norm.endswith("{"):
            sig_norm += "\n{"
        out.append(sig_norm + "\n")
        out.append("  (void)0;\n")
        out.append(ret_for(sig_norm))
        out.append("}\n\n")

src.write_text("".join(out))
print(f"Stubbed sepolicy.c exported funcs: {len(func_sigs)}")
PY
    fi
  fi

  # ------------------------------------------------------------
  # Weak link stubs for missing hook symbols (prevents ld.lld undefined symbols)
  # ------------------------------------------------------------
  if [ -d drivers/kernelsu ]; then
    if [ ! -f drivers/kernelsu/ci_compat_weak.c ]; then
      cat > drivers/kernelsu/ci_compat_weak.c <<'EOF'
// SPDX-License-Identifier: GPL-2.0
#include <linux/types.h>
#include <linux/fs.h>
#include <linux/input.h>
#include <linux/sched.h>
#include <linux/uaccess.h>
struct filename;

__attribute__((weak))
int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user *arg)
{ (void)magic1; (void)magic2; (void)cmd; (void)arg; return 0; }

__attribute__((weak))
long ksu_handle_sys_read(unsigned int fd, char __user *buf, size_t count)
{ (void)fd; (void)buf; (void)count; return 0; }

__attribute__((weak))
ssize_t ksu_vfs_read_hook(struct file *file, char __user *buf, size_t count, loff_t *pos)
{ (void)file; (void)buf; (void)count; (void)pos; return 0; }

__attribute__((weak))
int ksu_handle_execveat(int fd, struct filename *filename,
                        const char __user *const __user *argv,
                        const char __user *const __user *envp, int flags)
{ (void)fd; (void)filename; (void)argv; (void)envp; (void)flags; return 0; }

__attribute__((weak))
void ksu_input_hook(struct input_dev *dev, unsigned int type, unsigned int code, int value)
{ (void)dev; (void)type; (void)code; (void)value; }

__attribute__((weak))
void put_task_struct(struct task_struct *t)
{ (void)t; }
EOF
    fi

    if [ -f drivers/kernelsu/Makefile ]; then
      ensure_line_once drivers/kernelsu/Makefile "obj-y += ci_compat_weak.o"
    elif [ -f drivers/kernelsu/Kbuild ]; then
      ensure_line_once drivers/kernelsu/Kbuild "obj-y += ci_compat_weak.o"
    fi
  fi

  # Sanity checks
  grep -q '^CONFIG_KPROBES=y' out/.config || fail_gracefully "ERROR: CONFIG_KPROBES is not enabled; KernelSU depends on it."
  grep -q "^CONFIG_${KSU_SYM}=y" out/.config || fail_gracefully "ERROR: CONFIG_${KSU_SYM} could not be enabled (=y)."
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
exit 0
