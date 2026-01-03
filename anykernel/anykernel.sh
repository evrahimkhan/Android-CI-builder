#!/sbin/sh
#
# AnyKernel3 Ramdisk Mod Script
# Universal CI-ready version
#

AK3_VER=3.6.0

# Universal settings
do.devicecheck=0
do.cleanup=1
do.modules=0
do.systemless=0

# Device injected by CI
DEVICE_NAME="@DEVICE@"

# Boot partition
block=/dev/block/bootdevice/by-name/boot
is_slot_device=auto

kernel.string=Image
ramdisk_compression=auto

properties() {
  resetprop ro.kernel.anykernel 1
}

backup_file boot
replace_kernel

set_permissions() {
  return 0
}

ui_print " "
ui_print "✅ Kernel flashed successfully"
ui_print "📱 Device: ${DEVICE_NAME:-Universal}"
ui_print "🧠 GKI / Non-GKI compatible"
ui_print "🛠 Installed via AnyKernel3"
ui_print " "
