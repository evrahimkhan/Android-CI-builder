#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# NetHunter Kernel Configuration Script
# Universal support for kernel versions 4.x, 5.x, 6.x+
# Automatically detects kernel version and applies compatible configurations

# Source directory (should be in kernel/ after clone)
# Use GITHUB_WORKSPACE to resolve absolute path
if [[ -z "${KERNEL_DIR:-}" ]]; then
  if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    KERNEL_DIR="${GITHUB_WORKSPACE}/kernel"
  else
    KERNEL_DIR="kernel"
  fi
fi

# Configurable default hostname
NETHUNTER_HOSTNAME="${NETHUNTER_HOSTNAME:-kali}"

# Detect kernel version for conditional config application
detect_kernel_version() {
  local kver

  # Validate kernel directory exists
  if [ ! -d "$KERNEL_DIR" ]; then
    log_error "Kernel directory not found: $KERNEL_DIR"
    return 1
  fi

  # Detect kernel version
  kver="$(cd "$KERNEL_DIR" && make -s kernelversion 2>/dev/null | head -n1 | tr -d '\n')"

  # Allow explicit override via environment variable
  if [[ -n "${FORCE_KERNEL_VERSION:-}" ]]; then
    kver="$FORCE_KERNEL_VERSION"
    log_info "Using forced kernel version: $kver"
  fi

  if [ -z "$kver" ] || [ "$kver" = "" ] || [[ ! "$kver" =~ ^[0-9]+\.[0-9]+ ]]; then
    log_error "Could not detect kernel version: '${kver:-unknown}'"
    log_error "Set FORCE_KERNEL_VERSION=x.y environment variable to override"
    return 1
  fi

  # Parse major and minor versions
  local major minor
  major=$(echo "$kver" | cut -d. -f1)
  minor=$(echo "$kver" | cut -d. -f2)

  # Validate parsed values are numeric
  if [[ ! "$major" =~ ^[0-9]+$ ]] || [[ ! "$minor" =~ ^[0-9]+$ ]]; then
    log_error "Invalid kernel version format: $kver"
    return 1
  fi

  export KERNEL_MAJOR="${major:-4}"
  export KERNEL_MINOR="${minor:-4}"

  printf "Detected kernel version: %s.%s\n" "$KERNEL_MAJOR" "$KERNEL_MINOR"
}

# Check if config option exists in Kconfig files
# Handles multiple Kconfig directives: config, menuconfig, choice, etc.
check_config_exists() {
  local config_name="$1"

  if [ ! -d "$KERNEL_DIR" ]; then
    return 1
  fi

  # Validate config_name format first (defense in depth)
  if [[ ! "$config_name" =~ ^[A-Za-z0-9_]+$ ]]; then
    return 1
  fi

  # Search in Kconfig files with validated config name
  while IFS= read -r -d '' kconfig_file; do
    # Use grep with fixed strings for safer searching (no regex injection possible)
    if grep -F "config ${config_name}" "$kconfig_file" 2>/dev/null; then
      return 0  # Config exists
    fi
  done < <(find "$KERNEL_DIR" -name "Kconfig*" -type f -print0 2>/dev/null)

  # Also check if it's already in .config (may be from defconfig)
  if [ -f "$KERNEL_DIR/out/.config" ]; then
    local escaped_config
    escaped_config=$(printf '%s\n' "$config_name" | sed 's/[][\.*^$()+?{|]/\\&/g')
    if grep -qE "^#?\s*CONFIG_${escaped_config}=" "$KERNEL_DIR/out/.config" 2>/dev/null; then
      return 0  # Config exists in .config
    fi
  fi

  return 1  # Config doesn't exist
}

# Safe config setter that checks existence first
safe_set_kcfg_bool() {
  local key="$1"
  local yn="$2"
  
  # Validate inputs before use
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    printf "Notice: CONFIG_%s has invalid format, skipping\n" "$key"
    return 1
  fi
  
  if [[ ! "$yn" =~ ^[yn]$ ]]; then
    printf "Notice: Invalid value '%s' for CONFIG_%s, skipping\n" "$yn" "$key"
    return 1
  fi
  
  if check_config_exists "$key"; then
    set_kcfg_bool "$key" "$yn"
  else
    printf "Notice: CONFIG_%s not available in this kernel version, skipping\n" "$key"
  fi
}

