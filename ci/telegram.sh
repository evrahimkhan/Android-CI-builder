#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required}"
DEVICE="${2:-unknown}"

# Define all parameters with defaults to prevent unbound variable errors
BRANCH="${3:-}"
DEFCONFIG="${4:-}"

# Skip base image parameters (5-7) as image repacking has been removed
CUSTOM_ENABLED="${8:-false}"
CFG_LOCALVERSION="${9:--CI}"
CFG_DEFAULT_HOSTNAME="${10:-CI Builder}"
CFG_UNAME_OVERRIDE_STRING="${11:-}"
CFG_CC_VERSION_TEXT="${12:-}"


# Validate inputs to prevent potential information disclosure or injection
if [[ ! "$MODE" =~ ^(start|success|failure)$ ]]; then
  echo "ERROR: Invalid mode: $MODE" >&2
  exit 1
fi

# Sanitize device name to prevent injection - more restrictive validation
if [[ ! "$DEVICE" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "$DEVICE" =~ \.\. ]] || [[ "$DEVICE" =~ /\* ]] || [[ "$DEVICE" =~ \*/ ]]; then
  echo "ERROR: Invalid device name format: $DEVICE" >&2
  exit 1
fi
DEVICE=$(printf '%s\n' "$DEVICE" | sed 's/[^a-zA-Z0-9._-]/_/g')

