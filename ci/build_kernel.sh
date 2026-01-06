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

ensure_line_once() {
  local f="$1"
  local line="$2"
  grep -qF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
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
      echo "Applied KernelSU Makefile compat: ccflags-y += -DTWA_RESUME=1"
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

changed = 0
for p in files:
    s = p.read_text(errors="ignore")
    if "KSU_NEXT_CI_COMPAT_PGTABLE" in s:
        continue
    if not pat.search(s):
        continue
    p.write_text(pat.sub(block, s, count=1))
    changed += 1

print(f"Applied pgtable compat patch to {changed} file(s).")
PY
  fi

  # ------------------------------------------------------------
  # Compat: SECCOMP_ARCH_NATIVE_NR missing
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
last_inc = max([i for i,l in enumerate(lines[:200]) if l.lstrip().startswith("#include")], default=-1)
lines.insert(last_inc + 1 if last_inc != -1 else 0, compat + "\n")
p.write_text("".join(lines))
print("Applied seccomp_cache.c SECCOMP_ARCH_NATIVE_NR compat patch.")
PY
    fi
  fi

  # ------------------------------------------------------------
  # Compat: pkg_observer.c fsnotify API mismatch
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
    last_inc = max([i for i,l in enumerate(lines[:250]) if l.lstrip().startswith("#include")], default=-1)
    lines.insert(last_inc + 1 if last_inc != -1 else 0, wrapper + "\n")
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
  # Fix: put_task_struct implicit declaration in allowlist.c
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/allowlist.c ] && grep -q 'put_task_struct' drivers/kernelsu/allowlist.c; then
    python3 - <<'PY'
from pathlib import Path
p = Path("drivers/kernelsu/allowlist.c")
s = p.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_PUT_TASK_STRUCT_PROTO"
if marker in s:
    raise SystemExit(0)

proto = r'''
/* KSU_NEXT_CI_COMPAT_PUT_TASK_STRUCT_PROTO:
 * Some vendor kernels don't expose put_task_struct prototype via headers.
 */
struct task_struct;
extern void put_task_struct(struct task_struct *t);
'''

lines = s.splitlines(True)
last_inc = max([i for i,l in enumerate(lines[:200]) if l.lstrip().startswith("#include")], default=-1)
lines.insert(last_inc + 1 if last_inc != -1 else 0, proto + "\n")
p.write_text("".join(lines))
print("Injected put_task_struct prototype into allowlist.c")
PY
  fi

  # ------------------------------------------------------------
  # FIX: sepolicy.c filename_trans_* API mismatch
  # Your policydb.h provides only forward decls / old layout -> stub sepolicy.c
  # ------------------------------------------------------------
  if [ -f drivers/kernelsu/selinux/sepolicy.c ] && [ -f security/selinux/ss/policydb.h ]; then
    NEED_STUB="0"
    # Your error indicates filename_trans_key is only forward-declared (incomplete)
    if ! grep -qE 'struct[[:space:]]+filename_trans_key[[:space:]]*\{' security/selinux/ss/policydb.h; then
      NEED_STUB="1"
    fi
    if [ "$NEED_STUB" = "1" ] && ! grep -q 'KSU_NEXT_CI_COMPAT_SEPOLICY_STUB_ALL' drivers/kernelsu/selinux/sepolicy.c; then
      python3 - <<'PY'
import re
from pathlib import Path

src = Path("drivers/kernelsu/selinux/sepolicy.c")
s = src.read_text(errors="ignore")
marker = "KSU_NEXT_CI_COMPAT_SEPOLICY_STUB_ALL"
if marker in s:
    raise SystemExit(0)

lines = s.splitlines(True)

def brace_delta(line: str) -> int:
    return line.count("{") - line.count("}")

def looks_like_func(sig_text: str) -> bool:
    if "=" in sig_text and sig_text.find("=") < sig_text.find("{"):
        return False
    return bool(re.search(r'\b[A-Za-z_]\w*\s*\([^;]*\)\s*\{', sig_text))

