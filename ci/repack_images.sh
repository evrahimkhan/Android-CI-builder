#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"
BASE_BOOT_URL="${2:-}"
BASE_VENDOR_BOOT_URL="${3:-}"
BASE_INIT_BOOT_URL="${4:-}"

# Validate device name to prevent path traversal
if [[ ! "$DEVICE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: Invalid device name format: $DEVICE" >&2
  exit 1
fi

# Validate GITHUB_ENV to prevent path traversal
if [[ ! "$GITHUB_ENV" =~ ^/ ]]; then
  echo "ERROR: GITHUB_ENV must be an absolute path: $GITHUB_ENV" >&2
  exit 1
fi

if [[ "$GITHUB_ENV" == *".."* ]]; then
  echo "ERROR: GITHUB_ENV contains invalid characters: $GITHUB_ENV" >&2
  exit 1
fi

BOOTDIR="kernel/out/arch/arm64/boot"
test -d "$BOOTDIR"

ts() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
log() { echo "[$(ts)] [skip] $*"; }

show_file() {
  local f="$1"
  [ -f "$f" ] || { log "missing file: $f"; return 1; }
  local sz
  sz="$(stat -c%s "$f" 2>/dev/null || echo 0)"
  log "file: $f (bytes=$sz)"
  return 0
}

log "Skipping boot image repacking process as requested"
log "Only kernel image will be used in AnyKernel ZIP packaging"

KIMG=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  if [ -f "${BOOTDIR}/${f}" ]; then
    KIMG="$f"
    break
  fi
done

if [ -z "$KIMG" ]; then
  log "ERROR: No kernel image found in ${BOOTDIR}"
  ls -la "$BOOTDIR" || true
  exit 1
fi

KIMG_PATH="${BOOTDIR}/${KIMG}"
log "Selected kernel image: ${KIMG_PATH}"
show_file "$KIMG_PATH"

# Skip image repacking and set mode to skip
echo "BOOT_IMG_MODE=skip" >> "$GITHUB_ENV"
echo "BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
echo "VENDOR_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
echo "INIT_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"

log "Skipped boot image repacking. Kernel image ready for AnyKernel ZIP packaging."
exit 0
