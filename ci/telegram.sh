#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"
DEVICE="${2:-unknown}"
BRANCH="${3:-}"
DEFCONFIG="${4:-}"
BASE_BOOT_URL="${5:-}"

api="https://api.telegram.org/bot${TG_TOKEN}"

send_msg() {
  local text="$1"
  curl -sS -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="$text" >/dev/null
}

send_doc() {
  local path="$1"
  local caption="${2:-}"
  [ -f "$path" ] || return 0
  if [ -n "$caption" ]; then
    curl -sS -F chat_id="${TG_CHAT_ID}" \
      -F parse_mode="HTML" \
      --form-string caption="$caption" \
      -F document=@"$path" \
      "${api}/sendDocument" >/dev/null
  else
    curl -sS -F chat_id="${TG_CHAT_ID}" \
      -F document=@"$path" \
      "${api}/sendDocument" >/dev/null
  fi
}

human_size() {
  # bytes -> human-ish (KiB/MiB)
  local b="$1"
  if [ "$b" -lt 1024 ]; then echo "${b} B"; return; fi
  local kib=$((b / 1024))
  if [ "$kib" -lt 1024 ]; then echo "${kib} KiB"; return; fi
  local mib=$((kib / 1024))
  echo "${mib} MiB"
}

if [ "$MODE" = "start" ]; then
  local_base="(none)"
  [ -n "$BASE_BOOT_URL" ] && local_base="provided"

  send_msg "<b>🚀 Kernel Build Started</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🌿 <b>Branch</b>: <code>${BRANCH}</code>
⚙️ <b>Defconfig</b>: <code>${DEFCONFIG}</code>
🧩 <b>Base boot.img</b>: <code>${local_base}</code>

⏳ Building with CI toolchain + cache…"
  exit 0
fi

if [ "$MODE" = "success" ]; then
  ZIP="${ZIP_NAME:-}"
  BOOT="${BOOT_IMG_NAME:-}"
  LOG="kernel/build.log"

  zipsz=""
  bootsz=""
  if [ -n "$ZIP" ] && [ -f "$ZIP" ]; then
    zipsz="$(human_size "$(stat -c%s "$ZIP")")"
  fi
  if [ -n "$BOOT" ] && [ -f "$BOOT" ]; then
    bootsz="$(human_size "$(stat -c%s "$BOOT")")"
  fi

  send_msg "<b>✅ Build Succeeded</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🧠 <b>Type</b>: <code>${KERNEL_TYPE:-unknown}</code>
🐧 <b>Linux</b>: <code>${KERNEL_VERSION:-unknown}</code>
🛠 <b>Clang</b>: <code>${CLANG_VERSION:-unknown}</code>
⏱ <b>Time</b>: <code>${BUILD_TIME:-0}s</code>
📦 <b>Artifacts</b>:
 • AnyKernel ZIP: <code>${ZIP:-n/a}</code> ${zipsz:+(<code>$zipsz</code>)}
 • boot.img: <code>${BOOT:-n/a}</code> ${bootsz:+(<code>$bootsz</code>)}

📤 Uploading files…"

  [ -n "$ZIP" ] && send_doc "$ZIP" "📦 <b>AnyKernel ZIP</b> • <code>${DEVICE}</code>"
  [ -n "$BOOT" ] && send_doc "$BOOT" "🧩 <b>boot.img</b> • <code>${DEVICE}</code>"
  send_doc "$LOG" "🧾 <b>build.log</b>"

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

  send_doc "$ERR" "🧯 <b>error.log</b> • <code>${DEVICE}</code>"
  exit 0
fi

echo "Unknown mode: $MODE" >&2
exit 2