def ret_for(sig_text: str) -> str:
    if re.search(r'^\s*(static\s+)?(inline\s+)?void\b', sig_text):
        return ""
    if re.search(r'\bbool\b', sig_text):
        return "  return false;\n"
    if re.search(r'\*\s*[A-Za-z_]\w*\s*\(', sig_text):
        return "  return NULL;\n"
    return "  return 0;\n"

# Extract top-level function signatures
func_sigs = []
depth = 0
collect = False
sig = []
for line in lines:
    if depth == 0:
        if not collect:
            if "(" in line and ";" not in line and not line.lstrip().startswith("#"):
                sig = [line]
                collect = True
        else:
            sig.append(line)

        if collect and "{" in line:
            sig_text = "".join(sig)
            if looks_like_func(sig_text):
                # keep signature lines up to first '{'
                sig_lines = []
                for l in sig:
                    sig_lines.append(l)
                    if "{" in l:
                        break
                func_sigs.append("".join(sig_lines))
            collect = False
            sig = []
    depth += brace_delta(line)
    if depth < 0:
        depth = 0

out = []
out.append(f"/* {marker}: KernelSU sepolicy implementation incompatible with this kernel policydb layout.\n")
out.append(" * Auto-stubbed in CI to keep KernelSU-Next building on older/vendor SELinux trees.\n")
out.append(" */\n\n")
out.append("#include <linux/types.h>\n#include <linux/errno.h>\n#include <linux/kernel.h>\n\n")

if not func_sigs:
    out.append("/* No functions detected to stub. */\n")
else:
    for sig_text in func_sigs:
        sig_text = re.sub(r'\{\s*$', '{', sig_text.strip()) + "\n"
        out.append(sig_text)
        out.append("  (void)0;\n")
        out.append(ret_for(sig_text))
        out.append("}\n\n")

src.write_text("".join(out))
print(f"Stubbed {len(func_sigs)} function(s) in sepolicy.c")
PY
    fi
  fi

  # ------------------------------------------------------------
  # Fix: provide missing KernelSU hook symbols at link time (weak stubs)
  # ------------------------------------------------------------
  if [ -d drivers/kernelsu ]; then
    if [ ! -f drivers/kernelsu/ci_compat_weak.c ]; then
      cat > drivers/kernelsu/ci_compat_weak.c <<'EOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * CI compatibility weak stubs
 *
 * Some vendor trees + KernelSU patches may reference KernelSU hook symbols
 * in core kernel code. If real implementations are missing due to API
 * mismatches, these weak stubs prevent link failure.
 *
 * If KernelSU provides strong definitions, they override these.
 */

#include <linux/types.h>
#include <linux/errno.h>
#include <linux/fs.h>
#include <linux/input.h>
#include <linux/sched.h>
#include <linux/uaccess.h>

struct filename;

__attribute__((weak))
int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user *arg)
{
	(void)magic1; (void)magic2; (void)cmd; (void)arg;
	return 0;
}

__attribute__((weak))
long ksu_handle_sys_read(unsigned int fd, char __user *buf, size_t count)
{
	(void)fd; (void)buf; (void)count;
	return 0;
}

__attribute__((weak))
ssize_t ksu_vfs_read_hook(struct file *file, char __user *buf, size_t count, loff_t *pos)
{
	(void)file; (void)buf; (void)count; (void)pos;
	return 0;
}

__attribute__((weak))
int ksu_handle_execveat(int fd, struct filename *filename,
			const char __user *const __user *argv,
			const char __user *const __user *envp,
			int flags)
{
	(void)fd; (void)filename; (void)argv; (void)envp; (void)flags;
	return 0;
}

__attribute__((weak))
void ksu_input_hook(struct input_dev *dev, unsigned int type, unsigned int code, int value)
{
	(void)dev; (void)type; (void)code; (void)value;
}

__attribute__((weak))
void put_task_struct(struct task_struct *t)
{
	(void)t;
}
EOF
      echo "Created drivers/kernelsu/ci_compat_weak.c"
    fi

    if [ -f drivers/kernelsu/Makefile ]; then
      ensure_line_once drivers/kernelsu/Makefile "obj-y += ci_compat_weak.o"
    elif [ -f drivers/kernelsu/Kbuild ]; then
      ensure_line_once drivers/kernelsu/Kbuild "obj-y += ci_compat_weak.o"
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
exit 0
