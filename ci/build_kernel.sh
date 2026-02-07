#!/usr/bin/env bash
set -euo pipefail

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi
if [[ -f "${SCRIPT_DIR}/lib/atomic_ops.sh" ]]; then
  source "${SCRIPT_DIR}/lib/atomic_ops.sh"
fi

# CRITICAL: Cleanup handler to prevent resource leaks on script interruption
CLEANUP_FILES=()
cleanup_handler() {
  printf "\n[build_kernel] Cleanup triggered by signal\n" >&2
  
  # Remove all tracked temporary files
  for file in "${CLEANUP_FILES[@]}"; do
    if [ -f "$file" ]; then
      rm -f "$file" 2>/dev/null || true
    fi
  done
  
  # Release GITHUB_ENV lock if we hold it
  if [ -f "${GITHUB_ENV}.lock" ] && [ "$(cat "${GITHUB_ENV}.lock" 2>/dev/null)" = "$$" ]; then
    rm -f "${GITHUB_ENV}.lock" 2>/dev/null || true
  fi
  
  # Kill any child processes
  if [ -n "$(jobs -p)" ]; then
    jobs -p | xargs -r kill 2>/dev/null || true
  fi
  
  exit 130  # SIGINT exit code
}

# Register cleanup for common signals
trap cleanup_handler EXIT
trap cleanup_handler INT
trap cleanup_handler TERM
trap cleanup_handler HUP

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

# Initialize SUCCESS with atomic operation
atomic_write_env "$GITHUB_ENV" "SUCCESS" "0"

# Configure ccache with shared constant and available space check
# Ensure we have enough disk space before setting cache size
local available_space
available_space=$(df "${GITHUB_WORKSPACE:-/tmp}" | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")

# Convert CCACHE_SIZE to bytes for comparison (5G = 5*1024*1024 KB)
local cache_size_kb
case "${CCACHE_SIZE}" in
  *G) cache_size_kb=$((${CCACHE_SIZE%G} * 1024 * 1024)) ;;
  *M) cache_size_kb=$((${CCACHE_SIZE%M} * 1024)) ;;
  *K) cache_size_kb=${CCACHE_SIZE%K} ;;
  *) cache_size_kb=$((5 * 1024 * 1024)) ;;  # Default to 5G
esac

# Only set cache if we have at least 2x the cache size in available space
if [ "$available_space" -gt $((cache_size_kb * 2)) ]; then
  ccache -M "${CCACHE_SIZE}" || printf "Warning: ccache configuration failed, continuing without cache\n" >&2
else
  # Use smaller cache if space is limited
  local reduced_cache="$((available_space / 4))K"
  printf "Warning: Limited disk space, reducing ccache to %s\n" "$reduced_cache" >&2
  ccache -M "$reduced_cache" || printf "Warning: ccache configuration failed, continuing without cache\n" >&2
fi
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
export KERNELRELEASE=""
export KBUILD_BUILD_TIMESTAMP=""
export KBUILD_BUILD_USER="android"
export KBUILD_BUILD_HOST="android-build"

cd kernel
mkdir -p out

# Set up log path (use LOG for consistency with run_logged.sh)
LOG="${GITHUB_WORKSPACE:-$(pwd)}/kernel/build.log"

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
  if ! make O=out olddefconfig; then
    # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
    if ! make O=out silentoldconfig; then
      # Fallback to oldconfig with yes "" if both fail
      run_oldconfig || true
    fi
  fi
}

