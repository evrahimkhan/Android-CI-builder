#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"
DEVICE="${2:-unknown}"
BRANCH="${3:-}"
DEFCONFIG="${4:-}"
BASE_BOOT_URL="${5:-}"

# Always operate from workspace root so relative paths (Kernel-*.zip, boot-*.img) resolve
cd "${GITHUB_WORKSPACE:-$(pwd)}"

api="https://api.telegram.org/bot${TG_TOKEN}"

send_msg() {
  local text="$1"
  curl -sS -f -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    --data-urlencode text="$text" \
    -d parse_mode="HTML" >/dev/null
}

# Sends a document and shows Telegram error response if it fails
send_doc_raw() {
  local path="$1"
  local caption="${2:-}"

  local resp
  if [ -n "$caption" ]; then
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
  else
    resp="$(curl -sS -f \
      -F chat_id="${TG_CHAT_ID}" \
      -F document=@"$path" \
      "${api}/sendDocument" 2>&1)" || {
        echo "Telegram sendDocument failed for $path" >&2
        echo "$resp" >&2
        return 1
      }
  fi
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

# Telegram bots can fail on large files. Split large files and upload parts.
send_doc_auto() {
  local path="$1"
  local caption="${2:-}"

  if [ ! -f "$path" ]; then
    echo "File not found: $path" >&2
    return 1
  fi

  local size
  size="$(stat -c%s "$path")"
  local hsz
  hsz="$(human_size "$size")"

  # 45 MiB chunk size to stay under typical bot limits
  local max=$((45 * 1024 * 1024))

  if [ "$size" -le "$max" ]; then
    send_doc_raw "$path" "${caption} <code>(${hsz})</code>"
    return $?
  fi

  # Split and upload parts
  local base
  base="$(basename "$path")"
  local dir
  dir="$(dirname "$path")"
  local prefix="${dir}/${base}.part-"

  rm -f "${prefix}"* 2>/dev/null || true
  split -b "${max}" -d -a 2 "$path" "${prefix}"

  send_msg "<b>📦 Large file detected</b>
<code>${base}</code> is <code>${hsz}</code>.
Uploading in parts…"

  local part
  for part in "${prefix}"*; do
    local pbase
    pbase="$(basename "$part")"
    send_doc_raw "$part" "${caption} <b>(part)</b> <code>${pbase}</code>"
  done

  send_msg "✅ Uploaded parts for <code>${base}</code>
To restore on PC:
<code>cat ${base}.part-* &gt; ${base}</code>"
  return 0
}

if [ "$MODE" = "start" ]; then
  local base="(none)"
  [ -n "$BASE_BOOT_URL" ] && base="provided"
  send_msg "<b>🚀 Kernel Build Started</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🌿 <b>Branch</b>: <code>${BRANCH}</code>
⚙️ <b>Defconfig</b>: <code>${DEFCONFIG}</code>
🧩 <b>Base boot.img</b>: <code>${base}</code>

⏳ Compiling…"
  exit 0
fi

if [ "$MODE" = "success" ]; then
  ZIP="${ZIP_NAME:-}"
  BOOT="${BOOT_IMG_NAME:-}"
  LOG="kernel/build.log"

  # Debug info to stderr (shows in Actions logs)
  echo "Telegram success:"
  echo "  ZIP_NAME=$ZIP"
  echo "  BOOT_IMG_NAME=$BOOT"
  ls -la . || true

  send_msg "<b>✅ Build Succeeded</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🧠 <b>Type</b>: <code>${KERNEL_TYPE:-unknown}</code>
🐧 <b>Linux</b>: <code>${KERNEL_VERSION:-unknown}</code>
🛠 <b>Clang</b>: <code>${CLANG_VERSION:-unknown}</code>
⏱ <b>Time</b>: <code>${BUILD_TIME:-0}s</code>

📦 Uploading artifacts…"

  if [ -n "$ZIP" ]; then
    send_doc_auto "$ZIP" "📦 <b>AnyKernel ZIP</b> • <code>${DEVICE}</code>" || true
  else
    send_msg "⚠️ ZIP_NAME is empty; skipping ZIP upload."
  fi

  if [ -n "$BOOT" ]; then
    send_doc_auto "$BOOT" "🧩 <b>boot.img</b> • <code>${DEVICE}</code>" || true
  else
    send_msg "⚠️ BOOT_IMG_NAME is empty; skipping boot.img upload."
  fi

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
