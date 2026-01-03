#!/sbin/sh
#
# AnyKernel3 Installer
# Enhanced Professional Installer UI
#

### ─── BASIC CONFIG ───────────────────────────────────────────
kernel.string=Custom Kernel
do.devicecheck=1
do.modules=0
do.cleanup=1
do.cleanuponabort=0

### ─── SUPPORTED DEVICES (OPTIONAL) ───────────────────────────
device.name1=moonstone
device.name2=

### ─── UI COLOR CODES (RECOVERY SAFE) ─────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

### ─── LOAD ANYKERNEL CORE ────────────────────────────────────
. tools/ak3-core.sh

### ─── UI HELPERS ─────────────────────────────────────────────
progress() {
  ui_print "${CYAN}[$1%]${NC} $2"
}

success() {
  ui_print "${GREEN}✔ $1${NC}"
}

warn() {
  ui_print "${YELLOW}⚠️  $1${NC}"
}

header() {
  ui_print " "
  ui_print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  ui_print "${CYAN}$1${NC}"
  ui_print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

### ─── START ──────────────────────────────────────────────────
header "Custom Kernel Installer"

progress 5 "Initializing installer"
success "Environment ready"

### ─── DEVICE INFO ────────────────────────────────────────────
MODEL="$(getprop ro.product.model)"
CODENAME="$(getprop ro.product.device)"
ANDROID="$(getprop ro.build.version.release)"
ROM="$(getprop ro.build.display.id)"
FINGERPRINT="$(getprop ro.build.fingerprint)"

progress 10 "Reading device information"
ui_print "${BLUE}📱 Device:${NC} $MODEL"
ui_print "${BLUE}🔖 Codename:${NC} $CODENAME"
ui_print "${BLUE}🤖 Android:${NC} $ANDROID"
ui_print "${BLUE}📀 ROM:${NC} $ROM"
success "Device info loaded"

### ─── SLOT DETECTION ──────────────────────────────────────────
progress 15 "Detecting active slot"
SLOT="$(getprop ro.boot.slot_suffix)"
[ -z "$SLOT" ] && SLOT="_a"
ui_print "${BLUE}🔀 Active Slot:${NC} $SLOT"
success "A/B slot detected"

### ─── OTA SAFETY BANNER ───────────────────────────────────────
ui_print " "
ui_print "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ui_print "${YELLOW}⚠️  OTA / A-B SAFE FLASH${NC}"
ui_print "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ui_print "• Only boot partition will be modified"
ui_print "• No system / vendor changes"
ui_print "• Safe for OTA & dirty flash"
ui_print " "

### ─── IMAGE AUTO DETECTION ────────────────────────────────────
progress 25 "Detecting kernel image format"

if [ -f Image.gz ]; then
  KERNEL_IMAGE="Image.gz"
  IMGTYPE="Image.gz"
elif [ -f Image.lz4 ]; then
  KERNEL_IMAGE="Image.lz4"
  IMGTYPE="Image.lz4"
elif [ -f Image ]; then
  KERNEL_IMAGE="Image"
  IMGTYPE="Image"
else
  abort "❌ No kernel Image found!"
fi

ui_print "${BLUE}📦 Kernel Image:${NC} $IMGTYPE"
success "Kernel image detected"

### ─── BOOT IMAGE PREP ─────────────────────────────────────────
progress 40 "Preparing boot image"
dump_boot
success "Boot image dumped"

### ─── UNPACK ─────────────────────────────────────────────────
progress 55 "Unpacking boot image"
unpack_boot
success "Boot image unpacked"

### ─── PATCH KERNEL ───────────────────────────────────────────
progress 70 "Patching kernel"
replace_kernel "$KERNEL_IMAGE"
success "Kernel patched"

### ─── REPACK ────────────────────────────────────────────────
progress 85 "Repacking boot image"
repack_boot
success "Boot image repacked"

### ─── FLASH ─────────────────────────────────────────────────
progress 95 "Flashing to active slot $SLOT"
flash_boot
success "Boot image flashed"

### ─── FINAL SUMMARY ─────────────────────────────────────────
progress 100 "Finalizing installation"

header "Flash Summary"

ui_print "${BLUE}📱 Device:${NC} $MODEL"
ui_print "${BLUE}🔖 Codename:${NC} $CODENAME"
ui_print "${BLUE}🤖 Android:${NC} $ANDROID"
ui_print "${BLUE}🔀 Slot:${NC} $SLOT"
ui_print "${BLUE}📦 Image:${NC} $IMGTYPE"
ui_print "${BLUE}🧩 Kernel:${NC} $kernel.string"

ui_print " "
ui_print "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ui_print "${GREEN}✅ FLASH COMPLETED SUCCESSFULLY${NC}"
ui_print "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ui_print "${GREEN}🎉 Reboot and enjoy!${NC}"
ui_print " "
