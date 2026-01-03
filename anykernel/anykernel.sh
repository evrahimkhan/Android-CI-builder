#!/sbin/sh
# AnyKernel3 universal installer

properties() {
  kernel.string=CI-Built By Evrahim
  do.devicecheck=1
  do.modules=0
  do.cleanup=1
  do.cleanuponabort=0
}

. tools/ak3-core.sh

# ---- Device Detection (FIX unsupported device) ----
DEVICE="$(getprop ro.product.device)"
DEVICE_ALT="$(getprop ro.build.product)"

ui_print " "
ui_print "📱 Detected device: $DEVICE"
ui_print "📱 Alt device: $DEVICE_ALT"

# Accept ANY device passed by CI (universal)
if [ -z "$DEVICE" ]; then
  abort "❌ Unable to detect device"
fi

# ---- Slot Detection (A/B safe) ----
SLOT="$(getprop ro.boot.slot_suffix)"
[ -z "$SLOT" ] && SLOT="$(getprop ro.boot.slot)"
[ -z "$SLOT" ] && SLOT=""

ui_print "📀 Slot: ${SLOT:-A-only}"

# ---- Boot Image Detection ----
if [ -e /dev/block/bootdevice/by-name/boot$SLOT ]; then
  block=/dev/block/bootdevice/by-name/boot$SLOT
elif [ -e /dev/block/by-name/boot$SLOT ]; then
  block=/dev/block/by-name/boot$SLOT
else
  abort "❌ Boot partition not found"
fi

ui_print "🧠 Boot block: $block"

# ---- Flash Kernel ----
dump_boot

write_boot

ui_print "✅ Kernel flashed successfully"
