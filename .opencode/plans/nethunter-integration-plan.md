# NetHunter Configuration Integration Plan - Universal Modern Kernel Support

## Overview

This plan outlines the implementation of **universal NetHunter kernel configuration** that works across all modern Android kernel versions (4.x, 5.x, 6.x+) with automatic kernel version detection and compatibility handling.

## Research Summary: Kernel Compatibility

### Universal Safe Configs (4.x → 6.x+)
These configs are available and stable across all modern kernel versions:

**Tier 1 - Universal Core:**
- `CONFIG_SYSVIPC` - Available since 2.x
- `CONFIG_MODULES`, `CONFIG_MODULE_UNLOAD`, `CONFIG_MODVERSIONS` - Universal
- `CONFIG_CFG80211`, `CONFIG_MAC80211` - Available since 2.6.22
- `CONFIG_BT` - Universal Bluetooth subsystem
- `CONFIG_USB_ACM`, `CONFIG_USB_STORAGE`, `CONFIG_USB_GADGET` - Universal USB
- `CONFIG_USB_CONFIGFS_*` - Available in 4.x+

### Version-Specific Considerations

**Config Renames/Deprecations:**
| Old (4.x-5.x) | New (5.x+) | Status |
|--------------|------------|---------|
| `CONFIG_ANDROID_BINDER_IPC` | `CONFIG_ANDROID_BINDERFS` | Changed in 5.x |
| `CONFIG_ANDROID` | Removed | Deprecated in 6.x |

**GKI Compatibility:**
| Kernel Version | GKI Version | Strategy |
|---------------|-------------|----------|
| 4.4 - 4.19 | Non-GKI | Build all drivers into kernel |
| 5.4 | GKI 1.0 | Vendor modules separate |
| 5.10+ | GKI 2.0 | Load vendor modules separately |
| 6.1+ | GKI 2.0 | Current stable |

## Universal Implementation Strategy

### Phase 1: Enhanced Build Script with Version Detection

#### 1.1 Kernel Version Detection System

Add to `ci/build_kernel.sh`:

```bash
# Detect kernel version for conditional config application
detect_kernel_version() {
  local kver
  kver="$(make -s kernelversion 2>/dev/null | head -n1 | tr -d '\n')"
  
  # Parse major and minor versions
  local major minor
  major=$(echo "$kver" | cut -d. -f1)
  minor=$(echo "$kver" | cut -d. -f2)
  
  echo "${major}.${minor}"
  export KERNEL_MAJOR="$major"
  export KERNEL_MINOR="$minor"
}

# Check if config option exists in Kconfig
check_config_exists() {
  local config_name="$1"
  local kconfig_files
  
  # Search in Kconfig files
  if find . -name "Kconfig*" -type f -exec grep -l "config $config_name" {} \; 2>/dev/null | grep -q .; then
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
```

#### 1.2 Universal NetHunter Configuration Functions

```bash
# Tier 1: Universal configs (works on 4.x, 5.x, 6.x+)
apply_nethunter_universal_core() {
  echo "Applying universal NetHunter core configuration..."
  
  # General - Universal
  safe_set_kcfg_bool SYSVIPC y
  safe_set_kcfg_bool MODULES y
  safe_set_kcfg_bool MODULE_UNLOAD y
  safe_set_kcfg_bool MODULE_FORCE_UNLOAD y
  safe_set_kcfg_bool MODVERSIONS y
  set_kcfg_str DEFAULT_HOSTNAME "kali"
  set_kcfg_str LOCALVERSION ""
  
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

# Main configuration dispatcher
apply_nethunter_config() {
  local level="${NETHUNTER_CONFIG_LEVEL:-basic}"
  
  # Detect kernel version
  detect_kernel_version
  echo "Detected kernel version: ${KERNEL_MAJOR}.${KERNEL_MINOR}"
  
  # Check GKI status
  local is_gki=false
  if grep -q "CONFIG_GKI=y" out/.config 2>/dev/null; then
    is_gki=true
    echo "GKI kernel detected"
  fi
  
  echo "Applying NetHunter configuration (level: $level)..."
  
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
  
  # Re-run olddefconfig to resolve dependencies
  echo "Resolving configuration dependencies..."
  if ! make O=out olddefconfig 2>&1 | tee -a build.log; then
    if ! make O=out silentoldconfig 2>&1 | tee -a build.log; then
      run_oldconfig || true
    fi
  fi
  
  echo "NetHunter configuration applied successfully"
}
```

### Phase 2: Workflow Configuration Updates

#### 2.1 Update `.github/workflows/kernel-ci.yml`

```yaml
enable_nethunter_config:
  description: Enable NetHunter kernel configuration
  required: true
  default: "false"
  type: choice
  options: ["false", "true"]

nethunter_config_level:
  description: NetHunter configuration level (basic/full)
  required: false
  default: "basic"
  type: choice
  options: ["basic", "full"]

nethunter_skip_unavailable:
  description: Skip unavailable configs silently (recommended for universal compatibility)
  required: false
  default: "true"
  type: choice
  options: ["true", "false"]
```

#### 2.2 Environment Variables

```yaml
env:
  NETHUNTER_ENABLED: ${{ inputs.enable_nethunter_config }}
  NETHUNTER_CONFIG_LEVEL: ${{ inputs.nethunter_config_level }}
  NETHUNTER_SKIP_UNAVAILABLE: ${{ inputs.nethunter_skip_unavailable }}
```

### Phase 3: GKI Compatibility Module

#### 3.1 GKI Detection Enhancement

