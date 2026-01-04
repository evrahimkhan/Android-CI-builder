#!/sbin/sh
#
# AnyKernel3 Installer (Universal)
#

# ------------------------------------------------------------
# Pre-core boot partition detection
# Fixes: "Unable to determine partition. Aborting..."
# ------------------------------------------------------------
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
  if [ -n "$p" ]; then
    AK3_BLOCK="$p"
    AK3_IS_SLOT_DEVICE="0"
  fi
fi

[ -n "$AK3_BLOCK" ] && block="$AK3_BLOCK"
[ -n "$AK3_IS_SLOT_DEVICE" ] && is_slot_device="$AK3_IS_SLOT_DEVICE"

# ------------------------------------------------------------
# AnyKernel properties
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Load AnyKernel3 core
# ------------------------------------------------------------
if [ -f tools/ak3-core.sh ]; then
  . tools/ak3-core.sh
else
  echo "ERROR: Missing tools/ak3-core.sh"
  exit 1
fi

# ------------------------------------------------------------
# Universal printing helpers
# ------------------------------------------------------------
_has() { command -v "$1" >/dev/null 2>&1; }

_print() {
  if _has ui_print; then ui_print "$1"; else echo "$1"; fi
}

USE_COLOR=0
USE_UNICODE=0

if [ "$USE_COLOR" = "1" ]; then
  RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
  BLUE='\033[1;34m'; CYAN='\033[1;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

if [ "$USE_UNICODE" = "1" ]; then
  OK="✔"; WARN="!"; BAR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  OK="OK"; WARN="WARN"; BAR="=================================="
fi

progress() { _print "${CYAN}[$1%]${NC} $2"; }
success()  { _print "${GREEN}[${OK}]${NC} $1"; }
warn()     { _print "${YELLOW}[${WARN}]${NC} $1"; }

header() {
  _print " "
  _print "${BLUE}${BAR}${NC}"
  _print "${CYAN}$1${NC}"
  _print "${BLUE}${BAR}${NC}"
}

KERNEL_LABEL="$(grep -m1 '^kernel.string=' "$0" 2>/dev/null | cut -d= -f2-)"
[ -z "$KERNEL_LABEL" ] && KERNEL_LABEL="Custom Kernel"

header "AnyKernel3 Universal Installer"
progress 5 "Initializing"
success "Environment ready"

MODEL="$(getprop ro.product.model 2>/dev/null)"
CODENAME="$(getprop ro.product.device 2>/dev/null)"
ANDROID="$(getprop ro.build.version.release 2>/dev/null)"
ROM="$(getprop ro.build.display.id 2>/dev/null)"

progress 10 "Reading device information"
[ -n "$MODEL" ] && _print "Device:   $MODEL"
[ -n "$CODENAME" ] && _print "Codename: $CODENAME"
[ -n "$ANDROID" ] && _print "Android:  $ANDROID"
[ -n "$ROM" ] && _print "ROM:      $ROM"
success "Device info loaded"

progress 15 "Detecting slot"
if [ -n "$SLOT_SUFFIX" ]; then
  _print "Active slot suffix: $SLOT_SUFFIX"
  success "A/B device detected"
else
  warn "No slot suffix reported (may be A-only)"
fi

progress 20 "Boot partition"
if [ -n "${block:-}" ]; then
  _print "Boot block: $block"
  success "Boot block resolved"
else
  warn "Boot block not resolved (core may still attempt autodetect)"
fi

progress 25 "Detecting kernel image"
KERNEL_IMAGE=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  [ -f "$f" ] && KERNEL_IMAGE="$f" && break
done
[ -z "$KERNEL_IMAGE" ] && abort "ERROR: No kernel image found in zip (expected Image*, zImage)."

_print "Kernel image file: $KERNEL_IMAGE"
success "Kernel image detected"

progress 40 "Dumping boot image"
dump_boot
success "Boot image dumped"

progress 55 "Unpacking boot image"
unpack_boot
success "Boot image unpacked"

progress 70 "Replacing kernel"
replace_kernel "$KERNEL_IMAGE"
success "Kernel replaced"

progress 85 "Repacking boot image"
repack_boot
success "Boot image repacked"

progress 95 "Flashing boot"
flash_boot
success "Boot flashed"

progress 100 "Finalizing"
header "Flash Summary"
[ -n "$MODEL" ] && _print "Device:  $MODEL"
[ -n "$CODENAME" ] && _print "Code:    $CODENAME"
[ -n "$ANDROID" ] && _print "Android: $ANDROID"
_print "Slot:    ${SLOT_SUFFIX:-N/A}"
_print "Image:   $KERNEL_IMAGE"
_print "Kernel:  $KERNEL_LABEL"

_print " "
_print "${GREEN}DONE.${NC} Reboot system."
_print " "
