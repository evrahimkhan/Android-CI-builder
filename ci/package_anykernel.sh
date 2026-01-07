#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"
BASE_BOOT_URL="${2:-}"
BASE_VENDOR_BOOT_URL="${3:-}"
BASE_INIT_BOOT_URL="${4:-}"

BOOTDIR="kernel/out/arch/arm64/boot"
test -d "$BOOTDIR"

rm -f anykernel/Image* anykernel/zImage 2>/dev/null || true

# Pick kernel image
KIMG=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  if [ -f "${BOOTDIR}/${f}" ]; then
    KIMG="$f"
    cp -f "${BOOTDIR}/${f}" "anykernel/${f}"
    break
  fi
done

if [ -z "$KIMG" ]; then
  echo "No kernel image found in ${BOOTDIR}"
  ls -la "$BOOTDIR" || true
  exit 1
fi

# Build info in zip
cat > anykernel/build-info.txt <<EOF
✨ Android Kernel CI Artifact
Device: ${DEVICE}
Kernel: ${KERNEL_VERSION:-unknown}
Type: ${KERNEL_TYPE:-unknown}
Clang: ${CLANG_VERSION:-unknown}
Image: ${KIMG}
CI: ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT}
SHA: ${GITHUB_SHA}

Base boot.img URL: ${BASE_BOOT_URL:-}
Base vendor_boot URL: ${BASE_VENDOR_BOOT_URL:-}
Base init_boot URL: ${BASE_INIT_BOOT_URL:-}

Custom config enabled: ${CUSTOM_CONFIG_ENABLED:-false}
CONFIG_LOCALVERSION: ${CFG_LOCALVERSION:--CI}
CONFIG_DEFAULT_HOSTNAME: ${CFG_DEFAULT_HOSTNAME:-CI Builder}
CONFIG_UNAME_OVERRIDE_STRING: ${CFG_UNAME_OVERRIDE_STRING:-}
CONFIG_CC_VERSION_TEXT: ${CFG_CC_VERSION_TEXT:-auto}
EOF

# Installer label
KSTR="✨ ${DEVICE} • Linux ${KERNEL_VERSION:-unknown} • CI ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT}"
KSTR_ESC="${KSTR//&/\\&}"
sed -i "s|^[[:space:]]*kernel.string=.*|kernel.string=${KSTR_ESC}|" anykernel/anykernel.sh || true
sed -i "s|^[[:space:]]*device.name1=.*|device.name1=${DEVICE}|" anykernel/anykernel.sh || true

ZIP_NAME="Kernel-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.zip"
(cd anykernel && zip -r9 "../${ZIP_NAME}" . -x "*.git*" )

printf "Built for %s | Linux %s | CI %s/%s\n" \
  "${DEVICE}" "${KERNEL_VERSION:-unknown}" "${GITHUB_RUN_ID}" "${GITHUB_RUN_ATTEMPT}" \
  | zip -z "../${ZIP_NAME}" >/dev/null || true

echo "ZIP_NAME=${ZIP_NAME}" >> "$GITHUB_ENV"
echo "KERNEL_IMAGE_FILE=${KIMG}" >> "$GITHUB_ENV"

# ---- boot.img generation (repack from base strongly recommended) ----
OUT_BOOT="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
echo "BOOT_IMG_NAME=${OUT_BOOT}" >> "$GITHUB_ENV"

command -v mkbootimg >/dev/null 2>&1 || { echo "mkbootimg not found (run ci/setup_aosp_mkbootimg.sh)"; exit 1; }

# output flag detection
OUTFLAG="--output"
if mkbootimg --help 2>/dev/null | grep -qE '(^|[[:space:]])-o[[:space:]]+OUTPUT\b' && ! mkbootimg --help 2>/dev/null | grep -q -- '--output'; then
  OUTFLAG="-o"
fi

KIMG_PATH="${BOOTDIR}/${KIMG}"
EMPTY_RD="$(mktemp)"; : > "$EMPTY_RD"

BOOT_MODE="minimal"

pick1() { find "$1" -maxdepth 3 -type f -iname "$2" 2>/dev/null | head -n1 || true; }

# Try repack from base (preserves metadata; prevents fastboot boots on many devices)
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
    echo "Base repack failed; using minimal boot.img fallback (often not bootable)" >&2
  fi
fi

if [ "$BOOT_MODE" != "repacked" ]; then
  mkbootimg --kernel "$KIMG_PATH" --ramdisk "$EMPTY_RD" --cmdline "" --header_version 0 "$OUTFLAG" "$OUT_BOOT"
  BOOT_MODE="minimal"
fi

echo "BOOT_IMG_MODE=${BOOT_MODE}" >> "$GITHUB_ENV"

# ---- Optional: vendor_boot/init_boot “matching set” downloads ----
# NOTE: We do not repack vendor_boot/init_boot here; we provide them as matching base images.
# This is often what users actually need if their device expects vendor_boot/init_boot in addition to boot.
if [ -n "$BASE_VENDOR_BOOT_URL" ]; then
  VBOOT="vendor_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  echo "VENDOR_BOOT_IMG_NAME=${VBOOT}" >> "$GITHUB_ENV"
  echo "Downloading vendor_boot.img..."
  curl -L --fail -o "$VBOOT" "$BASE_VENDOR_BOOT_URL"
else
  echo "VENDOR_BOOT_IMG_NAME=" >> "$GITHUB_ENV"
fi

if [ -n "$BASE_INIT_BOOT_URL" ]; then
  IBOOT="init_boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
  echo "INIT_BOOT_IMG_NAME=${IBOOT}" >> "$GITHUB_ENV"
  echo "Downloading init_boot.img..."
  curl -L --fail -o "$IBOOT" "$BASE_INIT_BOOT_URL"
else
  echo "INIT_BOOT_IMG_NAME=" >> "$GITHUB_ENV"
fi
