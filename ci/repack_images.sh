#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"
BASE_BOOT_URL="${2:-}"
BASE_VENDOR_BOOT_URL="${3:-}"
BASE_INIT_BOOT_URL="${4:-}"

BOOTDIR="kernel/out/arch/arm64/boot"
test -d "$BOOTDIR"

ts() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
log() { echo "[$(ts)] [repack] $*"; }

redact_url() {
  local u="$1"
  echo "${u%%\?*}"
}

show_file() {
  local f="$1"
  [ -f "$f" ] || { log "missing file: $f"; return 1; }
  local sz
  sz="$(stat -c%s "$f" 2>/dev/null || echo 0)"
  log "file: $f (bytes=$sz)"
  return 0
}

command -v mkbootimg >/dev/null 2>&1 || { log "ERROR: mkbootimg not found on PATH (run ci/setup_aosp_mkbootimg.sh)"; exit 1; }

OUTFLAG="--output"
if mkbootimg --help 2>/dev/null | grep -qE '(^|[[:space:]])-o[[:space:]]+OUTPUT\b' && ! mkbootimg --help 2>/dev/null | grep -q -- '--output'; then
  OUTFLAG="-o"
fi
log "mkbootimg OUTFLAG selected: ${OUTFLAG}"

SUPPORTS_BOOTCONFIG="0"
mkbootimg --help 2>/dev/null | grep -q -- '--bootconfig' && SUPPORTS_BOOTCONFIG="1"
log "mkbootimg supports --bootconfig: ${SUPPORTS_BOOTCONFIG}"

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

EMPTY_RD="$(mktemp)"
: > "$EMPTY_RD"
log "Created empty ramdisk: ${EMPTY_RD}"

OUT_BOOT_RAW="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
OUT_BOOT_XZ="${OUT_BOOT_RAW}.xz"
echo "BOOT_IMG_NAME=${OUT_BOOT_RAW}" >> "$GITHUB_ENV"
echo "BOOT_IMG_XZ_NAME=${OUT_BOOT_XZ}" >> "$GITHUB_ENV"

BOOT_MODE="minimal"

pick1() { find "$1" -maxdepth 3 -type f -iname "$2" 2>/dev/null | head -n1 || true; }

download_to() {
  local url="$1"
  local out="$2"
  log "Downloading: $(redact_url "$url") -> $out"
  curl -L --fail --retry 3 --retry-delay 2 --progress-bar -o "$out" "$url"
  show_file "$out"
}

