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

OUT_BOOT="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
echo "BOOT_IMG_NAME=${OUT_BOOT}" >> "$GITHUB_ENV"

command -v mkbootimg >/dev/null 2>&1 || { echo "mkbootimg not found (run ci/setup_aosp_mkbootimg.sh)"; exit 1; }

KIMG_PATH="${BOOTDIR}/${KIMG}"
EMPTY_RD="$(mktemp)"; : > "$EMPTY_RD"

BOOT_MODE="minimal"

pick1() { find "$1" -maxdepth 3 -type f -iname "$2" 2>/dev/null | head -n1 || true; }

build_from_args_file() {
  local args_file="$1"
  local out_img="$2"
  local kernel_img="$3"

  python3 - "$args_file" <<'PY' > /tmp/mkbootimg_args.nul
import shlex, sys
txt = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read().strip()
argv = shlex.split(txt)
sys.stdout.write("\0".join(argv))
PY

  mapfile -d '' -t ARGS < /tmp/mkbootimg_args.nul || true

  NEW=()
  skip=0
  for ((i=0; i<${#ARGS[@]}; i++)); do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "${ARGS[$i]}" in
      --kernel|--output)
        skip=1
        ;;
      *)
        NEW+=("${ARGS[$i]}")
        ;;
    esac
  done

  mkbootimg "${NEW[@]}" --kernel "$kernel_img" --output "$out_img"
}

if [ -n "$BASE_BOOT_URL" ] && command -v unpack_bootimg >/dev/null 2>&1; then
  echo "Repacking boot.img from base (recommended; preserves device metadata)."
  curl -L --fail -o base_boot.img "$BASE_BOOT_URL"

  rm -rf boot-unpack
  mkdir -p boot-unpack

  unpack_bootimg --boot_img base_boot.img --out boot-unpack >/dev/null 2>&1 || true

  # Try to produce mkbootimg args (best)
  ARGS_TXT="boot-unpack/mkbootimg_args.txt"
  if unpack_bootimg --help 2>/dev/null | grep -q -- '--format'; then
    unpack_bootimg --boot_img base_boot.img --out boot-unpack --format mkbootimg > "$ARGS_TXT" 2>/dev/null || true
  fi
  if [ ! -s "$ARGS_TXT" ]; then
    CAND="$(pick1 boot-unpack '*mkbootimg*args*')"
    [ -n "$CAND" ] && cp -f "$CAND" "$ARGS_TXT" || true
  fi

  if [ -s "$ARGS_TXT" ]; then
    set +e
    build_from_args_file "$ARGS_TXT" "$OUT_BOOT" "$KIMG_PATH"
    RC=$?
    set -e
    if [ "$RC" -eq 0 ] && [ -s "$OUT_BOOT" ]; then
      BOOT_MODE="repacked"
    fi
  fi

  # Heuristic fallback if args route not available
  if [ "$BOOT_MODE" != "repacked" ]; then
    RAMDISK="$(pick1 boot-unpack '*ramdisk*')"
    [ -z "$RAMDISK" ] && RAMDISK="$EMPTY_RD"
    DTB="$(pick1 boot-unpack '*dtb*')"
    BOOTCONFIG="$(pick1 boot-unpack '*bootconfig*')"

    CMDLINE_FILE="$(pick1 boot-unpack '*cmdline*')"
    CMDLINE=""; [ -n "$CMDLINE_FILE" ] && CMDLINE="$(cat "$CMDLINE_FILE" 2>/dev/null || true)"

    HV_FILE="$(pick1 boot-unpack '*header_version*')"
    HV="0"; [ -n "$HV_FILE" ] && HV="$(cat "$HV_FILE" 2>/dev/null || echo 0)"

    OSV_FILE="$(pick1 boot-unpack '*os_version*')"
    OSP_FILE="$(pick1 boot-unpack '*os_patch_level*')"
    OSV=""; OSP=""
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
      ${BOOTCONFIG:+--bootconfig "$BOOTCONFIG"} \
      --output "$OUT_BOOT"
    RC=$?
    set -e

    if [ "$RC" -eq 0 ] && [ -s "$OUT_BOOT" ]; then
      BOOT_MODE="repacked"
    fi
  fi
fi

if [ "$BOOT_MODE" != "repacked" ]; then
  mkbootimg \
    --kernel "$KIMG_PATH" \
    --ramdisk "$EMPTY_RD" \
    --cmdline "" \
    --header_version 0 \
    --output "$OUT_BOOT"
  BOOT_MODE="minimal"
fi

echo "BOOT_IMG_MODE=${BOOT_MODE}" >> "$GITHUB_ENV"
