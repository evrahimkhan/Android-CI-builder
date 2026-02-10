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

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

printf "SUCCESS=0\n" >> "$GITHUB_ENV"

# Configure ccache with shared constant for maximum cache size
ccache -M "${CCACHE_SIZE}" || printf "Warning: ccache configuration failed, continuing without cache\n" >&2
ccache -z || printf "Warning: ccache zero stats failed, continuing\n" >&2

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
# Use ISO 8601 timestamp for reproducibility, fallback to build start time
export KERNELRELEASE=""
if [[ -z "${KBUILD_BUILD_TIMESTAMP:-}" ]]; then
  export KBUILD_BUILD_TIMESTAMP="$(date -u +'%Y-%m-%d %H:%M:%S')"
fi
export KBUILD_BUILD_USER="android"
export KBUILD_BUILD_HOST="android-build"

# Validate kernel directory exists before changing
if [ ! -d "kernel" ]; then
  printf "ERROR: kernel directory not found\n" >&2
  exit 1
fi
cd kernel

# Validate out directory path
if [ ! -d "out" ]; then
  mkdir -p out || { printf "ERROR: Failed to create out directory\n" >&2; exit 1; }
fi

# Set up log path - write to file AND stdout for GitHub Actions
LOG="${GITHUB_WORKSPACE:-$(pwd)}/kernel/build.log"

run_oldconfig() {
  set +e
  set +o pipefail
  # Use yes "" to auto-answer prompts with defaults, but also redirect stdin to avoid hanging
  yes "" | make O=out oldconfig 2>&1 | tee -a "$LOG" || true
  local rc=${PIPESTATUS[0]:-$?}
  set -o pipefail
  set -e
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
  set +u
  local nethunter_enabled="${NETHUNTER_ENABLED:-false}"
  local nethunter_level="${NETHUNTER_CONFIG_LEVEL:-basic}"
  set -u
  
  # Debug: Show raw values
  printf "DEBUG: NETHUNTER_ENABLED='%s'\n" "$nethunter_enabled"
  printf "DEBUG: NETHUNTER_CONFIG_LEVEL='%s'\n" "$nethunter_level"
  
  # Convert to lowercase for comparison
  nethunter_enabled=$(echo "$nethunter_enabled" | tr '[:upper:]' '[:lower:]')
  
  # Check if enabled (true, 1, yes)
  if [[ "$nethunter_enabled" == "true" ]] || [[ "$nethunter_enabled" == "1" ]] || [[ "$nethunter_enabled" == "yes" ]]; then
    printf "NetHunter configuration ENABLED\n"
  else
    printf "NetHunter configuration disabled (value='%s')\n" "$nethunter_enabled"
    return 0
  fi

  printf "Configuration level: %s\n\n" "$nethunter_level"
  
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

# Final olddefconfig to ensure all configurations are properly set
printf "\n===== [$(date +%Y-%m-%d\ %H:%M:%S)] Running final olddefconfig =====\n"
if ! make O=out olddefconfig 2>&1 | tee -a "$LOG"; then
  printf "Warning: Final olddefconfig failed, trying silentoldconfig...\n" | tee -a "$LOG"
  if ! make O=out silentoldconfig 2>&1 | tee -a "$LOG"; then
    printf "Warning: silentoldconfig failed, using oldconfig with defaults...\n" | tee -a "$LOG"
    yes "" 2>/dev/null | make O=out oldconfig 2>&1 | tee -a "$LOG" || true
  fi
fi


START="$(date +%s)"
if make -j"$(nproc)" O=out LLVM=1 LLVM_IAS=1 2>&1 | tee -a "$LOG"; then
  printf "SUCCESS=1\n" >> "$GITHUB_ENV"
else
  printf "SUCCESS=0\n" >> "$GITHUB_ENV"
  cp -f "$LOG" "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true
fi
END="$(date +%s)"
printf "BUILD_TIME=%s\n" "$((END-START))" >> "$GITHUB_ENV"

KVER="$(make -s kernelversion | tr -d '\n' || true)"
CLANG_VER="$(clang --version | head -n1 | tr -d '\n' || true)"
printf "KERNEL_VERSION=%s\n" "${KVER:-unknown}" >> "$GITHUB_ENV"
printf "CLANG_VERSION=%s\n" "${CLANG_VER:-unknown}" >> "$GITHUB_ENV"

# Create kernel directory and copy logs
mkdir -p "${GITHUB_WORKSPACE}/kernel" 2>/dev/null || {
  printf "ERROR: Failed to create kernel directory\n" >&2
}

# Validate workspace path before using
if [[ -z "${GITHUB_WORKSPACE:-}" ]] || [[ ! "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  printf "ERROR: Invalid GITHUB_WORKSPACE path\n" >&2
fi

# Safely append log with error handling - always ensure logs are captured
if [ -f "$LOG" ] && [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ "$GITHUB_WORKSPACE" =~ ^/ ]] && [[ "$GITHUB_WORKSPACE" != *".."* ]]; then
  # Copy full log to kernel directory for artifact upload
  cp -f "$LOG" "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || printf "Warning: Failed to copy log to build.log\n" >&2
else
  printf "Warning: Could not write to log directory\n" >&2
fi

ccache -s || true
  # Exit based on SUCCESS variable (used by GitHub Actions workflow)
  # Direct script execution will see the correct exit code
  if [[ "${SUCCESS:-0}" == "1" ]]; then
    exit 0
  else
    exit 1
  fi
