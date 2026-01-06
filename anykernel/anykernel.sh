#!/sbin/sh
#
# AnyKernel3 Installer (Universal Modern UI)
#

# -----------------------------
# Pre-core boot partition detection
# -----------------------------
SLOT_SUFFIX="$(getprop ro.boot.slot_suffix 2>/dev/null)"

detect_byname() {
  local n="$1" p
  for p in \
    "/dev/block/bootdevice/by-name/$n" \
    "/dev/block/by-name/$n" \
    /dev/block/platform/*/by-name/"$n" \
    /dev/block/platform/*/*/by-name/"$n" \
    "/dev/block/mapper/$n"
  do
    [ -e "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

AK3_BLOCK=""
AK3_IS_SLOT_DEVICE=""

if [ -n "$SLOT_SUFFIX" ]; then
  p="$(detect_byname boot 2>/dev/null || true)"
  if [ -n "$p" ]; then
    AK3_BLOCK="$p"
    AK3_IS_SLOT_DEVICE="1"
  else
    p="$(detect_byname "boot${SLOT_SUFFIX}" 2>/dev/null || true)"
    if [ -n "$p" ]; then
      AK3_BLOCK="$p"
      AK3_IS_SLOT_DEVICE="0"
    fi
  fi
else
  p="$(detect_byname boot 2>/dev/null || true)"
  [ -n "$p" ] && AK3_BLOCK="$p" && AK3_IS_SLOT_DEVICE="0"
fi

[ -n "$AK3_BLOCK" ] && block="$AK3_BLOCK"
[ -n "$AK3_IS_SLOT_DEVICE" ] && is_slot_device="$AK3_IS_SLOT_DEVICE"

# -----------------------------
# AnyKernel properties
# -----------------------------
properties() {
cat <<'EOF'
kernel.string=Custom Kernel
do.devicecheck=0
do.modules=0
do.cleanup=1
do.cleanuponabort=0
device.name1=universal
device.name2=
EOF
[ -n "${AK3_BLOCK:-}" ] && printf 'block=%s\n' "$AK3_BLOCK"
[ -n "${AK3_IS_SLOT_DEVICE:-}" ] && printf 'is_slot_device=%s\n' "$AK3_IS_SLOT_DEVICE"
}

# -----------------------------
# Load AnyKernel core
# -----------------------------
. tools/ak3-core.sh

# -----------------------------
# UI helpers
# -----------------------------
_has() { command -v "$1" >/dev/null 2>&1; }
ui() { if _has ui_print; then ui_print "$1"; else echo "$1"; fi; }

bar() { ui "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
h1()  { ui " "; bar; ui "$1"; bar; }

KERNEL_LABEL="$(grep -m1 '^kernel.string=' "$0" 2>/dev/null | cut -d= -f2-)"
[ -z "$KERNEL_LABEL" ] && KERNEL_LABEL="Custom Kernel"

MODEL="$(getprop ro.product.model 2>/dev/null)"
CODENAME="$(getprop ro.product.device 2>/dev/null)"
ANDROID="$(getprop ro.build.version.release 2>/dev/null)"

# -----------------------------
# Start
# -----------------------------
h1 "✨ Kernel Installer"
ui "📌 Kernel: $KERNEL_LABEL"
[ -n "$MODEL" ] && ui "📱 Device: $MODEL"
[ -n "$CODENAME" ] && ui "🏷 Codename: $CODENAME"
[ -n "$ANDROID" ] && ui "🤖 Android: $ANDROID"
[ -n "$SLOT_SUFFIX" ] && ui "🧩 Slot: $SLOT_SUFFIX" || ui "🧩 Slot: N/A"
[ -n "${block:-}" ] && ui "🧱 Boot block: $block"

# Kernel image detection
KERNEL_IMAGE=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  [ -f "$f" ] && KERNEL_IMAGE="$f" && break
done
[ -z "$KERNEL_IMAGE" ] && abort "❌ No kernel image found in zip!"

ui "📦 Kernel image: $KERNEL_IMAGE"

# Flash flow
h1 "⚙️ Patching boot.img"
ui "🔍 Dumping boot..."
dump_boot

ui "🧩 Unpacking boot..."
unpack_boot

ui "🧠 Replacing kernel..."
replace_kernel "$KERNEL_IMAGE"

ui "🧱 Repacking boot..."
repack_boot

ui "🚀 Flashing boot..."
flash_boot

h1 "✅ Done"
ui "🎉 Flash completed successfully."
ui "🔁 Reboot system."
ui " "
