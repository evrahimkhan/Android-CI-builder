#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"
BASE_BOOT_URL="${2:-}"
BASE_VENDOR_BOOT_URL="${3:-}"
BASE_INIT_BOOT_URL="${4:-}"

BOOTDIR="kernel/out/arch/arm64/boot"
test -d "$BOOTDIR"

command -v mkbootimg >/dev/null 2>&1 || { echo "mkbootimg not found on PATH (run ci/setup_aosp_mkbootimg.sh)"; exit 1; }

# output flag detection
OUTFLAG="--output"
if mkbootimg --help 2>/dev/null | grep -qE '(^|[[:space:]])-o[[:space:]]+OUTPUT\b' && ! mkbootimg --help 2>/dev/null | grep -q -- '--output'; then
  OUTFLAG="-o"
fi

# Pick kernel image
KIMG=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  [ -f "${BOOTDIR}/${f}" ] && KIMG="$f" && break
done
[ -n "$KIMG" ] || { echo "No kernel image found in ${BOOTDIR}"; ls -la "$BOOTDIR" || true; exit 1; }

KIMG_PATH="${BOOTDIR}/${KIMG}"
EMPTY_RD="$(mktemp)"; : > "$EMPTY_RD"

OUT_BOOT_RAW="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
OUT_BOOT_XZ="${OUT_BOOT_RAW}.xz"
echo "BOOT_IMG_NAME=${OUT_BOOT_RAW}" >> "$GITHUB_ENV"
echo "BOOT_IMG_XZ_NAME=${OUT_BOOT_XZ}" >> "$GITHUB_ENV"

BOOT_MODE="minimal"

pick1() { find "$1" -maxdepth 3 -type f -iname "$2" 2>/dev/null | head -n1 || true; }

if [ -n "$BASE_BOOT_URL" ] && command -v unpack_bootimg >/dev/null 2>&1; then
  echo "Repacking boot.img from base (recommended)."
  curl -L --fail -o base_boot.img "$BASE_BOOT_URL"

  rm -rf boot-unpack
  mkdir -p boot-unpack
  unpack_bootimg --boot_img base_boot.img --out boot-unpack >/dev/null 2>&1 || true

  RAMDISK="$(pick1 boot-unpack '*ramdisk*')"
  [ -z "$RAMDISK" ] && RAMDISK="$EMPTY_RD"

  DTB="$(pick1 boot-unpack '*dtb*')"
  BOOTCONFIG="$(pick1 boot-unpack '*bootconfig*')"

  CMDLINE_FILE="$(pick1 boot-unpack '*cmdline*')"
  CMDLINE=""
  [ -n "$CMDLINE_FILE" ] && CMDLINE="$(cat "$CMDLINE_FILE" 2>/dev/null || true)"
  CMDLINE="${CMDLINE//$'\n'/ }"
  CMDLINE="${CMDLINE//$'\r'/}"

  HV_FILE="$(pick1 boot-unpack '*header_version*')"
  HV="0"; [ -n "$HV_FILE" ] && HV="$(cat "$HV_FILE" 2>/dev/null || echo 0)"

  OSV_FILE="$(pick1 boot-unpack '*os_version*')"
  OSP_FILE="$(pick1 boot-unpack '*os_patch_level*')"
  OSV=""; OSP=""
  [ -n "$OSV_FILE" ] && OSV="$(cat "$OSV_FILE" 2>/dev/null || true)"
  [ -n "$OSP_FILE" ] && OSP="$(cat "$OSP_FILE" 2>/dev/null || true)"

  ARGS=( --kernel "$KIMG_PATH" --ramdisk "$RAMDISK" --cmdline "$CMDLINE" --header_version "$HV" )
  [ -n "$OSV" ] && ARGS+=( --os_version "$OSV" )
  [ -n "$OSP" ] && ARGS+=( --os_patch_level "$OSP" )
  [ -n "$DTB" ] && ARGS+=( --dtb "$DTB" )

  if [ -n "$BOOTCONFIG" ] && mkbootimg --help 2>/dev/null | grep -q -- '--bootconfig'; then
    ARGS+=( --bootconfig "$BOOTCONFIG" )
  fi

  ARGS+=( "$OUTFLAG" "$OUT_BOOT_RAW" )

  set +e
  mkbootimg "${ARGS[@]}"
  RC=$?
  set -e

  if [ "$RC" -eq 0 ] && [ -s "$OUT_BOOT_RAW" ]; then
    BOOT_MODE="repacked"
  fi
fi

if [ "$BOOT_MODE" != "repacked" ]; then
  mkbootimg --kernel "$KIMG_PATH" --ramdisk "$EMPTY_RD" --cmdline "" --header_version 0 "$OUTFLAG" "$OUT_BOOT_RAW"
  BOOT_MODE="minimal"
fi

echo "BOOT_IMG_MODE=${BOOT_MODE}" >> "$GITHUB_ENV"

# Compress boot.img (upload only compressed)
xz -T0 -9 -f "$OUT_BOOT_RAW"
[ -f "$OUT_BOOT_XZ" ] || { echo "boot.img.xz not created"; exit 1; }

# vendor_boot/init_boot downloads + compress (upload only compressed)
if [ -n "$BASE_VENDOR_BOOT_URL" ]; then
  VBOOT_RAW="vendor_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  VBOOT_XZ="${VBOOT_RAW}.xz"
  echo "VENDOR_BOOT_IMG_NAME=${VBOOT_RAW}" >> "$GITHUB_ENV"
  echo "VENDOR_BOOT_IMG_XZ_NAME=${VBOOT_XZ}" >> "$GITHUB_ENV"
  curl -L --fail -o "$VBOOT_RAW" "$BASE_VENDOR_BOOT_URL"
  xz -T0 -9 -f "$VBOOT_RAW"
else
  echo "VENDOR_BOOT_IMG_NAME=" >> "$GITHUB_ENV"
  echo "VENDOR_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
fi

if [ -n "$BASE_INIT_BOOT_URL" ]; then
  IBOOT_RAW="init_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  IBOOT_XZ="${IBOOT_RAW}.xz"
  echo "INIT_BOOT_IMG_NAME=${IBOOT_RAW}" >> "$GITHUB_ENV"
  echo "INIT_BOOT_IMG_XZ_NAME=${IBOOT_XZ}" >> "$GITHUB_ENV"
  curl -L --fail -o "$IBOOT_RAW" "$BASE_INIT_BOOT_URL"
  xz -T0 -9 -f "$IBOOT_RAW"
else
  echo "INIT_BOOT_IMG_NAME=" >> "$GITHUB_ENV"
  echo "INIT_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
fi
