#!/usr/bin/env bash
set -euo pipefail

# RTL8188eus Driver Integration Script
# Clones and patches the rtl8188eus driver into kernel source tree
# Driver source: https://github.com/aircrack-ng/rtl8188eus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

RTL8188EUS_REPO="${RTL8188EUS_REPO:-https://github.com/aircrack-ng/rtl8188eus}"
RTL8188EUS_BRANCH="${RTL8188EUS_BRANCH:-master}"

# Kernel directory
if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
  KERNEL_DIR="${GITHUB_WORKSPACE}/kernel"
else
  KERNEL_DIR="kernel"
fi

# Staging driver directory
STAGING_DRIVER_DIR="${KERNEL_DIR}/drivers/staging/rtl8188eu"

log_info() { printf "[rtl8188eus] %s\n" "$*"; }
log_error() { printf "[rtl8188eus ERROR] %s\n" "$*" >&2; }

# Validate git URL
validate_rtl8188eus_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(:[0-9]+)?(/[a-zA-Z0-9._-]+)*(\.git)?$ ]]; then
    log_error "Invalid git URL: $url"
    return 1
  fi
  if [[ "$url" =~ \.\. ]]; then
    log_error "URL contains path traversal: $url"
    return 1
  fi
  return 0
}

# Main clone and patch function
clone_and_patch_driver() {
  local work_dir
  work_dir=$(mktemp -d)
  trap "rm -rf '$work_dir'" EXIT

  log_info "Cloning RTL8188eus driver from: $RTL8188EUS_REPO"
  log_info "Branch: $RTL8188EUS_BRANCH"

  # Validate URL
  if ! validate_rtl8188eus_url "$RTL8188EUS_REPO"; then
    exit 1
  fi

  # Check if kernel directory exists
  if [ ! -d "$KERNEL_DIR" ]; then
    log_error "Kernel directory not found: $KERNEL_DIR"
    exit 1
  fi

  # Clone driver to temporary directory
  if ! git clone --depth=1 -b "$RTL8188EUS_BRANCH" "$RTL8188EUS_REPO" "$work_dir/driver" 2>&1; then
    log_error "Failed to clone RTL8188eus driver"
    exit 1
  fi

  # Check if already patched
  if [ -d "$STAGING_DRIVER_DIR" ] && [ -f "$STAGING_DRIVER_DIR/core/rtw_core.c" ]; then
    log_info "Driver already patched in kernel source"
    return 0
  fi

  # Create staging directory
  mkdir -p "$STAGING_DRIVER_DIR"

  # Copy driver files
  log_info "Patching driver into kernel source: $STAGING_DRIVER_DIR"
  
  # Copy core files
  if [ -d "$work_dir/driver/core" ]; then
    cp -r "$work_dir/driver/core" "$STAGING_DRIVER_DIR/"
  fi
  
  # Copy hal files
  if [ -d "$work_dir/driver/hal" ]; then
    cp -r "$work_dir/driver/hal" "$STAGING_DRIVER_DIR/"
  fi
  
  # Copy include files
  if [ -d "$work_dir/driver/include" ]; then
    cp -r "$work_dir/driver/include" "$STAGING_DRIVER_DIR/"
  fi
  
  # Copy os_dep files
  if [ -d "$work_dir/driver/os_dep" ]; then
    cp -r "$work_dir/driver/os_dep" "$STAGING_DRIVER_DIR/"
  fi

  # Create Kconfig file
  cat > "$STAGING_DRIVER_DIR/Kconfig" << 'KCONFIG_EOF'
# SPDX-License-Identifier: GPL-2.0
config RTL8188EU
	tristate "Realtek RTL8188EU Wireless LAN NIC driver"
	depends on WLAN && USB
	select WIRELESS_EXT
	select WEXT_PRIV
	default n
	help
	  This option adds support for the Realtek RTL8188EU USB wireless
	  adapter. This driver is typically used with TP-Link TL-WN725N
	  and similar devices.

	  If built as a module, it will be called r8188eu.ko
KCONFIG_EOF

  # Create Makefile for staging
  cat > "$STAGING_DRIVER_DIR/Makefile" << 'MAKEFILE_EOF'
# SPDX-License-Identifier: GPL-2.0
obj-$(CONFIG_RTL8188EU) += r8188eu.o

r8188eu-objs := \
	core/rtw_core.o \
	core/rtw_cmd.o \
	core/rtw_debug.o \
	core/rtw_efuse.o \
	core/rtw_io.o \
	core/rtw_ioctl_query.o \
	core/rtw_ioctl_set.o \
	core/rtw_mlme_ext.o \
	core/rtw_pwrctrl.o \
	core/rtw_recv.o \
	core/rtw_security.o \
	core/rtw_sta_mgt.o \
	core/rtw_xmit.o \
	hal/hal_intf.o \
	hal/hal_com.o \
	hal/hal_hci/hal_usb.o \
	hal/rtl8188e/rtl8188e_xmit.o \
	hal/rtl8188e/rtl8188e_recv.o \
	hal/rtl8188e/rtl8188e_phycfg.o \
	hal/rtl8188e/rtl8188e_mac.o \
	hal/rtl8188e/rtl8188e_halinit.o \
	hal/rtl8188e/rtl8188e_ops.o \
	os_dep/osdep_service.o \
	os_dep/os_intfs.o \
	os_dep/usb_intf.o \
	os_dep/usb_ops.o \
	os_dep/ioctl_linux.o

ccflags-y += -DCONFIG_8188EU -DCONFIG_USB_HCI -DCONFIG_80211N_HT -DCONFIG_80211W
MAKEFILE_EOF

  # Add to staging Makefile if not already present
  STAGING_MAKEFILE="${KERNEL_DIR}/drivers/staging/Makefile"
  if [ -f "$STAGING_MAKEFILE" ]; then
    if ! grep -q "rtl8188eu" "$STAGING_MAKEFILE"; then
      echo "obj-\$(CONFIG_STAGING) += rtl8188eu/" >> "$STAGING_MAKEFILE"
    fi
  fi

  # Add to staging Kconfig if not already present
  STAGING_KCONFIG="${KERNEL_DIR}/drivers/staging/Kconfig"
  if [ -f "$STAGING_KCONFIG" ]; then
    if ! grep -q "rtl8188eu" "$STAGING_KCONFIG"; then
      echo "source \"drivers/staging/rtl8188eu/Kconfig\"" >> "$STAGING_KCONFIG"
    fi
  fi

  log_info "RTL8188eus driver successfully patched into kernel source"
  log_info "Driver location: $STAGING_DRIVER_DIR"
}

# Execute
log_info "Starting RTL8188eus driver integration..."
clone_and_patch_driver
log_info "Done!"