# Safe config setter for string values
safe_set_kcfg_str() {
  local key="$1"
  local val="$2"
  
  # Validate inputs before use
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    printf "Notice: CONFIG_%s has invalid format, skipping\n" "$key"
    return 1
  fi
  
  if check_config_exists "$key"; then
    set_kcfg_str "$key" "$val"
  else
    printf "Notice: CONFIG_%s not available in this kernel version, skipping\n" "$key"
  fi
}

# Apply config with fallback for renamed options
set_kcfg_with_fallback() {
  local primary_key="$1"
  local fallback_key="$2"
  local yn="$3"
  
  if check_config_exists "$primary_key"; then
    set_kcfg_bool "$primary_key" "$yn"
  elif check_config_exists "$fallback_key"; then
    set_kcfg_bool "$fallback_key" "$yn"
  else
    printf "Notice: Neither CONFIG_%s nor CONFIG_%s available, skipping\n" "$primary_key" "$fallback_key"
  fi
}

# Helper function to set boolean config (requires cfg_tool from build_kernel.sh)
set_kcfg_bool() {
  local key="$1"
  local yn="$2"

  # Sanitize inputs to prevent command injection
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    log_error "Invalid key format: $key"
    return 1
  fi

  if [[ ! "$yn" =~ ^[yn]$ ]]; then
    log_error "Invalid yn value: $yn, must be 'y' or 'n'"
    return 1
  fi

  local tool
  tool="$KERNEL_DIR/scripts/config"

  if [ -f "$tool" ]; then
    chmod +x "$tool" 2>/dev/null || true
    if [ "$yn" = "y" ]; then
      "$tool" --file "$KERNEL_DIR/out/.config" -e "$key" >/dev/null 2>&1 || true
    else
      "$tool" --file "$KERNEL_DIR/out/.config" -d "$key" >/dev/null 2>&1 || true
    fi
  else
    # Fallback to sed manipulation with proper error handling
    if [ "$yn" = "y" ]; then
      sed -i "s|^# CONFIG_${key} is not set|CONFIG_${key}=y|" "$KERNEL_DIR/out/.config" 2>/dev/null || true
      if grep -q "^CONFIG_${key}=y" "$KERNEL_DIR/out/.config" 2>/dev/null; then
        : # Config already set
      else
        printf "CONFIG_%s=y\n" "$key" >> "$KERNEL_DIR/out/.config" || { log_error "Failed to append CONFIG_${key}"; return 1; }
      fi
    else
      sed -i "/^CONFIG_${key}=y$/d;/^CONFIG_${key}=m$/d" "$KERNEL_DIR/out/.config" 2>/dev/null || true
      grep -q "^# CONFIG_${key} is not set" "$KERNEL_DIR/out/.config" 2>/dev/null || { log_error "Failed to mark CONFIG_${key} as not set"; return 1; }
    fi
  fi
}

