#!/usr/bin/env bash
# NetHunter Configuration Verification Script
# Verifies that NetHunter configurations were successfully applied to kernel config
# Usage: ci/verify_nethunter_config.sh <basic|full>

set -euo pipefail

CONFIG_LEVEL="${1:-basic}"

# Validate input
if [[ ! "$CONFIG_LEVEL" =~ ^(basic|full)$ ]]; then
    printf "[verify-nethunter] ERROR: Invalid config level: %s (must be 'basic' or 'full')\n" "$CONFIG_LEVEL" >&2
    exit 2
fi

# Determine kernel directory with proper validation
KERNEL_DIR="${KERNEL_DIR:-${GITHUB_WORKSPACE:-.}/kernel}"
CONFIG_FILE="${KERNEL_DIR}/out/.config"

# Validate KERNEL_DIR is safe (no path traversal)
if [[ "$KERNEL_DIR" =~ \.\. ]]; then
    printf "[verify-nethunter] ERROR: Invalid KERNEL_DIR path: %s\n" "$KERNEL_DIR" >&2
    exit 1
fi

# Wrapper functions with prefix
log_info() { echo "[verify-nethunter] $*"; }
log_warn() { echo "[verify-nethunter] WARNING: $*" >&2; }
log_error() { echo "[verify-nethunter] ERROR: $*" >&2; }

CONFIGS_CHECKED=0
CONFIGS_FOUND=0
CONFIGS_TOTAL=0
MISSING_CRITICAL=()
WARNINGS=()

check_config() {
    local config_name="$1"
    local is_critical="${2:-false}"

    ((CONFIGS_TOTAL++)) || true

    # Use grep -F for fixed-string matching (safer than escaping)
    if grep -qF "CONFIG_${config_name}=" "$CONFIG_FILE" 2>/dev/null; then
        ((CONFIGS_FOUND++)) || true
        return 0
    else
        # Also check for commented-out configs
        if grep -qF "# CONFIG_${config_name} is not set" "$CONFIG_FILE" 2>/dev/null; then
            ((CONFIGS_FOUND++)) || true
            return 0
        fi
        if [ "$is_critical" == "true" ]; then
            MISSING_CRITICAL+=("$config_name")
        else
            WARNINGS+=("$config_name")
        fi
        return 1
    fi
}

echo "=============================================="
echo "Verifying NetHunter Kernel Configuration"
echo "=============================================="
echo "Config level: ${CONFIG_LEVEL}"
echo "Config file: ${CONFIG_FILE}"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Kernel config file not found: ${CONFIG_FILE}"
    exit 1
fi

echo "Checking USB Gadget configurations..."
# Critical configs - USB gadget framework must be present
if check_config "USB_GADGET" "true"; then
    log_info "✓ CONFIG_USB_GADGET present"
else
    log_error "✗ CONFIG_USB_GADGET missing (CRITICAL)"
fi

# Optional configs - might not be needed in all configurations
if check_config "USB_GADGETFS" "false"; then
    log_info "✓ CONFIG_USB_GADGETFS present"
else
    log_warn "✗ CONFIG_USB_GADGETFS missing (optional)"
fi

# Critical configs - USB configfs is required for gadget support
if check_config "USB_CONFIGFS" "true"; then
    log_info "✓ CONFIG_USB_CONFIGFS present"
else
    log_error "✗ CONFIG_USB_CONFIGFS missing (CRITICAL)"
fi

# Optional configs - Serial/ACM might not be needed
if check_config "USB_CONFIGFS_SERIAL" "false"; then
    log_info "✓ CONFIG_USB_CONFIGFS_SERIAL present"
else
    log_warn "✗ CONFIG_USB_CONFIGFS_SERIAL missing (optional)"
fi

if check_config "USB_CONFIGFS_ACM" "false"; then
    log_info "✓ CONFIG_USB_CONFIGFS_ACM present"
else
    log_warn "✗ CONFIG_USB_CONFIGFS_ACM missing (optional)"
fi

# Optional - RNDIS is one of many network options
if check_config "USB_CONFIGFS_RNDIS" "false"; then
    log_info "✓ CONFIG_USB_CONFIGFS_RNDIS present"
else
    log_warn "✗ CONFIG_USB_CONFIGFS_RNDIS missing (optional)"
fi

