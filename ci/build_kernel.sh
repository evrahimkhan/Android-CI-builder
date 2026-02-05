#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"

# Validate DEFCONFIG parameter to prevent path traversal and command injection
if [[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]] || [[ "$DEFCONFIG" =~ /\* ]] || [[ "$DEFCONFIG" =~ \*/ ]]; then
  echo "ERROR: Invalid defconfig format: $DEFCONFIG" >&2
  exit 1
fi

# Validate GITHUB_WORKSPACE and GITHUB_ENV to prevent path traversal
if [[ ! "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  echo "ERROR: GITHUB_WORKSPACE must be an absolute path: $GITHUB_WORKSPACE" >&2
  exit 1
fi

if [[ "$GITHUB_WORKSPACE" == *".."* ]]; then
  echo "ERROR: GITHUB_WORKSPACE contains invalid characters: $GITHUB_WORKSPACE" >&2
  exit 1
fi

if [[ ! "$GITHUB_ENV" =~ ^/ ]]; then
  echo "ERROR: GITHUB_ENV must be an absolute path: $GITHUB_ENV" >&2
  exit 1
fi

if [[ "$GITHUB_ENV" == *".."* ]]; then
  echo "ERROR: GITHUB_ENV contains invalid characters: $GITHUB_ENV" >&2
  exit 1
fi

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

# Prevent interactive configuration prompts
export KCONFIG_NOTIMESTAMP=1
export KERNELRELEASE=""
export KBUILD_BUILD_TIMESTAMP=""
export KBUILD_BUILD_USER="android"
export KBUILD_BUILD_HOST="android-build"

cd kernel
mkdir -p out

run_oldconfig() {
  set +e
  set +o pipefail
  # Use yes "" to auto-answer prompts with defaults, but also redirect stdin to avoid hanging
  yes "" | make O=out oldconfig 2>/dev/null || true
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
  # Sanitize inputs to prevent command injection
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: Invalid key format: $key" >&2
    return 1
  fi

  # Escape special characters in value to prevent injection
  local sanitized_val
  sanitized_val=$(printf '%s\n' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')

  local tool; tool="$(cfg_tool)"
  if [ -n "$tool" ]; then
    "$tool" --file out/.config --set-str "$key" "$sanitized_val" >/dev/null 2>&1 || true
  else
    if grep -q "^CONFIG_${key}=" out/.config 2>/dev/null; then
      sed -i "s|^CONFIG_${key}=.*|CONFIG_${key}=\"${sanitized_val}\"|" out/.config || true
    else
      printf 'CONFIG_%s="%s"\n' "$key" "$sanitized_val" >> out/.config
    fi
  fi
}

set_kcfg_bool() {
  local key="$1"
  local yn="$2"
  # Sanitize inputs to prevent command injection
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: Invalid key format: $key" >&2
    return 1
  fi

  if [[ ! "$yn" =~ ^[yn]$ ]]; then
    echo "ERROR: Invalid yn value: $yn, must be 'y' or 'n'" >&2
    return 1
  fi

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
  if ! make O=out olddefconfig; then
    # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
    if ! make O=out silentoldconfig; then
      # Fallback to oldconfig with yes "" if both fail
      run_oldconfig || true
    fi
  fi
}

make O=out "$DEFCONFIG"
# Use olddefconfig to automatically accept default values for new config options
if ! make O=out olddefconfig; then
  # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
  if ! make O=out silentoldconfig; then
    # Fallback to oldconfig with yes "" if both fail
    run_oldconfig || { echo "ERROR: oldconfig failed" > error.log; exit 0; }
  fi
fi

# Apply custom kconfig branding if enabled
apply_custom_kconfig_branding

# Apply NetHunter configuration if enabled
apply_nethunter_config() {
  if [ "${NETHUNTER_ENABLED:-false}" != "true" ]; then
    return 0
  fi
  
  echo "Applying NetHunter kernel configuration..."
  
  # Source the NetHunter config script
  if [ -f "${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh" ]; then
    # Export functions so they're available to the sourced script
    export -f set_kcfg_str set_kcfg_bool cfg_tool 2>/dev/null || true
    
    # Change to kernel directory and run the script
    # Kernel is cloned into 'kernel/' subdirectory by ci/clone_kernel.sh
    (
      export KERNEL_DIR="kernel"
      cd "${GITHUB_WORKSPACE}"
      bash "${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh"
    )
  else
    echo "Warning: NetHunter config script not found at ${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh"
    return 0
  fi
  
  # Run olddefconfig to resolve dependencies
  echo "Resolving NetHunter configuration dependencies..."
  # Use separate temp log to avoid race condition with main build
  local nethunter_log="nethunter-config-${$}-$(date +%s).log"
  if ! make O=out olddefconfig 2>&1 | tee -a "$nethunter_log"; then
    if ! make O=out silentoldconfig 2>&1 | tee -a "$nethunter_log"; then
      run_oldconfig || true
    fi
  fi
  
  # Append to main build log and cleanup
  if [ -f "$nethunter_log" ]; then
    cat "$nethunter_log" >> build.log 2>/dev/null || true
    rm -f "$nethunter_log"
  fi
}

apply_nethunter_config

# Run olddefconfig to ensure all new configurations are properly set without interactive prompts
if ! make O=out olddefconfig; then
  # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
  if ! make O=out silentoldconfig; then
    # Fallback to oldconfig with yes "" if both fail
    run_oldconfig || { echo "ERROR: oldconfig failed" > error.log; exit 0; }
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

mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
cat build.log >> "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true
[ -f error.log ] && cat error.log >> "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true

ccache -s || true
exit 0
