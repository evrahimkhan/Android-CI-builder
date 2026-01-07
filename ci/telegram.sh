#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"
DEVICE="${2:-unknown}"

# START args from workflow
BRANCH="${3:-}"
DEFCONFIG="${4:-}"
BASE_BOOT_URL="${5:-}"
BASE_VENDOR_BOOT_URL="${6:-}"
BASE_INIT_BOOT_URL="${7:-}"

# Branding args (optional)
CUSTOM_ENABLED="${8:-false}"
CFG_LOCALVERSION="${9:--CI}"
CFG_DEFAULT_HOSTNAME="${10:-CI Builder}"
CFG_UNAME_OVERRIDE_STRING="${11:-}"
CFG_CC_VERSION_TEXT="${12:-}"

# Always operate from workspace root so relative paths resolve
cd "${GITHUB_WORKSPACE:-$(pwd)}"

api="https://api.telegram.org/bot${TG_TOKEN}"

log_err() { echo "[telegram] $*" >&2; }

# ---------- helpers ----------
human_size() {
  local b="$1"
  if [ "$b" -lt 1024 ]; then echo "${b} B"; return; fi
  local kib=$((b / 1024))
  if [ "$kib" -lt 1024 ]; then echo "${kib} KiB"; return; fi
  local mib=$((kib / 1024))
  echo "${mib} MiB"
}

pick_latest() {
  # usage: pick_latest 'pattern'
  ls -1t $1 2>/dev/null | head -n1 || true
}

safe_send_msg() {
  # Never fail CI if Telegram rejects messages
  local text="$1"
  curl -sS -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="$text" >/dev/null 2>&1 || {
      log_err "sendMessage failed"
      return 0
    }
  return 0
}

safe_send_doc_raw() {
  local path="$1"
  local caption="${2:-}"

  [ -f "$path" ] || { log_err "file missing: $path"; return 0; }

  # Use HTML captions
  if [ -n "$caption" ]; then
    curl -sS \
      -F chat_id="${TG_CHAT_ID}" \
      --form-string parse_mode="HTML" \
      --form-string caption="$caption" \
      -F document=@"$path" \
      "${api}/sendDocument" >/dev/null 2>&1 || {
        log_err "sendDocument failed for: $path"
        return 0
      }
  else
    curl -sS \
      -F chat_id="${TG_CHAT_ID}" \
      -F document=@"$path" \
      "${api}/sendDocument" >/dev/null 2>&1 || {
        log_err "sendDocument failed for: $path"
        return 0
      }
  fi

  return 0
}

safe_send_doc_auto() {
  # Splits big files into parts so Telegram bot can upload them
  local path="$1"
  local caption="${2:-}"

  [ -f "$path" ] || { log_err "file missing: $path"; return 0; }

  local size max hsz
  size="$(stat -c%s "$path" 2>/dev/null || echo 0)"
  max=$((45 * 1024 * 1024)) # 45 MiB
  hsz="$(human_size "$size")"

  if [ "$size" -le "$max" ]; then
    safe_send_doc_raw "$path" "${caption} <code>(${hsz})</code>"
    return 0
  fi

  local base dir prefix
  base="$(basename "$path")"
  dir="$(dirname "$path")"
  prefix="${dir}/${base}.part-"

  rm -f "${prefix}"* 2>/dev/null || true
  split -b "${max}" -d -a 2 "$path" "${prefix}" || {
    log_err "split failed for: $path"
    return 0
  }

  safe_send_msg "<b>📦 Large file</b>
<code>${base}</code> is <code>${hsz}</code>.
Uploading in parts…"

  local part
  for part in "${prefix}"*; do
    safe_send_doc_raw "$part" "${caption} <b>(part)</b> <code>$(basename "$part")</code>"
  done

  safe_send_msg "✅ Parts uploaded for <code>${base}</code>
Restore on PC:
<code>cat ${base}.part-* &gt; ${base}</code>"
  return 0
}

# ---------- modes ----------
if [ "$MODE" = "start" ]; then
  base_boot="(none)"; [ -n "$BASE_BOOT_URL" ] && base_boot="provided"
  base_vboot="(none)"; [ -n "$BASE_VENDOR_BOOT_URL" ] && base_vboot="provided"
  base_iboot="(none)"; [ -n "$BASE_INIT_BOOT_URL" ] && base_iboot="provided"

  branding="🎛 <b>Branding</b>: <code>disabled</code>"
  if [ "$CUSTOM_ENABLED" = "true" ]; then
    branding="🎛 <b>Branding</b>: <code>enabled</code>
• LOCALVERSION: <code>${CFG_LOCALVERSION}</code>
• HOSTNAME: <code>${CFG_DEFAULT_HOSTNAME}</code>
• UNAME: <code>${CFG_UNAME_OVERRIDE_STRING}</code>
• CC_VERSION_TEXT: <code>${CFG_CC_VERSION_TEXT:-auto}</code>"
  fi

  safe_send_msg "<b>🚀 Kernel Build Started</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🌿 <b>Branch</b>: <code>${BRANCH}</code>
