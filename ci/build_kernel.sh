#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

DEFCONFIG="${1:?defconfig required}"

# Validate DEFCONFIG parameter to prevent path traversal and command injection
if ! validate_defconfig "$DEFCONFIG"; then
  exit 1
fi

# Validate GITHUB_WORKSPACE and GITHUB_ENV to prevent path traversal
if ! validate_workspace; then
  exit 1
fi

if ! validate_github_env; then
  exit 1
fi

# Use GCC instead of Clang (system-installed via apt-get)
# Add /usr/bin to PATH to ensure cross-compiler is found
export PATH="/usr/bin:/bin:${GITHUB_WORKSPACE}/gcc/bin:${PATH}"

# Verify cross-compiler is available
if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
  printf "ERROR: aarch64-linux-gnu-gcc not found in PATH\n" >&2
  printf "PATH: %s\n" "$PATH" >&2
  exit 1
fi

printf "Using cross-compiler: %s\n" "$(which aarch64-linux-gnu-gcc)"

printf "SUCCESS=0\n" >> "$GITHUB_ENV"

# Configure ccache with shared constant for maximum cache size
ccache -M "${CCACHE_SIZE}" || printf "Warning: ccache configuration failed, continuing without cache\n" >&2
ccache -z || printf "Warning: ccache zero stats failed, continuing\n" >&2

# GCC compiler settings for ARM64
export CC="ccache aarch64-linux-gnu-gcc"
export CXX="ccache aarch64-linux-gnu-g++"
export CROSS_COMPILE="aarch64-linux-gnu-"
export LD="aarch64-linux-gnu-ld"
export AR="aarch64-linux-gnu-ar"
export NM="aarch64-linux-gnu-nm"
export OBJCOPY="aarch64-linux-gnu-objcopy"
export OBJDUMP="aarch64-linux-gnu-objdump"
export STRIP="aarch64-linux-gnu-strip"

# Disable treating warnings as errors for GCC compatibility
export KCFLAGS="-Wno-error"

# Disable LLVM-specific linker options for GCC
# LLVM=0 tells kernel to use standard GNU toolchain
export LLVM=0
export LD=aarch64-linux-gnu-ld
export LD_FLAGS=""

# Prevent interactive configuration prompts
export KCONFIG_NOTIMESTAMP=1
# Use ISO 8601 timestamp for reproducibility, fallback to build start time
export KERNELRELEASE=""
if [[ -z "${KBUILD_BUILD_TIMESTAMP:-}" ]]; then
  export KBUILD_BUILD_TIMESTAMP="$(date -u +'%Y-%m-%d %H:%M:%S')"
fi
export KBUILD_BUILD_USER="android"
export KBUILD_BUILD_HOST="android-build"

# Set architecture for cross-compilation
export ARCH="${ARCH:-arm64}"
export SUBARCH="${SUBARCH:-arm64}"

# Set CROSS_COMPILE_COMPAT for 32-bit ARM (VDSO32)
export CROSS_COMPILE_COMPAT="arm-linux-gnueabihf-"

# Set up paths
if [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  BUILD_LOG_PATH="${GITHUB_WORKSPACE}/kernel/build.log"
  cd "${GITHUB_WORKSPACE}" || exit 1
else
  BUILD_LOG_PATH="$(pwd)/kernel/build.log"
fi

# Create log directory
mkdir -p "$(dirname "$BUILD_LOG_PATH")" 2>/dev/null || true

# Change to kernel directory
if [ ! -d "kernel" ]; then
  printf "ERROR: kernel directory not found\n" >&2
  exit 1
fi
cd kernel || exit 1
KERNEL_DIR="$(pwd)"

# Validate out directory
if [ ! -d "out" ]; then
  mkdir -p out || { printf "ERROR: Failed to create out directory\n" >&2; exit 1; }
fi

# Log path
LOG="${BUILD_LOG_PATH}"

run_oldconfig() {
  # Save current pipefail state
  local old_pipefail=$(set +o | grep pipefail)
  set +o pipefail
  
  # Capture exit code properly
  yes "" | make O=out oldconfig 2>&1 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]:-$?}
  
  # Restore pipefail state
  $old_pipefail
  
  return "$rc"
}

cfg_tool() {
  if [ -f scripts/config ]; then
    chmod +x scripts/config || true
    printf "scripts/config\n"
  else
printf "\n"
  fi
}

