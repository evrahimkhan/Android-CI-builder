#!/sbin/sh
# AnyKernel3 Universal Script (CI-Safe)

properties() { '
kernel.string='"$(cat kernel.info 2>/dev/null || echo Android Kernel)"'
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
'; }

block=boot
is_slot_device=auto
ramdisk_compression=auto

. tools/ak3-core.sh

ui_print "• Flashing kernel Image"
dump_boot
write_boot
ui_print "✔ Kernel flashed successfully"
