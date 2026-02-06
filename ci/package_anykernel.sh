#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:?device required}"

# Simple error logging function (same as in telegram.sh)
log_err() { echo "[package_anykernel] $*" >&2; }

# Determine kernel variant for ZIP naming and notifications
# Based on NETHUNTER_ENABLED and NETHUNTER_CONFIG_LEVEL environment variables
if [ "${NETHUNTER_ENABLED:-false}" == "true" ]; then
  if [ "${NETHUNTER_CONFIG_LEVEL:-basic}" == "full" ]; then
    ZIP_VARIANT="full-nethunter"
  else
    ZIP_VARIANT="basic-nethunter"
  fi
else
  ZIP_VARIANT="normal"
fi

# Export for Telegram notifications
echo "ZIP_VARIANT=${ZIP_VARIANT}" >> "$GITHUB_ENV"

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


KERNELDIR="kernel/out/arch/arm64/boot"
test -d "$KERNELDIR"

rm -f anykernel/Image* anykernel/zImage 2>/dev/null || true

KIMG=""
for f in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage; do
  if [ -f "${KERNELDIR}/${f}" ]; then
    KIMG="$f"
    cp -f "${KERNELDIR}/${f}" "anykernel/${f}"
    break
  fi
done

if [ -z "$KIMG" ]; then
  echo "No kernel image found in ${KERNELDIR}"
  ls -la "$KERNELDIR" || true
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

Custom config enabled: ${CUSTOM_CONFIG_ENABLED:-false}
CONFIG_LOCALVERSION: ${CFG_LOCALVERSION:--CI}
CONFIG_DEFAULT_HOSTNAME: ${CFG_DEFAULT_HOSTNAME:-CI Builder}
CONFIG_UNAME_OVERRIDE_STRING: ${CFG_UNAME_OVERRIDE_STRING:-}
CONFIG_CC_VERSION_TEXT: ${CFG_CC_VERSION_TEXT:-auto}
EOF

KSTR="✨ ${DEVICE} • Linux ${KERNEL_VERSION:-unknown} • CI ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT}"

# More comprehensive sanitization for sed operations
KSTR_ESC=$(printf '%s\n' "$KSTR" | sed 's/[[\.*^$()+?{|]/\\&/g; s/&/\\&/g; s/\//\\\//g; s/\n/\\n/g')

# Validate that the sanitized string doesn't contain problematic sequences
if [[ "$KSTR_ESC" =~ \$\(|\`\(|sh\(|bash\(|\|.*\> ]] || [[ "$KSTR_ESC" == *">>"* ]]; then
  echo "ERROR: Sanitized string contains potentially dangerous sequences" >&2
  exit 1
fi

sed -i "s|^[[:space:]]*kernel.string=.*|kernel.string=${KSTR_ESC}|" anykernel/anykernel.sh || true
sed -i "s|^[[:space:]]*device.name1=.*|device.name1=${DEVICE}|" anykernel/anykernel.sh || true

ZIP_NAME="Kernel-${DEVICE}-${ZIP_VARIANT}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.zip"
(cd anykernel && zip -r9 "../${ZIP_NAME}" . -x "*.git*" ) || { echo "ERROR: ZIP creation failed"; exit 1; }

printf "Built for %s | Linux %s | CI %s/%s\n" \
  "${DEVICE}" "${KERNEL_VERSION:-unknown}" "${GITHUB_RUN_ID}" "${GITHUB_RUN_ATTEMPT}" \
  | zip -z "../${ZIP_NAME}" >/dev/null || log_err "Failed to add comment to ZIP"

echo "ZIP_NAME=${ZIP_NAME}" >> "$GITHUB_ENV"
echo "KERNEL_IMAGE_FILE=${KIMG}" >> "$GITHUB_ENV"

# No boot image variables to set since image repacking process has been removed
# Only AnyKernel ZIP is generated for flashing
