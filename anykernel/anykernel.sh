#!/sbin/sh
#
# AnyKernel3 Installer (Universal)
#

# ------------------------------------------------------------
# AnyKernel "properties" block
# These dotted keys are read by AK3 core; do NOT use them as shell vars.
# ------------------------------------------------------------
properties() {
kernel.string=Custom Kernel
do.devicecheck=0
do.modules=0
do.cleanup=1
do.cleanuponabort=0

# Optional (disable universal behavior if you enable devicecheck):
# device.name1=moonstone
# device.name2=

# Optional: hardcode boot block if you know it:
# block=/dev/block/bootdevice/by-name/boot
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
  if _has ui_print; then
    ui_print "$1"
  else
    echo "$1"
  fi
}

# Default to plain output for universality
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

# Read kernel.string for display (since $kernel.string is not a shell variable)
KERNEL_LABEL="$(grep -m1 '^kernel.string=' "$0" 2>/dev/null | cut -d= -f2-)"
[ -z "$KERNEL_LABEL" ] && KERNEL_LABEL="Custom Kernel"

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------
header "AnyKernel3 Universal Installer"
progress 5 "Initializing"
success "Environment ready"

# ------------------------------------------------------------
# Device info (best-effort)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Slot info (informational only)
# ------------------------------------------------------------
progress 15 "Detecting slot"
SLOT_SUFFIX="$(getprop ro.boot.slot_suffix 2>/dev/null)"
if [ -n "$SLOT_SUFFIX" ]; then
  _print "Active slot suffix: $SLOT_SUFFIX"
  success "A/B device detected"
else
  warn "No slot suffix reported (may be A-only)"
fi

# ------------------------------------------------------------
# Boot block detection (universal)
# Prefer slot-specific boot_a/boot_b if slot suffix exists.
# ------------------------------------------------------------
progress 20 "Detecting boot partition block device"

if [ -z "${block:-}" ] && _has find_block && [ -n "$SLOT_SUFFIX" ]; then
  block="$(find_block "boot${SLOT_SUFFIX}" 2>/dev/null)"
fi

if [ -z "${block:-}" ] && _has find_block; then
  block="$(find_block boot 2>/dev/null)"
fi

# Fallbacks for recoveries where find_block is limited:
if [ -z "${block:-}" ]; then
  # Try slot-specific by-name paths if we have suffix
  if [ -n "$SLOT_SUFFIX" ]; then
    for p in \
      "/dev/block/bootdevice/by-name/boot${SLOT_SUFFIX}" \
      "/dev/block/by-name/boot${SLOT_SUFFIX}" \
      /dev/block/platform/*/by-name/boot"${SLOT_SUFFIX}" \
      /dev/block/platform/*/*/by-name/boot"${SLOT_SUFFIX}"
    do
      [ -e "$p" ] && block="$p" && break
    done
  fi
fi

if [ -z "${block:-}" ]; then
  for p in \
    /dev/block/bootdevice/by-name/boot \
    /dev/block/by-name/boot \
    /dev/block/platform/*/by-name/boot \
    /dev/block/platform/*/*/by-name/boot
  do
    [ -e "$p" ] && block="$p" && break
  done
fi

[ -z "${block:-}" ] && abort "ERROR: Could not detect boot partition block device. Set 'block=' in properties()."

_print "Boot block: $block"
success "Boot partition detected"

# ------------------------------------------------------------
# Kernel image detection (universal)
# ------------------------------------------------------------
progress 25 "Detecting kernel image"

KERNEL_IMAGE=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  if [ -f "$f" ]; then
    KERNEL_IMAGE="$f"
    break
  fi
done

[ -z "$KERNEL_IMAGE" ] && abort "ERROR: No kernel image found in zip (expected Image*, zImage)."

_print "Kernel image file: $KERNEL_IMAGE"
success "Kernel image detected"

# ------------------------------------------------------------
# Boot image flow
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
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
