#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"
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

cfg_tool() {
  if [ -f scripts/config ]; then
    chmod +x scripts/config || true
    echo "scripts/config"
  else
    echo ""
  fi
}

set_kcfg_str() {
  local key="$1"
  local val="$2"
  local tool; tool="$(cfg_tool)"
  if [ -n "$tool" ]; then
    "$tool" --file out/.config --set-str "$key" "$val" >/dev/null 2>&1 || true
  else
    if grep -q "^CONFIG_${key}=" out/.config 2>/dev/null; then
      sed -i "s|^CONFIG_${key}=.*|CONFIG_${key}=\"${val//\"/\\\"}\"|" out/.config || true
    else
      printf 'CONFIG_%s="%s"\n' "$key" "${val//\"/\\\"}" >> out/.config
    fi
  fi
}

set_kcfg_bool() {
  local key="$1"
  local yn="$2"
  local tool; tool="$(cfg_tool)"
  if [ -n "$tool" ]; then
    if [ "$yn" = "y" ]; then "$tool" --file out/.config -e "$key" >/dev/null 2>&1 || true
    else "$tool" --file out/.config -d "$key" >/dev/null 2>&1 || true
    fi
  else
    if [ "$yn" = "y" ]; then
      sed -i "s|^# CONFIG_${key} is not set|CONFIG_${key}=y|" out/.config 2>/dev/null || true
      grep -q "^CONFIG_${key}=y" out/.config 2>/dev/null || echo "CONFIG_${key}=y" >> out/.config
    else
      sed -i "/^CONFIG_${key}=y$/d;/^CONFIG_${key}=m$/d" out/.config 2>/dev/null || true
      grep -q "^# CONFIG_${key} is not set" out/.config 2>/dev/null || echo "# CONFIG_${key} is not set" >> out/.config
    fi
  fi
}

apply_custom_kconfig_branding() {
  if [ "${CUSTOM_CONFIG_ENABLED:-false}" != "true" ]; then
    return 0
  fi

  local localversion="${CFG_LOCALVERSION:--CI}"
  local hostname="${CFG_DEFAULT_HOSTNAME:-CI Builder}"
  local uname_override="${CFG_UNAME_OVERRIDE_STRING:-}"
  local cc_text_override="${CFG_CC_VERSION_TEXT:-}"

  local clang_ver
  clang_ver="$(clang --version | head -n1 | tr -d '\n' || true)"

  local cc_text="$cc_text_override"
  [ -z "$cc_text" ] && cc_text="$clang_ver"

  set_kcfg_str LOCALVERSION "$localversion"
  set_kcfg_str DEFAULT_HOSTNAME "$hostname"
  set_kcfg_str CC_VERSION_TEXT "$cc_text"
  set_kcfg_str UNAME_OVERRIDE_STRING "$uname_override"

  if [ -n "$uname_override" ]; then
    set_kcfg_bool UNAME_OVERRIDE y
  else
    set_kcfg_bool UNAME_OVERRIDE n
  fi

  set_kcfg_bool LOCALVERSION_AUTO n
  run_oldconfig || true
}

make O=out "$DEFCONFIG"
run_oldconfig || { echo "ERROR: oldconfig failed" > error.log; exit 0; }

apply_custom_kconfig_branding

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

mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
cat build.log >> "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true
[ -f error.log ] && cat error.log >> "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true

ccache -s || true
exit 0
