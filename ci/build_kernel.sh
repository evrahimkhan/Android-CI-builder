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

set_kcfg_str() {
  # set_kcfg_str KEY VALUE
  local key="$1"
  local val="$2"

  if [ -x scripts/config ]; then
    scripts/config --file out/.config --set-str "$key" "$val" >/dev/null 2>&1 || true
  else
    # Fallback: edit .config directly (string configs use quotes)
    if grep -q "^CONFIG_${key}=" out/.config 2>/dev/null; then
      sed -i "s|^CONFIG_${key}=.*|CONFIG_${key}=\"${val//\"/\\\"}\"|" out/.config || true
    else
      printf 'CONFIG_%s="%s"\n' "$key" "${val//\"/\\\"}" >> out/.config
    fi
  fi
}

set_kcfg_bool() {
  # set_kcfg_bool KEY y|n
  local key="$1"
  local yn="$2"
  if [ -x scripts/config ]; then
    if [ "$yn" = "y" ]; then
      scripts/config --file out/.config -e "$key" >/dev/null 2>&1 || true
    else
      scripts/config --file out/.config -d "$key" >/dev/null 2>&1 || true
    fi
  else
    if [ "$yn" = "y" ]; then
      if grep -q "^# CONFIG_${key} is not set" out/.config 2>/dev/null; then
        sed -i "s|^# CONFIG_${key} is not set|CONFIG_${key}=y|" out/.config || true
      elif ! grep -q "^CONFIG_${key}=" out/.config 2>/dev/null; then
        echo "CONFIG_${key}=y" >> out/.config
      fi
    else
      sed -i "/^CONFIG_${key}=y$/d" out/.config 2>/dev/null || true
      if ! grep -q "^# CONFIG_${key} is not set" out/.config 2>/dev/null; then
        echo "# CONFIG_${key} is not set" >> out/.config
      fi
    fi
  fi
}

apply_custom_kconfig_branding() {
  # Controlled by workflow env:
  #   CUSTOM_CONFIG_ENABLED=true|false
  #   CFG_LOCALVERSION (default -CI)
  #   CFG_DEFAULT_HOSTNAME (default "CI Builder")
  #   CFG_UNAME_OVERRIDE_STRING (default "")
  #   CFG_CC_VERSION_TEXT (optional override; else auto)
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
  if [ -z "$cc_text" ]; then
    # "set according to the used one"
    cc_text="$clang_ver"
  fi

  # Set strings (only apply if symbols exist; scripts/config ignores unknown)
  set_kcfg_str LOCALVERSION "$localversion"
  set_kcfg_str DEFAULT_HOSTNAME "$hostname"
  set_kcfg_str CC_VERSION_TEXT "$cc_text"
  set_kcfg_str UNAME_OVERRIDE_STRING "$uname_override"

  # Prefer deterministic uname if user provided an override string:
  if [ -n "$uname_override" ]; then
    set_kcfg_bool UNAME_OVERRIDE y
  else
    set_kcfg_bool UNAME_OVERRIDE n
  fi

  # Avoid extra auto suffixes if supported
  set_kcfg_bool LOCALVERSION_AUTO n

  # Re-resolve config (drop unknowns, apply deps)
  run_oldconfig || true

  echo "Custom Kconfig branding enabled:"
  echo "  CONFIG_LOCALVERSION=\"$localversion\""
  echo "  CONFIG_DEFAULT_HOSTNAME=\"$hostname\""
  echo "  CONFIG_UNAME_OVERRIDE_STRING=\"$uname_override\""
  echo "  CONFIG_CC_VERSION_TEXT=\"$cc_text\""
}

# Generate .config
make O=out "$DEFCONFIG"

# Sync config non-interactively
run_oldconfig || { echo "ERROR: oldconfig failed" > error.log; exit 0; }

# Apply optional branding
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
cp -f build.log "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true
cp -f error.log "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true

ccache -s || true
exit 0
