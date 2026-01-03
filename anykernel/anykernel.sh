#!/sbin/sh
# AnyKernel3 Ramdisk Mod Script
# by osm0sis @ xda-developers
# CI-FIXED: Universal + KernelSU auto-detect

### AnyKernel properties
properties() {
    kernel.string=Android Kernel CI Build By Evrahim
    do.devicecheck=1
    do.modules=0
    do.cleanup=1
    do.cleanuponabort=0
    device.name1=@DEVICE@
}

### Import core
. tools/ak3-core.sh

### Boot block
block=/dev/block/bootdevice/by-name/boot
is_slot_device=auto
ramdisk_compression=auto

### -------- KernelSU auto-detection --------
ui_print ""
ui_print "🔍 Detecting KernelSU..."

if [ -e /proc/kernelsu ]; then
    ui_print "✅ KernelSU detected (already installed)"
elif strings "$kernel" 2>/dev/null | grep -q "KernelSU"; then
    ui_print "✅ KernelSU built-in (kernel)"
elif strings "$kernel" 2>/dev/null | grep -qi "kernelsu-next"; then
    ui_print "✅ KernelSU-Next detected"
else
    ui_print "ℹ️ KernelSU not present (normal kernel)"
fi
ui_print ""
### ----------------------------------------

### Flash kernel
dump_boot
write_boot