# Apply defconfig with proper error handling to avoid interactive prompts
printf "===== [$(date +%Y-%m-%d\ %H:%M:%S)] Running defconfig: make O=out %s =====\n" "$DEFCONFIG" | tee -a "$LOG"
if ! make O=out "$DEFCONFIG" 2>&1 | tee -a "$LOG"; then
  printf "Warning: Initial defconfig failed, trying olddefconfig...\n"
  if ! make O=out olddefconfig 2>&1 | tee -a "$LOG"; then
    printf "Warning: olddefconfig failed, trying silentoldconfig...\n"
    if ! make O=out silentoldconfig 2>&1 | tee -a "$LOG"; then
      printf "Warning: silentoldconfig failed, using oldconfig with defaults...\n"
      yes "" 2>/dev/null | run_oldconfig 2>&1 | tee -a "$LOG" || true
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
  
  if [ "${NETHUNTER_ENABLED:-false}" != "true" ]; then
    printf "NetHunter configuration disabled (set NETHUNTER_ENABLED=true to enable)\n"
    return 0
  fi

  printf "Configuration level: %s\n\n" "${NETHUNTER_CONFIG_LEVEL:-basic}"
  
  # Source the NetHunter config script
  if [ -f "${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh" ]; then
    # Use secure temporary file to avoid race conditions
    local nethunter_log
    nethunter_log=$(mktemp -t nethunter-config-XXXXXX.log) || {
      printf "ERROR: Failed to create secure temporary file for NetHunter log\n" >&2
      exit 1
    }
    
    # Track for cleanup
    CLEANUP_FILES+=("$nethunter_log")
    # Source functions locally instead of global export to prevent security boundary violations
    # Functions will be available through shared context, not global namespace
    # This prevents cross-script contamination and maintains encapsulation
    if ! bash "${GITHUB_WORKSPACE}/ci/apply_nethunter_config.sh" 2>&1 | tee -a "$nethunter_log"; then
      printf "Warning: NetHunter config script execution had issues\n" >&2
    fi
    
    printf "\nResolving NetHunter configuration dependencies...\n"
    if ! make O=out olddefconfig 2>&1 | tee -a "$nethunter_log"; then
      if ! make O=out silentoldconfig 2>&1 | tee -a "$nethunter_log"; then
        yes "" 2>/dev/null | make O=out oldconfig 2>&1 | tee -a "$nethunter_log" || true
      fi
    fi
    
    # CRITICAL SECURITY: Sanitize log content before appending to prevent RCE via Telegram
    # Malicious kernel source could inject arbitrary content into logs that get sent via notifications
    if [ -f "$nethunter_log" ]; then
      # Create sanitized version with dangerous characters removed
      local sanitized_log
      sanitized_log=$(mktemp -t nethunter-sanitized-XXXXXX.log) || {
        printf "ERROR: Failed to create sanitized log file\n" >&2
        rm -f "$nethunter_log"
        return 1
      }
      
      # Sanitize content: remove control chars, limit line length, escape special chars
      sed -e 's/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g' \
          -e 's/[^\x20-\x7E]/?/g' \
          -e 's/^\(.\{200\}\).*$/\1.../' \
          "$nethunter_log" > "$sanitized_log" 2>/dev/null || {
        printf "ERROR: Failed to sanitize NetHunter log\n" >&2
        rm -f "$nethunter_log" "$sanitized_log"
        return 1
      }
      
      # Only append sanitized content to main log
      cat "$sanitized_log" >> "$LOG" 2>/dev/null || true
      
      # Cleanup both files
      rm -f "$nethunter_log" "$sanitized_log"
    fi
  else
    printf "Warning: NetHunter config script not found at %s/ci/apply_nethunter_config.sh\n" "$GITHUB_WORKSPACE"
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
  printf "Warning: Final olddefconfig failed, trying silentoldconfig...\n"
  if ! make O=out silentoldconfig 2>&1 | tee -a "$LOG"; then
    printf "Warning: silentoldconfig failed, using oldconfig with defaults...\n"
    yes "" 2>/dev/null | make O=out oldconfig 2>&1 | tee -a "$LOG" || true
  fi
fi



START="$(date +%s)"
if make -j"$(nproc)" O=out LLVM=1 LLVM_IAS=1 2>&1 | tee -a "$LOG"; then
  atomic_write_env "$GITHUB_ENV" "SUCCESS" "1"
else
  atomic_write_env "$GITHUB_ENV" "SUCCESS" "0"
fi
END="$(date +%s)"
atomic_write_env "$GITHUB_ENV" "BUILD_TIME" "$((END-START))"

KVER="$(make -s kernelversion | tr -d '\n' || true)"
CLANG_VER="$(clang --version | head -n1 | tr -d '\n' || true)"
atomic_write_env "$GITHUB_ENV" "KERNEL_VERSION" "${KVER:-unknown}"
atomic_write_env "$GITHUB_ENV" "CLANG_VERSION" "${CLANG_VER:-unknown}"

mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
cat "$LOG" >> "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true

ccache -s || true
exit 0
