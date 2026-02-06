#!/usr/bin/env bash
set -euo pipefail

# Source shared validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

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
    printf "ERROR: Invalid mode: %s\n" "$MODE" >&2
    exit 1
  fi

# Sanitize device name to prevent injection - more restrictive validation
  if [[ ! "$DEVICE" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "$DEVICE" =~ \.\. ]] || [[ "$DEVICE" =~ /\* ]] || [[ "$DEVICE" =~ \*/ ]]; then
    printf "ERROR: Invalid device name format: %s\n" "$DEVICE" >&2
    exit 1
  fi
DEVICE=$(printf '%s\n' "$DEVICE" | sed 's/[^a-zA-Z0-9._-]/_/g')

# Sanitize other inputs with similar validation
  if [[ -n "$BRANCH" ]] && ([[ ! "$BRANCH" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$BRANCH" =~ \.\. ]] || [[ "$BRANCH" =~ /\* ]] || [[ "$BRANCH" =~ \*/ ]]); then
    printf "ERROR: Invalid branch name format: %s\n" "$BRANCH" >&2
    exit 1
  fi
BRANCH=$(printf '%s\n' "$BRANCH" | sed 's/[^a-zA-Z0-9/_.-]/_/g')

  if [[ -n "$DEFCONFIG" ]] && ([[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]] || [[ "$DEFCONFIG" =~ /\* ]] || [[ "$DEFCONFIG" =~ \*/ ]]); then
    printf "ERROR: Invalid defconfig format: %s\n" "$DEFCONFIG" >&2
    exit 1
  fi
DEFCONFIG=$(printf '%s\n' "$DEFCONFIG" | sed 's/[^a-zA-Z0-9/_.-]/_/g')

cd "${GITHUB_WORKSPACE:-$(pwd)}"

# Validate TG_TOKEN before constructing API URL
if [[ -z "${TG_TOKEN:-}" ]]; then
  log_err "TG_TOKEN not set, skipping Telegram notification"
  exit 0
fi

# Validate token format (Bot API tokens are like 123456:ABC-DEF1234ghIkl-zyx57WzyvAwdsDEFG)
if [[ ! "$TG_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
  log_err "Invalid TG_TOKEN format"
  exit 1
fi

api="https://api.telegram.org/bot${TG_TOKEN}"

log_err() { echo "[telegram] $*" >&2; }

safe_send_msg() {
  local text="$1"
  local log_file="${TELEGRAM_LOG:-/tmp/telegram_msg_$$.log}"
  curl -sS --max-time 30 -X POST "${api}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="$text" \
    >"$log_file" 2>&1 || {
      log_err "sendMessage failed"
      cat "$log_file" >> "${TELEGRAM_ERR_LOG:-/tmp/telegram_errors.log}" 2>/dev/null || true
    }
  rm -f "$log_file" 2>/dev/null || true
}

safe_send_doc_raw() {
  local path="$1"
  local caption="$2"
  [ -f "$path" ] || return 0
  local log_file="${TELEGRAM_LOG:-/tmp/telegram_$$.log}"
  curl -sS --max-time 60 \
    -F chat_id="${TG_CHAT_ID}" \
    --form-string parse_mode="HTML" \
    --form-string caption="$caption" \
    -F document=@"$path" \
    >"$log_file" 2>&1 || {
      log_err "sendDocument failed for: $path"
      cat "$log_file" >> "${TELEGRAM_ERR_LOG:-/tmp/telegram_errors.log}" 2>/dev/null || true
      rm -f "$log_file" 2>/dev/null || true
      return 1
    }
  rm -f "$log_file" 2>/dev/null || true
}

safe_send_doc_auto() {
  local path="$1"
  local caption="$2"
  [ -f "$path" ] || return 0

  # Use shared constant for Telegram max document size
  local size max hsz
  size="$(stat -c%s "$path" 2>/dev/null || echo 0)"
  max="${TELEGRAM_MAX_DOC_SIZE:-${TELEGRAM_MAX_SIZE}}"
  hsz="$(human_size "$size")"

  if [ "$size" -le "$max" ]; then
    safe_send_doc_raw "$path" "${caption} <code>(${hsz})</code>"
    return 0
  fi

  # Check if file is too large for split upload
  local num_parts max_parts=99
  num_parts=$(( (size + max - 1) / max ))
  if [ "$num_parts" -gt "$max_parts" ]; then
    log_err "File too large for Telegram split upload (${num_parts} parts needed, max ${max_parts})"
    return 1
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
    nethunter="🛡️ <b>NetHunter</b>: <code>enabled</code> (${NETHUNTER_CONFIG_LEVEL:-basic})"
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
  # Use NETHUNTER_CONFIG_LEVEL directly (passed as env var from workflow)
  # Fall back to 'normal' only if NetHunter is disabled
  if [ "${NETHUNTER_ENABLED:-false}" = "true" ]; then
    # Capitalize first letter for display
    NH_LEVEL="${NETHUNTER_CONFIG_LEVEL:-basic}"
    NH_LEVEL_DISPLAY="$(tr '[:lower:]' '[:upper:]' <<< "${NH_LEVEL:0:1}")${NH_LEVEL:1}"
    nethunter_info="🛡️ <b>NetHunter</b>: <code>${NH_LEVEL_DISPLAY}</code>
"
  else
    nethunter_info="📦 <b>Variant</b>: <code>normal</code>
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