# Helper function to set string config
set_kcfg_str() {
  local key="$1"
  local val="$2"
  
  # Sanitize inputs
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    log_error "Invalid key format: $key"
    return 1
  fi
  
  # Comprehensive escaping for sed - escape ALL special regex characters and shell metacharacters
  local sanitized_val
  sanitized_val=$(printf '%s\n' "$val" | \
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g; s/;/\\;/g; s/&/\\&/g; s/|/\\|/g; s/</\\</g; s/>/\\>/g; s/(/\\(/g; s/)/\\)/g; s/\[/\\[/g; s/\]/\\]/g; s/{/\\{/g; s/}/\\}/g; s/\*/\\*/g; s/?/\\?/g; s/+/\\+/g; s/\^/\\^/g; s/\./\\./g; s/\//\\\//g') || { log_error "Failed to sanitize value"; return 1; }
  
  local tool
  tool="$KERNEL_DIR/scripts/config"
  
  if [ -f "$tool" ]; then
    chmod +x "$tool" 2>/dev/null || true
    "$tool" --file "$KERNEL_DIR/out/.config" --set-str "$key" "$sanitized_val" >/dev/null 2>&1 || true
  else
    if grep -q "^CONFIG_${key}=" "$KERNEL_DIR/out/.config" 2>/dev/null; then
      sed -i "s|^CONFIG_${key}=.*|CONFIG_${key}=\"${sanitized_val}\"|" "$KERNEL_DIR/out/.config" || true
    else
      printf 'CONFIG_%s="%s"\n' "$key" "$sanitized_val" >> "$KERNEL_DIR/out/.config"
    fi
  fi
}

# Tier 1: Universal configs (works on 4.x, 5.x, 6.x+)
apply_nethunter_universal_core() {
  printf "Applying universal NetHunter core configuration...\n"
  
  # General - Universal
  safe_set_kcfg_bool SYSVIPC y
  safe_set_kcfg_bool MODULES y
  safe_set_kcfg_bool MODULE_UNLOAD y
  safe_set_kcfg_bool MODULE_FORCE_UNLOAD y
  safe_set_kcfg_bool MODVERSIONS y
  safe_set_kcfg_str DEFAULT_HOSTNAME "${NETHUNTER_HOSTNAME}"
  safe_set_kcfg_str LOCALVERSION ""
  
  # Core networking - Universal
  safe_set_kcfg_bool CFG80211 y
  safe_set_kcfg_bool CFG80211_WEXT y
  safe_set_kcfg_bool MAC80211 y
  safe_set_kcfg_bool MAC80211_MESH y
  
  # Bluetooth - Universal
  safe_set_kcfg_bool BT y
  safe_set_kcfg_bool BT_HCIBTUSB y
  safe_set_kcfg_bool BT_HCIBTUSB_BCM y
  safe_set_kcfg_bool BT_HCIBTUSB_RTL y
  safe_set_kcfg_bool BT_HCIUART y
  safe_set_kcfg_bool BT_HCIUART_H4 y
  
  # USB Core - Universal
  safe_set_kcfg_bool USB_ACM y
  safe_set_kcfg_bool USB_STORAGE y
  safe_set_kcfg_bool USB_GADGET y
  safe_set_kcfg_bool USB_CONFIGFS y
  safe_set_kcfg_bool USB_CONFIGFS_SERIAL y
  safe_set_kcfg_bool USB_CONFIGFS_ACM y
  safe_set_kcfg_bool USB_CONFIGFS_ECM y
  safe_set_kcfg_bool USB_CONFIGFS_RNDIS y
  safe_set_kcfg_bool USB_CONFIGFS_MASS_STORAGE y
  safe_set_kcfg_bool USB_CONFIGFS_F_HID y
  
  # HID Support - Universal
  safe_set_kcfg_bool HIDRAW y
  safe_set_kcfg_bool USB_HID y
}

# Tier 2: Version-aware Android/Binder support
apply_nethunter_android_binder() {
  printf "Applying Android Binder configuration...\n"
  
  # Android Binder with version fallback
  # 4.x uses ANDROID_BINDER_IPC, 5.x+ uses ANDROID_BINDERFS
  set_kcfg_with_fallback ANDROID_BINDERFS ANDROID_BINDER_IPC y
}

# Tier 3: Extended Networking (4.x+)
apply_nethunter_networking() {
  printf "Applying extended networking configuration...\n"
  
  # USB Ethernet adapters
  safe_set_kcfg_bool USB_RTL8150 y
  safe_set_kcfg_bool USB_RTL8152 y
  safe_set_kcfg_bool USB_NET_CDCETHER y
  safe_set_kcfg_bool USB_NET_RNDIS_HOST y
  
  # Network filesystems
  safe_set_kcfg_bool NETWORK_FILESYSTEMS y
  safe_set_kcfg_bool NFS_V2 y
  safe_set_kcfg_bool NFS_V3 y
  safe_set_kcfg_bool NFS_V4 y
  safe_set_kcfg_bool NFSD y
  safe_set_kcfg_bool NFSD_V3 y
  safe_set_kcfg_bool NFSD_V4 y
}

# Tier 4: Wireless LAN Drivers (4.x+)
apply_nethunter_wireless() {
  printf "Applying wireless LAN configuration...\n"
  
  # Atheros/Qualcomm
  safe_set_kcfg_bool WLAN_VENDOR_ATH y
  safe_set_kcfg_bool ATH9K_HTC y
  safe_set_kcfg_bool CARL9170 y
  safe_set_kcfg_bool ATH6KL y
  safe_set_kcfg_bool ATH6KL_USB y
  
  # MediaTek
  safe_set_kcfg_bool WLAN_VENDOR_MEDIATEK y
  safe_set_kcfg_bool MT7601U y
  
  # Ralink
  safe_set_kcfg_bool WLAN_VENDOR_RALINK y
  safe_set_kcfg_bool RT2X00 y
  safe_set_kcfg_bool RT2500USB y
  safe_set_kcfg_bool RT73USB y
  safe_set_kcfg_bool RT2800USB y
  safe_set_kcfg_bool RT2800USB_RT33XX y
  safe_set_kcfg_bool RT2800USB_RT35XX y
  safe_set_kcfg_bool RT2800USB_RT3573 y
  safe_set_kcfg_bool RT2800USB_RT53XX y
  safe_set_kcfg_bool RT2800USB_RT55XX y
  safe_set_kcfg_bool RT2800USB_UNKNOWN y
  
  # Realtek
  safe_set_kcfg_bool WLAN_VENDOR_REALTEK y
  safe_set_kcfg_bool RTL8187 y
  safe_set_kcfg_bool RTL_CARDS y
  safe_set_kcfg_bool RTL8192CU y
  safe_set_kcfg_bool RTL8XXXU_UNTESTED y
  
  # ZyDAS
  safe_set_kcfg_bool WLAN_VENDOR_ZYDAS y
  safe_set_kcfg_bool USB_ZD1201 y
  safe_set_kcfg_bool ZD1211RW y
  safe_set_kcfg_bool USB_NET_RNDIS_WLAN y
}

# Tier 5: SDR Support (4.x+, hardware dependent)
apply_nethunter_sdr() {
  printf "Applying SDR configuration...\n"
  
  # Digital TV and SDR support
  safe_set_kcfg_bool MEDIA_DIGITAL_TV_SUPPORT y
  safe_set_kcfg_bool MEDIA_SDR_SUPPORT y
  safe_set_kcfg_bool MEDIA_USB_SUPPORT y
  safe_set_kcfg_bool USB_AIRSPY y
  safe_set_kcfg_bool USB_HACKRF y
  safe_set_kcfg_bool USB_MSI2500 y
  
  # DVB frontends
  safe_set_kcfg_bool DVB_RTL2830 y
  safe_set_kcfg_bool DVB_RTL2832 y
  safe_set_kcfg_bool DVB_RTL2832_SDR y
  safe_set_kcfg_bool DVB_SI2168 y
  safe_set_kcfg_bool DVB_ZD1301_DEMOD y
}

# Tier 6: CAN Support (4.x+, specialized hardware)
apply_nethunter_can() {
  printf "Applying CAN bus configuration...\n"
  
  # CAN subsystem
  safe_set_kcfg_bool CAN y
  safe_set_kcfg_bool CAN_RAW y
  safe_set_kcfg_bool CAN_BCM y
  safe_set_kcfg_bool CAN_GW y
  safe_set_kcfg_bool CAN_VCAN y
  safe_set_kcfg_bool CAN_CALC_BITTIMING y
  
  # Virtual sockets for CAN
  safe_set_kcfg_bool VSOCKETS y
  safe_set_kcfg_bool NETLINK_DIAG y
  safe_set_kcfg_bool NET_CLS_CAN y
  
  # USB serial for CAN adapters
  safe_set_kcfg_bool USB_SERIAL y
  safe_set_kcfg_bool USB_SERIAL_CONSOLE y
  safe_set_kcfg_bool USB_SERIAL_GENERIC y
  safe_set_kcfg_bool USB_SERIAL_CH341 y
  safe_set_kcfg_bool USB_SERIAL_FTDI_SIO y
  safe_set_kcfg_bool USB_SERIAL_PL2303 y
}

# GKI-aware configuration (only for non-GKI kernels)
apply_nethunter_nongki_extras() {
  printf "Applying non-GKI specific configurations...\n"
  
  # These are better handled as vendor modules in GKI 2.0
  # But for non-GKI kernels, we build them in
  
  # Additional USB gadget functions
  safe_set_kcfg_bool USB_CONFIGFS_OBEX y
  safe_set_kcfg_bool USB_CONFIGFS_NCM y
  safe_set_kcfg_bool USB_CONFIGFS_ECM_SUBSET y
  safe_set_kcfg_bool USB_CONFIGFS_EEM y
  
  # More Bluetooth protocols
  safe_set_kcfg_bool BT_HCIBCM203X y
  safe_set_kcfg_bool BT_HCIBPA10X y
  safe_set_kcfg_bool BT_HCIBFUSB y
  safe_set_kcfg_bool BT_HCIVHCI y
}

# Check if running on GKI kernel
check_gki_status() {
  if [ -f "$KERNEL_DIR/out/.config" ]; then
    if grep -q "CONFIG_GKI=y" "$KERNEL_DIR/out/.config" 2>/dev/null; then
      return 0  # Is GKI
    fi
  fi
  return 1  # Not GKI
}

# Backup kernel config before modifications
backup_kernel_config() {
  if [ -f "$KERNEL_DIR/out/.config" ]; then
    cp "$KERNEL_DIR/out/.config" "$KERNEL_DIR/out/.config.backup.nethunter" 2>/dev/null || true
    printf "Backup created: .config.backup.nethunter\n"
  fi
}

# Restore kernel config from backup on failure
restore_kernel_config() {
  if [ -f "$KERNEL_DIR/out/.config.backup.nethunter" ]; then
    cp "$KERNEL_DIR/out/.config.backup.nethunter" "$KERNEL_DIR/out/.config" 2>/dev/null || true
    printf "Restored kernel config from backup\n"
    rm -f "$KERNEL_DIR/out/.config.backup.nethunter"
  fi
}

# Cleanup backup on success
cleanup_kernel_config_backup() {
  if ! rm -f "$KERNEL_DIR/out/.config.backup.nethunter" 2>/dev/null; then
    log_warn "Failed to remove kernel config backup (may not exist)"
  fi
}

# Validate NetHunter configuration level
validate_config_level() {
  local level="$1"
  
  case "$level" in
    basic|full)
      return 0
      ;;
    "")
      log_warn "NETHUNTER_CONFIG_LEVEL not set, defaulting to 'basic'"
      return 0
      ;;
    *)
      log_error "Invalid NETHUNTER_CONFIG_LEVEL='$level'. Must be 'basic' or 'full'"
      return 1
      ;;
  esac
}