# Sanitize other inputs with similar validation
if [[ -n "$BRANCH" ]] && ([[ ! "$BRANCH" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$BRANCH" =~ \.\. ]] || [[ "$BRANCH" =~ /\* ]] || [[ "$BRANCH" =~ \*/ ]]); then
  echo "ERROR: Invalid branch name format: $BRANCH" >&2
  exit 1
fi
BRANCH=$(printf '%s\n' "$BRANCH" | sed 's/[^a-zA-Z0-9/_.-]/_/g')

if [[ -n "$DEFCONFIG" ]] && ([[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]] || [[ "$DEFCONFIG" =~ /\* ]] || [[ "$DEFCONFIG" =~ \*/ ]]); then
  echo "ERROR: Invalid defconfig format: $DEFCONFIG" >&2
  exit 1
fi
DEFCONFIG=$(printf '%s\n' "$DEFCONFIG" | sed 's/[^a-zA-Z0-9/_.-]/_/g')

cd "${GITHUB_WORKSPACE:-$(pwd)}"
api="https://api.telegram.org/bot${TG_TOKEN}"

log_err() { echo "[telegram] $*" >&2; }

human_size() {
  local b="$1"

  # Validate input is numeric
  if ! [[ "$b" =~ ^[0-9]+$ ]]; then
    echo "0 B" >&2
    return 1
  fi

  # Check for potential overflow
  if [ "$b" -gt $((2**63 - 1)) ]; then
    echo "Invalid size: too large" >&2
    return 1
  fi

  if [ "$b" -lt 1024 ]; then echo "${b} B"; return; fi
  local kib=$((b / 1024))
  if [ "$kib" -lt 1024 ]; then echo "${kib} KiB"; return; fi
  local mib=$((kib / 1024))
  if [ "$mib" -lt 1024 ]; then echo "${mib} MiB"; return; fi
  local gib=$((mib / 1024))
  echo "${gib} GiB"
}

pick_latest() { ls -1t $1 2>/dev/null | head -n1 || true; }

safe_send_msg() {
  local text="$1"
  curl -sS -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="$text" >/dev/null 2>&1 || log_err "sendMessage failed"
}

safe_send_doc_raw() {
  local path="$1"
  local caption="$2"
  [ -f "$path" ] || return 0
  curl -sS \
    -F chat_id="${TG_CHAT_ID}" \
    --form-string parse_mode="HTML" \
    --form-string caption="$caption" \
    -F document=@"$path" \
    "${api}/sendDocument" >/dev/null 2>&1 || {
      log_err "sendDocument failed for: $path"
      return 1
    }
}

safe_send_doc_auto() {
  local path="$1"
  local caption="$2"
  [ -f "$path" ] || return 0

  # Telegram bot API limit is 50MB, use 45MB to leave room for overhead
  local size max hsz
  size="$(stat -c%s "$path" 2>/dev/null || echo 0)"
  local TELEGRAM_MAX_DOC_SIZE=$((45 * 1024 * 1024))  # 45MB limit
  max="${TELEGRAM_MAX_DOC_SIZE}"
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
  timeout 300 split -b "${max}" -d -a 2 "$path" "${prefix}" || return 0

  safe_send_msg "<b>📦 Large file</b>
<code>${base}</code> is <code>${hsz}</code>.
Uploading in parts…"

  local part
  for part in "${prefix}"*; do
    safe_send_doc_raw "$part" "${caption} <b>(part)</b> <code>$(basename "$part")</code>"
  done

  safe_send_msg "✅ Parts uploaded for <code>${base}</code>
Restore:
<code>cat ${base}.part-* &gt; ${base}</code>"
}

if [ "$MODE" = "start" ]; then

  branding="🎛 <b>Branding</b>: <code>disabled</code>"
  if [ "$CUSTOM_ENABLED" = "true" ]; then
    branding="🎛 <b>Branding</b>: <code>enabled</code>
• LOCALVERSION: <code>${CFG_LOCALVERSION}</code>
• HOSTNAME: <code>${CFG_DEFAULT_HOSTNAME}</code>
• UNAME: <code>${CFG_UNAME_OVERRIDE_STRING}</code>
• CC_VERSION_TEXT: <code>${CFG_CC_VERSION_TEXT:-auto}</code>"
  fi

  nethunter="🛡️ <b>NetHunter</b>: <code>disabled</code>"
  if [ "${NETHUNTER_ENABLED:-false}" = "true" ]; then
    nethunter="🛡️ <b>NetHunter</b>: <code>enabled</code>
• Level: <code>${NETHUNTER_CONFIG_LEVEL:-basic}</code>"
  fi

  safe_send_msg "<b>🚀 Kernel Build Started</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🌿 <b>Branch</b>: <code>${BRANCH}</code>
⚙️ <b>Defconfig</b>: <code>${DEFCONFIG}</code>

${branding}

${nethunter}

⏳ Compiling…
Note: Only AnyKernel ZIP will be generated (no individual boot images)"
  exit 0
fi

if [ "$MODE" = "success" ]; then
  ZIP="${ZIP_NAME:-}"; [ -z "$ZIP" ] && ZIP="$(pick_latest 'Kernel-*.zip')"

  # Only AnyKernel ZIP is generated (no individual boot images)
  LOG="kernel/build.log"

  nethunter_info=""
  if [ "${NETHUNTER_ENABLED:-false}" = "true" ]; then
    nethunter_info="🛡️ <b>NetHunter</b>: <code>${NETHUNTER_CONFIG_LEVEL:-basic}</code>
"
  fi

  safe_send_msg "<b>✅ Build Succeeded</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
🧠 <b>Type</b>: <code>${KERNEL_TYPE:-unknown}</code>
🐧 <b>Linux</b>: <code>${KERNEL_VERSION:-unknown}</code>
🛠 <b>Clang</b>: <code>${CLANG_VERSION:-unknown}</code>
⏱ <b>Time</b>: <code>${BUILD_TIME:-0}s</code>
${nethunter_info}
📦 Uploading artifacts…"

  [ -n "$ZIP" ] && safe_send_doc_auto "$ZIP" "📦 <b>AnyKernel ZIP</b> • <code>${DEVICE}</code>"
  safe_send_doc_auto "$LOG" "🧾 <b>build.log</b>"

  safe_send_msg "✅ Build completed. Only AnyKernel ZIP is available for flashing."

  exit 0
fi

if [ "$MODE" = "failure" ]; then
  ERR="kernel/error.log"
  LOG="kernel/build.log"
  [ -f "$ERR" ] || cp -f "$LOG" "$ERR" 2>/dev/null || true

  nethunter_fail_info=""
  if [ "${NETHUNTER_ENABLED:-false}" = "true" ]; then
    nethunter_fail_info="🛡️ <b>NetHunter</b>: <code>${NETHUNTER_CONFIG_LEVEL:-basic}</code>
"
  fi

  safe_send_msg "<b>❌ Build Failed</b>
━━━━━━━━━━━━━━━━━━━━
📱 <b>Device</b>: <code>${DEVICE}</code>
${nethunter_fail_info}
📎 Sending error log…"

  safe_send_doc_auto "$ERR" "🧯 <b>error.log</b> • <code>${DEVICE}</code>"
  exit 0
fi

exit 0
