# --- boot.img generation (AOSP mkbootimg on PATH from ci/setup_aosp_mkbootimg.sh) ---
OUT_BOOT="boot-${DEVICE}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.img"
echo "BOOT_IMG_NAME=${OUT_BOOT}" >> "$GITHUB_ENV"

command -v mkbootimg >/dev/null 2>&1 || { echo "mkbootimg not found on PATH"; exit 1; }

EMPTY_RD="$(mktemp)"
: > "$EMPTY_RD"

KIMG_PATH="${BOOTDIR}/${KIMG}"

# Best-effort: repack using base boot.img if provided AND unpack_bootimg exists
if [ -n "$BASE_BOOT_URL" ] && command -v unpack_bootimg >/dev/null 2>&1; then
  echo "Downloading base boot.img: $BASE_BOOT_URL"
  curl -L --fail -o base_boot.img "$BASE_BOOT_URL"

  rm -rf boot-unpack
  mkdir -p boot-unpack

  # AOSP unpack tool wrapper (from ci/setup_aosp_mkbootimg.sh)
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
    echo "boot.img repacked from base successfully: $OUT_BOOT"
    exit 0
  fi

  echo "Base repack failed; falling back to minimal boot.img" >&2
fi

# Fallback minimal boot image (always generated)
mkbootimg \
  --kernel "$KIMG_PATH" \
  --ramdisk "$EMPTY_RD" \
  --cmdline "" \
  --header_version 0 \
  --output "$OUT_BOOT"

echo "Generated minimal boot.img: $OUT_BOOT"