⚙️ <b>Defconfig</b>: <code>${DEFCONFIG}</code>

🧩 <b>Base images</b>
• boot: <code>${base_boot}</code>
• vendor_boot: <code>${base_vboot}</code>
• init_boot: <code>${base_iboot}</code>

${branding}

⏳ Compiling…"
  exit 0
fi

if [ "$MODE" = "success" ]; then
  # Use exported env vars if present, else find by glob
  ZIP="${ZIP_NAME:-}"; [ -z "$ZIP" ] && ZIP="$(pick_latest 'Kernel-*.zip')"
  BOOT="${BOOT_IMG_NAME:-}"; [ -z "$BOOT" ] && BOOT="$(pick_latest 'boot-*.img')"
  VBOOT="${VENDOR_BOOT_IMG_NAME:-}"; [ -z "$VBOOT" ] && VBOOT="$(pick_latest 'vendor_boot-*.img')"
  IBOOT="${INIT_BOOT_IMG_NAME:-}"; [ -z "$IBOOT" ] && IBOOT="$(pick_latest 'init_boot-*.img')"

  BOOTMODE="${BOOT_IMG_MODE:-unknown}"
  LOG="kernel/build.log"

  # Sizes for message
  zipsz=""; [ -n "$ZIP" ] && [ -f "$ZIP" ] && zipsz="$(human_size "$(stat -c%s "$ZIP")")"
  bootsz=""; [ -n "$BOOT" ] && [ -f "$BOOT" ] && bootsz="$(human_size "$(stat -c%s "$BOOT")")"
  vbootsz=""; [ -n "$VBOOT" ] && [ -f "$VBOOT" ] && vbootsz="$(human_size "$(stat -c%s "$VBOOT")")"
  ibootsz=""; [ -n "$IBOOT" ] && [ -f "$IBOOT" ] && ibootsz="$(human_size "$(stat -c%s "$IBOOT")")"

  safe_send_msg "<b>✅ Build Succeeded</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🧠 <b>Type</b>: <code>${KERNEL_TYPE:-unknown}</code>
🐧 <b>Linux</b>: <code>${KERNEL_VERSION:-unknown}</code>
🛠 <b>Clang</b>: <code>${CLANG_VERSION:-unknown}</code>
⏱ <b>Time</b>: <code>${BUILD_TIME:-0}s</code>

🧩 <b>boot.img mode</b>: <code>${BOOTMODE}</code>

📦 <b>Artifacts</b>
• ZIP: <code>${ZIP:-n/a}</code> ${zipsz:+(<code>$zipsz</code>)}
• boot.img: <code>${BOOT:-n/a}</code> ${bootsz:+(<code>$bootsz</code>)}
• vendor_boot: <code>${VBOOT:-n/a}</code> ${vbootsz:+(<code>$vbootsz</code>)}
• init_boot: <code>${IBOOT:-n/a}</code> ${ibootsz:+(<code>$ibootsz</code>)}

📤 Uploading files…"

  [ -n "$ZIP" ] && safe_send_doc_auto "$ZIP" "📦 <b>AnyKernel ZIP</b> • <code>${DEVICE}</code>"
  [ -n "$BOOT" ] && safe_send_doc_auto "$BOOT" "🧩 <b>boot.img</b> • <code>${DEVICE}</code>"
  [ -n "$VBOOT" ] && safe_send_doc_auto "$VBOOT" "🧩 <b>vendor_boot.img</b> • <code>${DEVICE}</code>"
  [ -n "$IBOOT" ] && safe_send_doc_auto "$IBOOT" "🧩 <b>init_boot.img</b> • <code>${DEVICE}</code>"
  safe_send_doc_auto "$LOG" "🧾 <b>build.log</b>"

  # Helpful warning if minimal boot.img (often causes fastboot)
  if [ "$BOOTMODE" = "minimal" ]; then
    safe_send_msg "⚠️ <b>Warning</b>: boot.img was generated in <code>minimal</code> mode.
This often boots to fastboot.
Provide a correct <code>base_boot_img_url</code> from your exact ROM build to get <code>repacked</code> mode."
  fi

  exit 0
fi

if [ "$MODE" = "failure" ]; then
  ERR="kernel/error.log"
  LOG="kernel/build.log"
  [ -f "$ERR" ] || cp -f "$LOG" "$ERR" 2>/dev/null || true

  safe_send_msg "<b>❌ Build Failed</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>

📎 Sending error log…"

  safe_send_doc_auto "$ERR" "🧯 <b>error.log</b> • <code>${DEVICE}</code>"
  exit 0
fi

log_err "Unknown mode: $MODE"
exit 0