# Main configuration dispatcher
apply_nethunter_config() {
  local level="${NETHUNTER_CONFIG_LEVEL:-basic}"
  
  # Validate config level
  if ! validate_config_level "$level"; then
    printf "Falling back to 'basic' level due to invalid input\n"
    level="basic"
  fi
  
  printf "\n==============================================\n"
  printf "NetHunter Kernel Configuration\n"
  printf "==============================================\n"
  
  # Detect kernel version
  detect_kernel_version
  
  # Check GKI status
  local is_gki=false
  if check_gki_status; then
    is_gki=true
    printf "GKI kernel detected - will respect GKI restrictions\n"
  else
    printf "Non-GKI kernel detected - full configuration available\n"
  fi
  
  printf "Configuration level: %s\n\n" "$level"
  
  # Backup config before modifications
  backup_kernel_config
  
  # Set trap to restore on error
  trap 'log_error "NetHunter configuration failed, restoring backup..."; restore_kernel_config; exit 1' ERR
  
  # Always apply universal core
  apply_nethunter_universal_core
  apply_nethunter_android_binder
  
  if [ "$level" = "full" ]; then
    # Apply extended configs
    apply_nethunter_networking
    apply_nethunter_wireless
    apply_nethunter_sdr
    apply_nethunter_can
    
    # Only apply non-GKI extras if not GKI
    if [ "$is_gki" = false ]; then
      apply_nethunter_nongki_extras
    fi
  fi
  
  # Clear trap on success
  trap - ERR
  
  # Cleanup backup
  cleanup_kernel_config_backup
  
  printf "\n==============================================\n"
  printf "NetHunter configuration applied successfully\n"
  printf "==============================================\n"
}

# Main execution
if [ "${NETHUNTER_ENABLED:-false}" != "true" ]; then
  printf "NetHunter configuration disabled (set NETHUNTER_ENABLED=true to enable)\n"
  exit 0
fi

# Change to kernel directory if it exists
if [ -d "$KERNEL_DIR" ]; then
  cd "$KERNEL_DIR"
fi

# Check if .config exists using absolute path
if [ ! -f "${KERNEL_DIR}/out/.config" ]; then
  log_error "Kernel config not found at ${KERNEL_DIR}/out/.config"
  exit 1
fi

# Apply configuration
apply_nethunter_config