echo ""
echo "Checking Bluetooth configurations..."
# Critical - BT core must be present
if check_config "BT" "true"; then
    log_info "✓ CONFIG_BT present"
else
    log_error "✗ CONFIG_BT missing (CRITICAL)"
fi

# Optional - RFCOMM is just one protocol
if check_config "BT_RFCOMM" "false"; then
    log_info "✓ CONFIG_BT_RFCOMM present"
else
    log_warn "✗ CONFIG_BT_RFCOMM missing (optional)"
fi

# Optional - HIDP is just one profile
if check_config "BT_HIDP" "false"; then
    log_info "✓ CONFIG_BT_HIDP present"
else
    log_warn "✗ CONFIG_BT_HIDP missing (optional)"
fi

echo ""
echo "Checking Networking configurations..."
# Critical - wireless networking stack must be present
if check_config "MAC80211" "true"; then
    log_info "✓ CONFIG_MAC80211 present"
else
    log_error "✗ CONFIG_MAC80211 missing (CRITICAL)"
fi

if check_config "CFG80211" "true"; then
    log_info "✓ CONFIG_CFG80211 present"
else
    log_error "✗ CONFIG_CFG80211 missing (CRITICAL)"
fi

if [ "${CONFIG_LEVEL}" == "full" ]; then
    echo ""
    echo "Checking Full-level configurations (WiFi, SDR, CAN, NFS)..."
    
    if check_config "CFG80211_CRDA_SUPPORT" "false"; then
        log_info "✓ CONFIG_CFG80211_CRDA_SUPPORT present"
    else
        log_warn "✗ CONFIG_CFG80211_CRDA_SUPPORT missing (optional)"
    fi
    
    if check_config "WLAN" "false"; then
        log_info "✓ CONFIG_WLAN present"
    else
        log_warn "✗ CONFIG_WLAN missing (optional)"
    fi
    
    if check_config "RTLWIFI" "false"; then
        log_info "✓ CONFIG_RTLWIFI present"
    else
        log_warn "✗ CONFIG_RTLWIFI missing (optional)"
    fi
    
    if check_config "CAN" "false"; then
        log_info "✓ CONFIG_CAN present"
    else
        log_warn "✗ CONFIG_CAN missing (optional)"
    fi
    
    if check_config "CAN_RAW" "false"; then
        log_info "✓ CONFIG_CAN_RAW present"
    else
        log_warn "✗ CONFIG_CAN_RAW missing (optional)"
    fi
    
    if check_config "NFS_FS" "false"; then
        log_info "✓ CONFIG_NFS_FS present"
    else
        log_warn "✗ CONFIG_NFS_FS missing (optional)"
    fi
    
    if check_config "NFS_V4" "false"; then
        log_info "✓ CONFIG_NFS_V4 present"
    else
        log_warn "✗ CONFIG_NFS_V4 missing (optional)"
    fi
    
    if check_config "USB_SERIAL" "false"; then
        log_info "✓ CONFIG_USB_SERIAL present"
    else
        log_warn "✗ CONFIG_USB_SERIAL missing (optional)"
    fi
    
    if check_config "USB_ACM" "false"; then
        log_info "✓ CONFIG_USB_ACM present"
    else
        log_warn "✗ CONFIG_USB_ACM missing (optional)"
    fi
fi

echo ""
echo "=============================================="
echo "Verification Summary"
echo "=============================================="
echo "Configs checked: ${CONFIGS_FOUND}/${CONFIGS_TOTAL}"
echo ""

if [ ${#MISSING_CRITICAL[@]} -gt 0 ]; then
    log_error "MISSING CRITICAL CONFIGS:"
    for config in "${MISSING_CRITICAL[@]}"; do
        echo "  - CONFIG_${config}"
    done
    echo ""
    log_error "Verification FAILED - missing critical configurations"
    exit 1
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    log_warn "Missing optional configs (${#WARNINGS[@]}):"
    for config in "${WARNINGS[@]}"; do
        echo "  - CONFIG_${config}"
    done
    echo ""
    log_warn "Verification PASSED with ${#WARNINGS[@]} optional configs missing"
    exit 0
fi

if [ "${CONFIGS_FOUND}" -eq "${CONFIGS_TOTAL}" ]; then
    log_info "All NetHunter configurations verified successfully!"
    echo ""
    log_info "NetHunter configuration verification: PASSED"
    exit 0
fi
