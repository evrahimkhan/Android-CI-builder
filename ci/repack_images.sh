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

# Pick kernel image same order as AnyKernel
KIMG=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  [ -f "${BOOTDIR}/${f}" ] && KIMG="$f" && break
done
[ -n "$KIMG" ] || { echo "No kernel image found in ${BOOTDIR}"; ls -la "$BOOTDIR" || true; exit 1; }

KIMG_PATH="${BOOTDIR}/${KIMG}"
EMPTY_RD="$(mktemp)"; : > "$EMPTY_RD"

OUT_BOOT="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
echo "BOOT_IMG_NAME=${OUT_BOOT}" >> "$GITHUB_ENV"

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

  ARGS+=( "$OUTFLAG" "$OUT_BOOT" )

  set +e
  mkbootimg "${ARGS[@]}"
  RC=$?
  set -e

  if [ "$RC" -eq 0 ] && [ -s "$OUT_BOOT" ]; then
    BOOT_MODE="repacked"
  else
    echo "Base repack failed; creating minimal boot.img (often not bootable)" >&2
  fi
fi

if [ "$BOOT_MODE" != "repacked" ]; then
  mkbootimg --kernel "$KIMG_PATH" --ramdisk "$EMPTY_RD" --cmdline "" --header_version 0 "$OUTFLAG" "$OUT_BOOT"
  BOOT_MODE="minimal"
fi

echo "BOOT_IMG_MODE=${BOOT_MODE}" >> "$GITHUB_ENV"

# vendor_boot/init_boot download as matching set (optional)
if [ -n "$BASE_VENDOR_BOOT_URL" ]; then
  VBOOT="vendor_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  echo "VENDOR_BOOT_IMG_NAME=${VBOOT}" >> "$GITHUB_ENV"
  curl -L --fail -o "$VBOOT" "$BASE_VENDOR_BOOT_URL"
else
  echo "VENDOR_BOOT_IMG_NAME=" >> "$GITHUB_ENV"
fi

if [ -n "$BASE_INIT_BOOT_URL" ]; then
  IBOOT="init_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  echo "INIT_BOOT_IMG_NAME=${IBOOT}" >> "$GITHUB_ENV"
  curl -L --fail -o "$IBOOT" "$BASE_INIT_BOOT_URL"
else
  echo "INIT_BOOT_IMG_NAME=" >> "$GITHUB_ENV"
fi