Update `ci/detect_gki.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

detect_gki_version() {
  local gki_version="none"
  
  if [ -f out/.config ]; then
    if grep -q "CONFIG_GKI=y" out/.config; then
      # Check for GKI 2.0 indicators
      if grep -q "CONFIG_GKI_2=y" out/.config 2>/dev/null || \
         grep -q "5\.[1-9][0-9]" out/.config 2>/dev/null || \
         grep -q "6\.[0-9]" out/.config 2>/dev/null; then
        gki_version="GKI_2.0"
      else
        gki_version="GKI_1.0"
      fi
    else
      gki_version="NON_GKI"
    fi
  fi
  
  echo "GKI_VERSION=$gki_version" >> "$GITHUB_ENV"
  echo "Detected GKI version: $gki_version"
}

detect_gki_version
```

### Phase 4: Configuration Matrix by Kernel Version

#### 4.1 Version-Specific Config Map

```bash
# Config availability matrix
# Usage: check_config_available "CONFIG_NAME" "min_major" "min_minor"
check_config_available() {
  local config="$1"
  local min_major="$2"
  local min_minor="$3"
  
  if [ "$KERNEL_MAJOR" -gt "$min_major" ] || \
     ([ "$KERNEL_MAJOR" -eq "$min_major" ] && [ "$KERNEL_MINOR" -ge "$min_minor" ]); then
    return 0  # Available
  fi
  
  return 1  # Not available
}

# Apply config only if kernel version supports it
apply_versioned_config() {
  local config="$1"
  local min_major="$2"
  local min_minor="$3"
  local value="$4"
  
  if check_config_available "$config" "$min_major" "$min_minor"; then
    safe_set_kcfg_bool "$config" "$value"
  else
    echo "Skipping CONFIG_$config (requires kernel >= $min_major.$min_minor)"
  fi
}
```

### Phase 5: Testing Strategy for Universal Compatibility

#### 5.1 Test Matrix

| Kernel Version | GKI Status | Config Level | Expected Result |
|---------------|------------|--------------|-----------------|
| 4.4.x | Non-GKI | basic | All universal configs applied |
| 4.4.x | Non-GKI | full | All configs including non-GKI extras |
| 4.19.x | Non-GKI | full | Full config without GKI restrictions |
| 5.4.x | GKI 1.0 | basic | Core configs only |
| 5.10.x | GKI 2.0 | basic | Core configs + vendor module support |
| 5.15.x | GKI 2.0 | full | Full configs, skip non-GKI extras |
| 6.1.x | GKI 2.0 | full | Full configs, skip non-GKI extras |
| 6.6.x | GKI 2.0 | full | Full configs, skip non-GKI extras |

#### 5.2 Validation Checks

```bash
validate_nethunter_config() {
  echo "Validating NetHunter configuration..."
  
  # Check essential configs
  local required_configs=(
    "CONFIG_SYSVIPC"
    "CONFIG_MODULES"
    "CONFIG_BT"
    "CONFIG_USB_ACM"
    "CONFIG_USB_GADGET"
  )
  
  local missing=()
  for config in "${required_configs[@]}"; do
    if ! grep -q "^$config=y" out/.config; then
      missing+=("$config")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo "WARNING: Missing essential configs: ${missing[*]}"
    return 1
  fi
  
  echo "Essential NetHunter configs validated successfully"
  return 0
}
```

### Phase 6: Implementation Checklist

#### Core Implementation
- [ ] Add kernel version detection to build script
- [ ] Implement `check_config_exists()` function
- [ ] Implement `safe_set_kcfg_bool()` with fallback
- [ ] Create universal config tier functions
- [ ] Add GKI detection and conditional logic
- [ ] Implement version-aware config application

#### Workflow Updates
- [ ] Update workflow YAML with NetHunter inputs
- [ ] Add GKI version detection step
- [ ] Pass environment variables to build steps

#### Testing & Validation
- [ ] Test with kernel 4.4 (Legacy)
- [ ] Test with kernel 4.19 (Pre-GKI)
- [ ] Test with kernel 5.4 (GKI 1.0)
- [ ] Test with kernel 5.10 (GKI 2.0)
- [ ] Test with kernel 5.15 (GKI 2.0 stable)
- [ ] Test with kernel 6.1 (Current stable)
- [ ] Validate config application logs
- [ ] Verify build success across all versions

#### Documentation
- [ ] Update README with kernel compatibility matrix
- [ ] Document version-specific behaviors
- [ ] Add troubleshooting guide for config issues

### Phase 7: Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Config doesn't exist in older kernels | Medium | `check_config_exists()` before applying |
| Config renamed in newer kernels | Medium | `set_kcfg_with_fallback()` for renamed options |
| GKI restrictions block configs | Medium | Detect GKI and skip incompatible configs |
| Kernel version parsing fails | Low | Fallback to safe universal configs only |
| Dependency resolution fails | Medium | Re-run olddefconfig after config changes |

### Phase 8: Success Criteria

1. **Universal Compatibility**: Works on kernel 4.x, 5.x, and 6.x+
2. **Graceful Degradation**: Skips unavailable configs without errors
3. **Version Awareness**: Automatically adapts to kernel capabilities
4. **GKI Compatible**: Respects GKI 2.0 restrictions
5. **Build Success**: Passes all test matrix configurations
6. **Zero Breaking Changes**: Doesn't affect existing non-NetHunter builds

## Configuration Summary

**Universal Core (All Kernels)**: ~25 configs
**Extended Features (4.x+)**: ~35 configs  
**Specialized Hardware (4.x+)**: ~30 configs
**Non-GKI Extras (4.x-5.x)**: ~10 configs

**Total Universal Coverage**: 90+ configuration options with intelligent fallbacks

## Next Steps

1. **Review** this universal plan
2. **Approve** approach for kernel compatibility
3. **Begin Phase 1** implementation with version detection
4. **Test iteratively** with different kernel versions
5. **Validate** GKI vs non-GKI behavior
6. **Document** final implementation