if [ -n "$BASE_BOOT_URL" ]; then
  if command -v unpack_bootimg >/dev/null 2>&1; then
    log "Base boot.img provided: yes (will repack from base)"
    download_to "$BASE_BOOT_URL" base_boot.img

    rm -rf boot-unpack
    mkdir -p boot-unpack

    log "Running unpack_bootimg..."
    set +e
    unpack_bootimg --boot_img base_boot.img --out boot-unpack
    U_RC=$?
    set -e
    log "unpack_bootimg exit code: ${U_RC}"

    log "boot-unpack contents:"
    ls -la boot-unpack || true

    RAMDISK="$(pick1 boot-unpack '*ramdisk*')"
    DTB="$(pick1 boot-unpack '*dtb*')"
    BOOTCONFIG="$(pick1 boot-unpack '*bootconfig*')"
    CMDLINE_FILE="$(pick1 boot-unpack '*cmdline*')"
    HV_FILE="$(pick1 boot-unpack '*header_version*')"
    OSV_FILE="$(pick1 boot-unpack '*os_version*')"
    OSP_FILE="$(pick1 boot-unpack '*os_patch_level*')"

    [ -n "$RAMDISK" ] && show_file "$RAMDISK" || log "No ramdisk extracted; using empty ramdisk"
    [ -n "$DTB" ] && show_file "$DTB" || log "No DTB extracted"
    [ -n "$BOOTCONFIG" ] && show_file "$BOOTCONFIG" || log "No bootconfig extracted"

    CMDLINE=""
    if [ -n "$CMDLINE_FILE" ] && [ -f "$CMDLINE_FILE" ]; then
      CMDLINE="$(cat "$CMDLINE_FILE" 2>/dev/null || true)"
      CMDLINE="${CMDLINE//$'\n'/ }"
      CMDLINE="${CMDLINE//$'\r'/}"
    fi

    HV="0"
    [ -n "$HV_FILE" ] && HV="$(cat "$HV_FILE" 2>/dev/null || echo 0)"

    OSV=""
    OSP=""
    [ -n "$OSV_FILE" ] && OSV="$(cat "$OSV_FILE" 2>/dev/null || true)"
    [ -n "$OSP_FILE" ] && OSP="$(cat "$OSP_FILE" 2>/dev/null || true)"

    log "Extracted metadata:"
    log "  header_version: $HV"
    log "  os_version: ${OSV:-<empty>}"
    log "  os_patch_level: ${OSP:-<empty>}"
    log "  cmdline length: ${#CMDLINE}"
    log "  cmdline preview: ${CMDLINE:0:140}"

    ARGS=( --kernel "$KIMG_PATH" )
    if [ -n "$RAMDISK" ]; then
      ARGS+=( --ramdisk "$RAMDISK" )
    else
      ARGS+=( --ramdisk "$EMPTY_RD" )
    fi

    ARGS+=( --cmdline "$CMDLINE" )
    ARGS+=( --header_version "$HV" )

    [ -n "$OSV" ] && ARGS+=( --os_version "$OSV" )
    [ -n "$OSP" ] && ARGS+=( --os_patch_level "$OSP" )
    [ -n "$DTB" ] && ARGS+=( --dtb "$DTB" )

    if [ "$SUPPORTS_BOOTCONFIG" = "1" ] && [ -n "$BOOTCONFIG" ]; then
      ARGS+=( --bootconfig "$BOOTCONFIG" )
    fi

    ARGS+=( "$OUTFLAG" "$OUT_BOOT_RAW" )

    log "Running mkbootimg with arguments:"
    for a in "${ARGS[@]}"; do
      printf '[%s]\n' "$a"
    done

    set +e
    mkbootimg "${ARGS[@]}"
    RC=$?
    set -e

    log "mkbootimg exit code: ${RC}"
    if [ "$RC" -eq 0 ] && [ -s "$OUT_BOOT_RAW" ]; then
      BOOT_MODE="repacked"
      show_file "$OUT_BOOT_RAW"
    else
      log "Repack failed; will fall back to minimal boot.img"
    fi
  else
    log "Base boot.img provided, but unpack_bootimg not available on PATH. Repack skipped."
  fi
else
  log "No base_boot_img_url provided. Will generate minimal boot.img (often not bootable)."
fi

if [ "$BOOT_MODE" != "repacked" ]; then
  log "Generating minimal boot.img (fallback)."
  ARGS=( --kernel "$KIMG_PATH" --ramdisk "$EMPTY_RD" --cmdline "" --header_version 0 "$OUTFLAG" "$OUT_BOOT_RAW" )

  log "mkbootimg args (minimal):"
  for a in "${ARGS[@]}"; do printf '[%s]\n' "$a"; done

  mkbootimg "${ARGS[@]}"
  show_file "$OUT_BOOT_RAW"
  BOOT_MODE="minimal"
fi

echo "BOOT_IMG_MODE=${BOOT_MODE}" >> "$GITHUB_ENV"

log "Compressing boot.img -> ${OUT_BOOT_XZ}"
xz -T0 -9 -f "$OUT_BOOT_RAW"
show_file "$OUT_BOOT_XZ"

if [ -n "$BASE_VENDOR_BOOT_URL" ]; then
  VBOOT_RAW="vendor_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  VBOOT_XZ="${VBOOT_RAW}.xz"
  echo "VENDOR_BOOT_IMG_XZ_NAME=${VBOOT_XZ}" >> "$GITHUB_ENV"

  download_to "$BASE_VENDOR_BOOT_URL" "$VBOOT_RAW"
  log "Compressing vendor_boot -> ${VBOOT_XZ}"
  xz -T0 -9 -f "$VBOOT_RAW"
  show_file "$VBOOT_XZ"
else
  echo "VENDOR_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
  log "No base_vendor_boot_img_url provided."
fi

if [ -n "$BASE_INIT_BOOT_URL" ]; then
  IBOOT_RAW="init_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  IBOOT_XZ="${IBOOT_RAW}.xz"
  echo "INIT_BOOT_IMG_XZ_NAME=${IBOOT_XZ}" >> "$GITHUB_ENV"

  download_to "$BASE_INIT_BOOT_URL" "$IBOOT_RAW"
  log "Compressing init_boot -> ${IBOOT_XZ}"
  xz -T0 -9 -f "$IBOOT_RAW"
  show_file "$IBOOT_XZ"
else
  echo "INIT_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
  log "No base_init_boot_img_url provided."
fi

log "Done. BOOT_IMG_MODE=${BOOT_MODE}"
