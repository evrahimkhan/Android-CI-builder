#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"

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

# Set base URLs to empty since image repacking has been removed
BASE_BOOT_URL=""
BASE_VENDOR_BOOT_URL=""
BASE_INIT_BOOT_URL=""

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

cat > anykernel/build-info.txt <<EOF
✨ Android Kernel CI Artifact
Device: ${DEVICE}
Kernel: ${KERNEL_VERSION:-unknown}
Type: ${KERNEL_TYPE:-unknown}
Clang: ${CLANG_VERSION:-unknown}
Image: ${KIMG}
CI: ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT}
SHA: ${GITHUB_SHA}

Base boot.img URL: (not provided - image repacking removed)
Base vendor_boot URL: (not provided - image repacking removed)
Base init_boot URL: (not provided - image repacking removed)

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

# Set image variables to empty since repack process is disabled
echo "BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
echo "VENDOR_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
echo "INIT_BOOT_IMG_XZ_NAME=" >> "$GITHUB_ENV"
