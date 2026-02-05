#!/usr/bin/env bash
set -euo pipefail

# NetHunter Kernel Configuration Script
# Universal support for kernel versions 4.x, 5.x, 6.x+
# Automatically detects kernel version and applies compatible configurations

# Source directory (should be in kernel/ after clone)
KERNEL_DIR="${KERNEL_DIR:-kernel}"

# Detect kernel version for conditional config application
detect_kernel_version() {
  local kver
  if [ -d "$KERNEL_DIR" ]; then
    kver="$(cd "$KERNEL_DIR" && make -s kernelversion 2>/dev/null | head -n1 | tr -d '\n')" || true
  fi
  
  if [ -z "$kver" ] || [ "$kver" = "" ]; then
    echo "Warning: Could not detect kernel version, assuming 4.4" >&2
    kver="4.4"
  fi
  
  # Parse major and minor versions
  local major minor
  major=$(echo "$kver" | cut -d. -f1)
  minor=$(echo "$kver" | cut -d. -f2)
  
  export KERNEL_MAJOR="${major:-4}"
  export KERNEL_MINOR="${minor:-4}"
  
  echo "Detected kernel version: ${KERNEL_MAJOR}.${KERNEL_MINOR}"
}

# Check if config option exists in Kconfig files
check_config_exists() {
  local config_name="$1"
  
  if [ ! -d "$KERNEL_DIR" ]; then
    return 1
  fi
  
  # Search in Kconfig files
  if find "$KERNEL_DIR" -name "Kconfig*" -type f 2>/dev/null | \
     xargs grep -l "^config $config_name" 2>/dev/null | grep -q .; then
    return 0  # Config exists
  fi
  
  return 1  # Config doesn't exist
}

# Safe config setter that checks existence first
safe_set_kcfg_bool() {
  local key="$1"
  local yn="$2"
  
  if check_config_exists "$key"; then
    set_kcfg_bool "$key" "$yn"
  else
    echo "Notice: CONFIG_$key not available in this kernel version, skipping"
  fi
}

# Safe config setter for string values
safe_set_kcfg_str() {
  local key="$1"
  local val="$2"
  
  if check_config_exists "$key"; then
    set_kcfg_str "$key" "$val"
  else
    echo "Notice: CONFIG_$key not available in this kernel version, skipping"
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
    echo "Notice: Neither CONFIG_$primary_key nor CONFIG_$fallback_key available, skipping"
  fi
}

# Helper function to set boolean config (requires cfg_tool from build_kernel.sh)
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
    # Fallback to sed manipulation
    if [ "$yn" = "y" ]; then
      sed -i "s|^# CONFIG_${key} is not set|CONFIG_${key}=y|" "$KERNEL_DIR/out/.config" 2>/dev/null || true
      grep -q "^CONFIG_${key}=y" "$KERNEL_DIR/out/.config" 2>/dev/null || echo "CONFIG_${key}=y" >> "$KERNEL_DIR/out/.config"
    else
      sed -i "/^CONFIG_${key}=y$/d;/^CONFIG_${key}=m$/d" "$KERNEL_DIR/out/.config" 2>/dev/null || true
      grep -q "^# CONFIG_${key} is not set" "$KERNEL_DIR/out/.config" 2>/dev/null || echo "# CONFIG_${key} is not set" >> "$KERNEL_DIR/out/.config"
    fi
  fi
}

# Helper function to set string config
set_kcfg_str() {
  local key="$1"
  local val="$2"
  
  # Sanitize inputs
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: Invalid key format: $key" >&2
    return 1
  fi
  
  # Escape special characters in value to prevent injection
  local sanitized_val
  sanitized_val=$(printf '%s\n' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
  
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
  echo "Applying universal NetHunter core configuration..."
  
  # General - Universal
  safe_set_kcfg_bool SYSVIPC y
  safe_set_kcfg_bool MODULES y
  safe_set_kcfg_bool MODULE_UNLOAD y
  safe_set_kcfg_bool MODULE_FORCE_UNLOAD y
  safe_set_kcfg_bool MODVERSIONS y
  safe_set_kcfg_str DEFAULT_HOSTNAME "kali"
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
  echo "Applying Android Binder configuration..."
  
  # Android Binder with version fallback
  # 4.x uses ANDROID_BINDER_IPC, 5.x+ uses ANDROID_BINDERFS
  set_kcfg_with_fallback ANDROID_BINDERFS ANDROID_BINDER_IPC y
}

# Tier 3: Extended Networking (4.x+)
apply_nethunter_networking() {
  echo "Applying extended networking configuration..."
  
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
  echo "Applying wireless LAN configuration..."
  
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
  echo "Applying SDR configuration..."
  
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
  echo "Applying CAN bus configuration..."
  
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
  echo "Applying non-GKI specific configurations..."
  
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

# Main configuration dispatcher
apply_nethunter_config() {
  local level="${NETHUNTER_CONFIG_LEVEL:-basic}"
  
  echo "=============================================="
  echo "NetHunter Kernel Configuration"
  echo "=============================================="
  
  # Detect kernel version
  detect_kernel_version
  
  # Check GKI status
  local is_gki=false
  if check_gki_status; then
    is_gki=true
    echo "GKI kernel detected - will respect GKI restrictions"
  else
    echo "Non-GKI kernel detected - full configuration available"
  fi
  
  echo "Configuration level: $level"
  echo ""
  
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
  
  echo ""
  echo "=============================================="
  echo "NetHunter configuration applied successfully"
  echo "=============================================="
}

# Main execution
if [ "${NETHUNTER_ENABLED:-false}" != "true" ]; then
  echo "NetHunter configuration disabled (set NETHUNTER_ENABLED=true to enable)"
  exit 0
fi

# Change to kernel directory if it exists
if [ -d "$KERNEL_DIR" ]; then
  cd "$KERNEL_DIR"
fi

# Check if .config exists
if [ ! -f "out/.config" ]; then
  echo "ERROR: Kernel config not found at out/.config" >&2
  exit 1
fi

# Apply configuration
apply_nethunter_config
