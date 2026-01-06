#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"
BASE_BOOT_URL="${2:-}"

BOOTDIR="kernel/out/arch/arm64/boot"
test -d "$BOOTDIR"

rm -f anykernel/Image* anykernel/zImage 2>/dev/null || true

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

# --- Modern build info inside zip ---
cat > anykernel/build-info.txt <<EOF
✨ Android Kernel CI Artifact
Device: ${DEVICE}
Kernel: ${KERNEL_VERSION:-unknown}
Type: ${KERNEL_TYPE:-unknown}
Clang: ${CLANG_VERSION:-unknown}
Image: ${KIMG}
CI: ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT}
SHA: ${GITHUB_SHA}

Custom config enabled: ${CUSTOM_CONFIG_ENABLED:-false}
CONFIG_LOCALVERSION: ${CFG_LOCALVERSION:--CI}
CONFIG_DEFAULT_HOSTNAME: ${CFG_DEFAULT_HOSTNAME:-CI Builder}
CONFIG_UNAME_OVERRIDE_STRING: ${CFG_UNAME_OVERRIDE_STRING:-}
CONFIG_CC_VERSION_TEXT: ${CFG_CC_VERSION_TEXT:-auto}
EOF

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

# --- boot.img generation using AOSP mkbootimg (from ci/setup_aosp_mkbootimg.sh) ---
OUT_BOOT="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
echo "BOOT_IMG_NAME=${OUT_BOOT}" >> "$GITHUB_ENV"

command -v mkbootimg >/dev/null 2>&1 || { echo "mkbootimg not found on PATH"; exit 1; }

EMPTY_RD="$(mktemp)"
: > "$EMPTY_RD"

KIMG_PATH="${BOOTDIR}/${KIMG}"

# Best-effort: repack using base boot.img if provided AND unpack_bootimg exists
if [ -n "$BASE_BOOT_URL" ] && command -v unpack_bootimg >/dev/null 2>&1; then
  curl -L --fail -o base_boot.img "$BASE_BOOT_URL"

  rm -rf boot-unpack
  mkdir -p boot-unpack

  unpack_bootimg --boot_img base_boot.img --out boot-unpack >/dev/null 2>&1 || true

  RAMDISK="$(ls -1 boot-unpack/*ramdisk* 2>/dev/null | head -n1 || true)"
  [ -z "$RAMDISK" ] && RAMDISK="$EMPTY_RD"

  DTB="$(ls -1 boot-unpack/*dtb* 2>/dev/null | head -n1 || true)"

  CMDLINE_FILE="$(ls -1 boot-unpack/*cmdline* 2>/dev/null | head -n1 || true)"
  CMDLINE=""
  [ -n "$CMDLINE_FILE" ] && CMDLINE="$(cat "$CMDLINE_FILE" 2>/dev/null || true)"

  HV_FILE="$(ls -1 boot-unpack/*header_version* 2>/dev/null | head -n1 || true)"
  HV="0"
  [ -n "$HV_FILE" ] && HV="$(cat "$HV_FILE" 2>/dev/null || echo 0)"

  OSV_FILE="$(ls -1 boot-unpack/*os_version* 2>/dev/null | head -n1 || true)"
  OSP_FILE="$(ls -1 boot-unpack/*os_patch_level* 2>/dev/null | head -n1 || true)"
  OSV=""
  OSP=""
  [ -n "$OSV_FILE" ] && OSV="$(cat "$OSV_FILE" 2>/dev/null || true)"
  [ -n "$OSP_FILE" ] && OSP="$(cat "$OSP_FILE" 2>/dev/null || true)"

  set +e
  mkbootimg \
    --kernel "$KIMG_PATH" \
    --ramdisk "$RAMDISK" \
    --cmdline "$CMDLINE" \
    --header_version "$HV" \
    ${OSV:+--os_version "$OSV"} \
    ${OSP:+--os_patch_level "$OSP"} \
    ${DTB:+--dtb "$DTB"} \
    --output "$OUT_BOOT"
  RC=$?
  set -e

  if [ "$RC" -eq 0 ]; then
    exit 0
  fi
fi

# Fallback minimal boot.img
mkbootimg \
  --kernel "$KIMG_PATH" \
  --ramdisk "$EMPTY_RD" \
  --cmdline "" \
  --header_version 0 \
  --output "$OUT_BOOT"