set_kcfg_str() {
  local key="$1"
  local val="$2"
  # Sanitize inputs to prevent command injection
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    printf "ERROR: Invalid key format: %s\n" "$key" >&2
    return 1
  fi

  # Comprehensive escaping for sed - escape ALL special regex characters and shell metacharacters
  local sanitized_val
  sanitized_val=$(printf '%s\n' "$val" | \
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g; s/;/\\;/g; s/&/\\&/g; s/|/\\|/g; s/</\\</g; s/>/\\>/g; s/(/\\(/g; s/)/\\)/g; s/\[/\\[/g; s/\]/\\]/g; s/{/\\{/g; s/}/\\}/g; s/\*/\\*/g; s/?/\\?/g; s/+/\\+/g; s/\^/\\^/g; s/\./\\./g; s/\//\\\//g')

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
    printf "ERROR: Invalid key format: %s\n" "$key" >&2
    return 1
  fi
  
  if [[ ! "$yn" =~ ^[yn]$ ]]; then
    printf "ERROR: Invalid yn value: %s, must be 'y' or 'n'\n" "$yn" >&2
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
      grep -q "^CONFIG_${key}=y" out/.config 2>/dev/null || printf "CONFIG_%s=y\n" "$key" >> out/.config
    else
      sed -i "/^CONFIG_${key}=y$/d;/^CONFIG_${key}=m$/d" out/.config 2>/dev/null || true
      grep -q "^# CONFIG_${key} is not set" out/.config 2>/dev/null || printf "# CONFIG_%s is not set\n" "$key" >> out/.config
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

  # Get GCC version instead of clang
  local gcc_ver
  gcc_ver="$(aarch64-linux-gnu-gcc --version | head -n1 | tr -d '\n' || true)"

  local cc_text="$cc_text_override"
  [ -z "$cc_text" ] && cc_text="$gcc_ver"

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
  if ! make O=out olddefconfig 2>&1 | tee -a "$LOG"; then
    # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
    if ! make O=out silentoldconfig 2>&1 | tee -a "$LOG"; then
      # Fallback to oldconfig with yes "" if both fail
      yes "" 2>/dev/null | make O=out oldconfig 2>&1 | tee -a "$LOG" || true
    fi
  fi
}

# Apply defconfig with proper error handling to avoid interactive prompts
printf "===== [$(date +%Y-%m-%d\ %H:%M:%S)] Running defconfig: make O=out %s =====\n" "$DEFCONFIG" | tee -a "$LOG"
if ! make O=out "$DEFCONFIG" 2>&1 | tee -a "$LOG"; then
  printf "Warning: Initial defconfig failed, trying olddefconfig...\n" | tee -a "$LOG"
  if ! make O=out olddefconfig 2>&1 | tee -a "$LOG"; then
    printf "Warning: olddefconfig failed, trying silentoldconfig...\n" | tee -a "$LOG"
    if ! make O=out silentoldconfig 2>&1 | tee -a "$LOG"; then
      printf "Warning: silentoldconfig failed, using oldconfig with defaults...\n" | tee -a "$LOG"
      yes "" 2>/dev/null | make O=out oldconfig 2>&1 | tee -a "$LOG" || true
    fi
  fi
fi

# Apply custom kconfig branding if enabled
apply_custom_kconfig_branding

# CRITICAL: Apply NetHunter configuration BEFORE final olddefconfig
# This ensures NetHunter configs are part of the final configuration
apply_nethunter_config() {
  printf "\n"
  printf "==============================================\n"
  printf "Applying NetHunter kernel configuration...\n"
  printf "==============================================\n"
  
  # Temporarily disable nounset to handle potentially unset env vars
  set +u 2>/dev/null
  local nethunter_enabled="${NETHUNTER_ENABLED:-false}"
  local nethunter_level="${NETHUNTER_CONFIG_LEVEL:-basic}"
  local rtl8188eus_enabled="${RTL8188EUS_ENABLED:-false}"
  set -u 2>/dev/null
  
  # Convert to lowercase for comparison
  nethunter_enabled=$(echo "$nethunter_enabled" | tr '[:upper:]' '[:lower:]')
  rtl8188eus_enabled=$(echo "$rtl8188eus_enabled" | tr '[:upper:]' '[:lower:]')
  
  # Check if any config is enabled
  local any_enabled=false
  if [[ "$nethunter_enabled" == "true" ]] || [[ "$nethunter_enabled" == "1" ]] || [[ "$nethunter_enabled" == "yes" ]]; then
    any_enabled=true
    printf "NetHunter configuration ENABLED\n"
  fi
  
  if [[ "$rtl8188eus_enabled" == "true" ]] || [[ "$rtl8188eus_enabled" == "1" ]] || [[ "$rtl8188eus_enabled" == "yes" ]]; then
    any_enabled=true
    printf "RTL8188eu driver ENABLED\n"
  fi
  
  if [ "$any_enabled" = false ]; then
    printf "NetHunter/RTL8188eu configuration disabled (nethunter='%s', rtl8188eus='%s')\n" "$nethunter_enabled" "$rtl8188eus_enabled"
    return 0
  fi

  printf "Configuration level: %s\n\n" "$nethunter_level"
  
  # Export RTL8188EUS_ENABLED so it's available to the config script
  export RTL8188EUS_ENABLED="$rtl8188eus_enabled"
  
  # Source the NetHunter config script
  if [ -f "${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh" ]; then
    # Export functions so they're available to the sourced script
    export -f set_kcfg_str set_kcfg_bool cfg_tool 2>/dev/null || {
      printf "Warning: Function export failed - may indicate bash version incompatibility\n" | tee -a "$LOG"
    }
    bash "${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh" 2>&1 | tee -a "$LOG"
    
    printf "\nResolving NetHunter configuration dependencies...\n" | tee -a "$LOG"
    if ! make O=out olddefconfig 2>&1 | tee -a "$LOG"; then
      if ! make O=out silentoldconfig 2>&1 | tee -a "$LOG"; then
        yes "" 2>/dev/null | make O=out oldconfig 2>&1 | tee -a "$LOG" || true
      fi
    fi
  else
    printf "Warning: NetHunter config script not found at %s/ci/apply_nethunter_config.sh\n" "$GITHUB_WORKSPACE" | tee -a "$LOG"
    return 0
  fi
  
  printf "\n==============================================\n"
  printf "NetHunter configuration applied\n"
  printf "==============================================\n"
}

apply_nethunter_config

# Fix VDSO32 for GCC cross-compilation
# VDSO32 requires special 32-bit toolchain support which may not be available
# This disables VDSO32 for ARM64 builds using GCC
printf "\n===== [$(date +%Y-%m-%d\ %H:%M:%S)] Configuring VDSO for GCC cross-compilation =====\n"
if [ -f "${KERNEL_DIR}/out/.config" ]; then
  # Disable VDSO32 for GCC cross-compilation (use various possible config names)
  printf "Disabling CONFIG_VDSO32 for GCC cross-compilation...\n" | tee -a "$LOG"
  sed -i 's/^CONFIG_VDSO32=.*/# CONFIG_VDSO32 is not set/' "${KERNEL_DIR}/out/.config" 2>/dev/null || true
  sed -i 's/^CONFIG_COMPAT_VDSO=.*/CONFIG_COMPAT_VDSO=n/' "${KERNEL_DIR}/out/.config" 2>/dev/null || true
  # Also set VDSO for the kernel
  echo "CONFIG_VDSO32=y" >> "${KERNEL_DIR}/out/.config" 2>/dev/null || true
  echo "# CONFIG_VDSO32 is not set" >> "${KERNEL_DIR}/out/.config" 2>/dev/null || true
  
  # Disable WERROR (treat warnings as errors) for GCC compatibility
  printf "Disabling CONFIG_WERROR for GCC cross-compilation...\n" | tee -a "$LOG"
  sed -i 's/^CONFIG_WERROR=y/# CONFIG_WERROR is not set/' "${KERNEL_DIR}/out/.config" 2>/dev/null || true
  
  # Disable LD_IS_LLD (LLVM linker) for GCC compatibility
  printf "Disabling CONFIG_LD_IS_LLD for GCC cross-compilation...\n" | tee -a "$LOG"
  sed -i 's/^CONFIG_LD_IS_LLD=y/# CONFIG_LD_IS_LLD is not set/' "${KERNEL_DIR}/out/.config" 2>/dev/null || true
fi

# Final olddefconfig to ensure all configurations are properly set
printf "\n===== [$(date +%Y-%m-%d\ %H:%M:%S)] Running final olddefconfig =====\n"
if ! make O=out LLVM=0 olddefconfig 2>&1 | tee -a "$LOG"; then
  printf "Warning: Final olddefconfig failed, trying silentoldconfig...\n" | tee -a "$LOG"
  if ! make O=out LLVM=0 silentoldconfig 2>&1 | tee -a "$LOG"; then
    printf "Warning: silentoldconfig failed, using oldconfig with defaults...\n" | tee -a "$LOG"
    yes "" 2>/dev/null | make O=out LLVM=0 oldconfig 2>&1 | tee -a "$LOG" || true
  fi
fi


START="$(date +%s)"
# Build with proper exit code capture (pipeto returns tee exit code, not make)
# Using GCC instead of Clang - use LLVM=0 to disable LLVM-specific options
set +o pipefail
make -j"$(nproc)" O=out LLVM=0 2>&1 | tee -a "$LOG"
BUILD_RC=${PIPESTATUS[0]}
set -o pipefail

if [ "$BUILD_RC" -eq 0 ]; then
  SUCCESS=1
  printf "SUCCESS=1\n" >> "$GITHUB_ENV"
else
  SUCCESS=0
  printf "SUCCESS=0\n" >> "$GITHUB_ENV"
  cp -f "$LOG" "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true
fi

# Build RTL8188eus driver as external module (AFTER kernel build)
build_rtl8188eus_driver() {
  set +u 2>/dev/null
  local rtl8188eus_enabled="${RTL8188EUS_ENABLED:-false}"
  set -u 2>/dev/null
  
  rtl8188eus_enabled=$(echo "$rtl8188eus_enabled" | tr '[:upper:]' '[:lower:]')
  
  if [[ "$rtl8188eus_enabled" != "true" ]] && [[ "$rtl8188eus_enabled" != "1" ]] && [[ "$rtl8188eus_enabled" != "yes" ]]; then
    printf "RTL8188eus driver disabled (value='%s')\n" "$rtl8188eus_enabled"
    return 0
  fi
  
  printf "\n"
  printf "==============================================\n"
  printf "Enabling RTL8188eu driver (in-kernel rtl8xxxu)...\n"
  printf "==============================================\n"
  
  if [ -f "${GITHUB_WORKSPACE}/ci/clone_rtl8188eus_driver.sh" ]; then
    bash "${GITHUB_WORKSPACE}/ci/clone_rtl8188eus_driver.sh" 2>&1 | tee -a "$LOG"
  else
    printf "Warning: RTL8188eus driver script not found\n" | tee -a "$LOG"
  fi
  
  printf "\n==============================================\n"
  printf "RTL8188eu driver configuration complete\n"
  printf "==============================================\n"
}

# Build RTL8188eus driver only if kernel build succeeded
if [ "$BUILD_RC" -eq 0 ]; then
  build_rtl8188eus_driver
fi

END="$(date +%s)"
printf "BUILD_TIME=%s\n" "$((END-START))" >> "$GITHUB_ENV"

KVER="$(make -s kernelversion | tr -d '\n' || true)"
GCC_VER="$(aarch64-linux-gnu-gcc --version | head -n1 | tr -d '\n' || true)"
printf "KERNEL_VERSION=%s\n" "${KVER:-unknown}" >> "$GITHUB_ENV"
printf "GCC_VERSION=%s\n" "${GCC_VER:-unknown}" >> "$GITHUB_ENV"

# Ensure kernel directory exists in workspace
if [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
  
  # Ensure the log file exists by copying if needed
  if [ -f "$BUILD_LOG_PATH" ]; then
    # File exists, nothing to do
    true
  elif [ -f "$LOG" ]; then
    # LOG exists at different location, copy it
    cp -f "$LOG" "$BUILD_LOG_PATH" 2>/dev/null || true
  else
    # Create empty log file to avoid missing artifact errors
    touch "$BUILD_LOG_PATH" 2>/dev/null || true
  fi
else
  printf "Warning: GITHUB_WORKSPACE not set, logs may not be captured\n" >&2
fi

ccache -s || true

# Exit based on SUCCESS variable
if [[ "${SUCCESS:-0}" == "1" ]]; then
  exit 0
else
  exit 1
fi
