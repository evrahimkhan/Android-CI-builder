#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"
DEVICE="${2:-unknown}"
BRANCH="${3:-}"
DEFCONFIG="${4:-}"
BASE_BOOT_URL="${5:-}"
BASE_VENDOR_BOOT_URL="${6:-}"
BASE_INIT_BOOT_URL="${7:-}"

CUSTOM_ENABLED="${8:-false}"
CFG_LOCALVERSION="${9:--CI}"
CFG_DEFAULT_HOSTNAME="${10:-CI Builder}"
CFG_UNAME_OVERRIDE_STRING="${11:-}"
CFG_CC_VERSION_TEXT="${12:-}"

cd "${GITHUB_WORKSPACE:-$(pwd)}"
api="https://api.telegram.org/bot${TG_TOKEN}"

send_msg() {
  local text="$1"
  curl -sS -f -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="$text" >/dev/null
}

send_doc_raw() {
  local path="$1"
  local caption="$2"
  local resp
  resp="$(curl -sS -f \
    -F chat_id="${TG_CHAT_ID}" \
    --form-string parse_mode="HTML" \
    --form-string caption="$caption" \
    -F document=@"$path" \
    "${api}/sendDocument" 2>&1)" || {
      echo "Telegram sendDocument failed for $path" >&2
      echo "$resp" >&2
      return 1
    }
  return 0
}

human_size() {
  local b="$1"
  if [ "$b" -lt 1024 ]; then echo "${b} B"; return; fi
  local kib=$((b / 1024))
  if [ "$kib" -lt 1024 ]; then echo "${kib} KiB"; return; fi
  local mib=$((kib / 1024))
  echo "${mib} MiB"
}

send_doc_auto() {
  local path="$1"
  local caption="$2"

  [ -f "$path" ] || return 0

  local size max
  size="$(stat -c%s "$path")"
  max=$((45 * 1024 * 1024))

  local hsz
  hsz="$(human_size "$size")"

  if [ "$size" -le "$max" ]; then
    send_doc_raw "$path" "${caption} <code>(${hsz})</code>"
    return $?
  fi

  local base dir prefix
  base="$(basename "$path")"
  dir="$(dirname "$path")"
  prefix="${dir}/${base}.part-"

  rm -f "${prefix}"* 2>/dev/null || true
  split -b "${max}" -d -a 2 "$path" "${prefix}"

  send_msg "<b>📦 Large file</b>
<code>${base}</code> is <code>${hsz}</code>.
Uploading in parts…"

  local part
  for part in "${prefix}"*; do
    send_doc_raw "$part" "${caption} <b>(part)</b> <code>$(basename "$part")</code>"
  done

  send_msg "✅ Parts uploaded for <code>${base}</code>
Restore:
<code>cat ${base}.part-* &gt; ${base}</code>"
}

pick_latest() { ls -1t $1 2>/dev/null | head -n1 || true; }

if [ "$MODE" = "start" ]; then
  base_boot="(none)"; [ -n "$BASE_BOOT_URL" ] && base_boot="provided"
  base_vboot="(none)"; [ -n "$BASE_VENDOR_BOOT_URL" ] && base_vboot="provided"
  base_iboot="(none)"; [ -n "$BASE_INIT_BOOT_URL" ] && base_iboot="provided"

  cfg_line="🎛 <b>Branding</b>: <code>disabled</code>"
  if [ "$CUSTOM_ENABLED" = "true" ]; then
    cfg_line="🎛 <b>Branding</b>: <code>enabled</code>
• LOCALVERSION: <code>${CFG_LOCALVERSION}</code>
• HOSTNAME: <code>${CFG_DEFAULT_HOSTNAME}</code>
• UNAME: <code>${CFG_UNAME_OVERRIDE_STRING}</code>
• CC_VERSION_TEXT: <code>${CFG_CC_VERSION_TEXT:-auto}</code>"
  fi

  send_msg "<b>🚀 Kernel Build Started</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🌿 <b>Branch</b>: <code>${BRANCH}</code>
⚙️ <b>Defconfig</b>: <code>${DEFCONFIG}</code>

🧩 <b>Base images</b>
• boot: <code>${base_boot}</code>
• vendor_boot: <code>${base_vboot}</code>
• init_boot: <code>${base_iboot}</code>

${cfg_line}

⏳ Compiling…"
  exit 0
fi

if [ "$MODE" = "success" ]; then
  ZIP="${ZIP_NAME:-}"; [ -z "$ZIP" ] && ZIP="$(pick_latest 'Kernel-*.zip')"
  BOOT="${BOOT_IMG_NAME:-}"; [ -z "$BOOT" ] && BOOT="$(pick_latest 'boot-*.img')"
  VBOOT="${VENDOR_BOOT_IMG_NAME:-}"; [ -z "$VBOOT" ] && VBOOT="$(pick_latest 'vendor_boot-*.img')"
  IBOOT="${INIT_BOOT_IMG_NAME:-}"; [ -z "$IBOOT" ] && IBOOT="$(pick_latest 'init_boot-*.img')"
  BOOTMODE="${BOOT_IMG_MODE:-unknown}"
  LOG="kernel/build.log"

  send_msg "<b>✅ Build Succeeded</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🧠 <b>Type</b>: <code>${KERNEL_TYPE:-unknown}</code>
🐧 <b>Linux</b>: <code>${KERNEL_VERSION:-unknown}</code>
🛠 <b>Clang</b>: <code>${CLANG_VERSION:-unknown}</code>
⏱ <b>Time</b>: <code>${BUILD_TIME:-0}s</code>

🧩 <b>boot.img mode</b>: <code>${BOOTMODE}</code>
📦 Uploading artifacts…"

  [ -n "$ZIP" ] && send_doc_auto "$ZIP" "📦 <b>AnyKernel ZIP</b> • <code>${DEVICE}</code>" || true
  [ -n "$BOOT" ] && send_doc_auto "$BOOT" "🧩 <b>boot.img</b> • <code>${DEVICE}</code>" || true
  [ -n "$VBOOT" ] && send_doc_auto "$VBOOT" "🧩 <b>vendor_boot.img</b> • <code>${DEVICE}</code>" || true
  [ -n "$IBOOT" ] && send_doc_auto "$IBOOT" "🧩 <b>init_boot.img</b> • <code>${DEVICE}</code>" || true
  send_doc_auto "$LOG" "🧾 <b>build.log</b>" || true
  exit 0
fi

if [ "$MODE" = "failure" ]; then
  ERR="kernel/error.log"
  LOG="kernel/build.log"
  [ -f "$ERR" ] || cp -f "$LOG" "$ERR" 2>/dev/null || true

  send_msg "<b>❌ Build Failed</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>

📎 Sending error log…"

  send_doc_auto "$ERR" "🧯 <b>error.log</b> • <code>${DEVICE}</code>" || true
  exit 0
fi

echo "Unknown mode: $MODE" >&2
exit 2
