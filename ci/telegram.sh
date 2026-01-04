#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"

# start:  device branch defconfig ksu_next
# success: device ksu_next
# failure: device ksu_next

api="https://api.telegram.org/bot${TG_TOKEN}"

if [ "$MODE" = "start" ]; then
  DEVICE="${2:?device}"
  BRANCH="${3:?branch}"
  DEFCONFIG="${4:?defconfig}"
  KSU_NEXT="${5:?ksu_next}"

  curl -sS -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    --data-urlencode text=$'Kernel Build Started\nDevice: '"${DEVICE}"$'\nBranch: '"${BRANCH}"$'\nDefconfig: '"${DEFCONFIG}"$'\nKernelSU-Next: '"${KSU_NEXT}"
  exit 0
fi

if [ "$MODE" = "success" ]; then
  DEVICE="${2:?device}"
  KSU_NEXT="${3:?ksu_next}"

  MSG=$'Kernel Build Success\nDevice: '"${DEVICE}"$'\nKernelSU-Next: '"${KSU_NEXT}"$'\nType: '"${KERNEL_TYPE:-unknown}"$'\nLinux: '"${KERNEL_VERSION:-unknown}"$'\nToolchain: '"${CLANG_VERSION:-unknown}"$'\nTime: '"${BUILD_TIME:-0}"$'s\nImage: '"${KERNEL_IMAGE_FILE:-unknown}"$'\nArtifact: '"${ZIP_NAME:-unknown}"
  curl -sS -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    --data-urlencode text="$MSG"

  if [ -n "${ZIP_NAME:-}" ] && [ -f "${ZIP_NAME}" ]; then
    curl -sS -F chat_id="${TG_CHAT_ID}" -F document=@"${ZIP_NAME}" "${api}/sendDocument"
  fi

  [ -f kernel/build.log ] && curl -sS -F chat_id="${TG_CHAT_ID}" -F document=@kernel/build.log "${api}/sendDocument"
  exit 0
fi

if [ "$MODE" = "failure" ]; then
  DEVICE="${2:?device}"
  KSU_NEXT="${3:?ksu_next}"

  test -f kernel/error.log || cp -f kernel/build.log kernel/error.log || true
  curl -sS -F chat_id="${TG_CHAT_ID}" \
    -F document=@kernel/error.log \
    -F caption="❌ Kernel build FAILED | Device=${DEVICE} | KernelSU-Next=${KSU_NEXT}" \
    "${api}/sendDocument"
  exit 0
fi

echo "Unknown mode: $MODE" >&2
exit 2
