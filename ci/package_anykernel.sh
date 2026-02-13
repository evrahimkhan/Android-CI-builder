#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

DEVICE="${1:?device required}"

# Validate device name to prevent path traversal
if ! validate_device_name "$DEVICE"; then
  exit 1
fi

# Validate GITHUB_WORKSPACE to prevent path traversal
if ! validate_workspace; then
  exit 1
fi

# Validate GITHUB_ENV to prevent path traversal
if ! validate_github_env; then
  exit 1
fi

# Simple error logging function (same as in telegram.sh)
log_err() { printf "[package_anykernel] %s\n" "$*" >&2; }

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
printf "ZIP_VARIANT=%s\n" "$ZIP_VARIANT" >> "$GITHUB_ENV"


# Determine kernel directory with proper validation
KERNEL_DIR="${KERNEL_DIR:-${GITHUB_WORKSPACE}/kernel}"
KERNELDIR="${KERNEL_DIR}/out/arch/arm64/boot"
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
  printf "ERROR: No kernel image found in %s\n" "$KERNELDIR" >&2
  printf "Available files:\n" >&2
  ls -la "$KERNELDIR" >&2 || true
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

# Validate that the sanitized string doesn't contain newlines or control characters
if [[ "$KSTR_ESC" == *$'\n'* ]] || [[ "$KSTR_ESC" == *$'\r'* ]]; then
  printf "ERROR: Sanitized string contains newlines or control characters\n" >&2
  exit 1
fi

# Validate file exists before sed operations
if [ ! -f anykernel/anykernel.sh ]; then
  printf "ERROR: anykernel/anykernel.sh not found\n" >&2
  exit 1
fi

sed -i "s|^[[:space:]]*kernel.string=.*|kernel.string=${KSTR_ESC}|" anykernel/anykernel.sh
sed -i "s|^[[:space:]]*device.name1=.*|device.name1=${DEVICE}|" anykernel/anykernel.sh

ZIP_NAME="Kernel-${DEVICE}-${ZIP_VARIANT}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.zip"

# Validate ZIP_NAME doesn't contain path traversal
if [[ "$ZIP_NAME" =~ \.\. ]] || [[ "$ZIP_NAME" =~ ^/ ]]; then
  printf "ERROR: Invalid ZIP name: %s\n" "$ZIP_NAME" >&2
  exit 1
fi

(cd anykernel && zip -r9 "../${ZIP_NAME}" . -x "*.git*" ) || { printf "ERROR: ZIP creation failed\n"; exit 1; }

printf "Built for %s | Linux %s | CI %s/%s\n" \
  "${DEVICE}" "${KERNEL_VERSION:-unknown}" "${GITHUB_RUN_ID}" "${GITHUB_RUN_ATTEMPT}" \
  | zip -z "../${ZIP_NAME}" >/dev/null || log_err "Failed to add comment to ZIP"

printf "ZIP_NAME=%s\n" "$ZIP_NAME" >> "$GITHUB_ENV"
printf "KERNEL_IMAGE_FILE=%s\n" "$KIMG" >> "$GITHUB_ENV"

# No boot image variables to set since image repacking process has been removed
# Only AnyKernel ZIP is generated for flashing
