#!/usr/bin/env bash
set -euo pipefail

# Use canonical path to avoid issues with relative paths in GitHub Actions
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd -P)"
# Fix: If we're inside the Android-CI-builder directory, don't double it
if [[ "$SCRIPT_DIR" == *"Android-CI-builder/Android-CI-builder"* ]]; then
  SCRIPT_DIR="${SCRIPT_DIR/Android-CI-builder\/Android-CI-builder/Android-CI-builder}"
fi

# Source shared validation library
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

  # Use shared validation functions for consistency and security
  if ! validate_device_name "$DEVICE"; then
    exit 1
  fi

  # Check if sanitize_input function exists before calling
  if declare -f sanitize_input >/dev/null 2>&1; then
    DEVICE=$(sanitize_input "$DEVICE" "a-zA-Z0-9._-")
  fi

  if [[ -n "$BRANCH" ]]; then
    if ! validate_branch_name "$BRANCH"; then
      exit 1
    fi
    if declare -f sanitize_input >/dev/null 2>&1; then
      BRANCH=$(sanitize_input "$BRANCH" "a-zA-Z0-9/_.-")
    fi
  fi

  if [[ -n "$DEFCONFIG" ]]; then
    if ! validate_defconfig "$DEFCONFIG"; then
      exit 1
    fi
    if declare -f sanitize_input >/dev/null 2>&1; then
      DEFCONFIG=$(sanitize_input "$DEFCONFIG" "a-zA-Z0-9/_.-")
    fi
  fi

cd "${GITHUB_WORKSPACE:-$(pwd)}"

# Validate TG_TOKEN before constructing API URL
if [[ -z "${TG_TOKEN:-}" ]]; then
  printf "[telegram] TG_TOKEN not set, skipping Telegram notification\n" >&2
  exit 0
fi

# Validate token format (Bot API tokens are like 123456:ABC-DEF1234ghIkl-zyx57WzyvAwdsDEFG)
# Enhanced validation: proper length and character set
if [[ ! "$TG_TOKEN" =~ ^[0-9]{5,}:[A-Za-z0-9_-]{30,}$ ]]; then
  log_err "Invalid TG_TOKEN format - expected format: numbers:alphanumeric_underscores_dashes"
  log_err "Token must be at least 35 characters total (ID: 5+ chars, Secret: 30+ chars)"
  exit 1
fi

# Validate TG_CHAT_ID
if [[ -z "${TG_CHAT_ID:-}" ]]; then
  printf "[telegram] TG_CHAT_ID not set\n" >&2
  exit 1
fi
if [[ ! "$TG_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
  printf "[telegram] Invalid TG_CHAT_ID format (must be numeric)\n" >&2
  exit 1
fi

api="https://api.telegram.org/bot${TG_TOKEN}"



safe_send_msg() {
  local text="$1"
  local log_file
  log_file=$(mktemp -t telegram_msg_XXXXXX.log) || {
    log_err "Failed to create secure temp file for Telegram message"
    return 1
  }
  
  local retry_count=0
  local max_retries=3
  
  while [ $retry_count -lt $max_retries ]; do
    if curl -sS --max-time 30 -X POST "${api}/sendMessage" \
      -d chat_id="${TG_CHAT_ID}" \
      -d parse_mode="HTML" \
      --data-urlencode text="$text" \
      >"$log_file" 2>&1; then
      # Success - check response for API errors
      if grep -q '"ok":true' "$log_file" 2>/dev/null; then
        rm -f "$log_file" 2>/dev/null || true
        return 0
      else
        log_err "Telegram API error: $(cat "$log_file" 2>/dev/null || 'unknown')"
      fi
    else
      log_err "sendMessage failed (attempt $((retry_count + 1))/$max_retries): $(cat "$log_file" 2>/dev/null || 'unknown')"
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $((retry_count * 2))  # Exponential backoff
    fi
  done
  
  rm -f "$log_file" 2>/dev/null || true
  return 1
}

safe_send_doc_raw() {
  local path="$1"
  local caption="$2"
  [ -f "$path" ] || { log_err "File not found: $path"; return 1; }
  local log_file
  log_file=$(mktemp -t telegram_doc_XXXXXX.log) || {
    log_err "Failed to create secure temp file for Telegram document"
    return 1
  }
  
  local retry_count=0
  local max_retries=2  # Fewer retries for large files
  
  while [ $retry_count -lt $max_retries ]; do
    if curl -sS --max-time 60 "${api}/sendDocument" \
      -F chat_id="${TG_CHAT_ID}" \
      --form-string parse_mode="HTML" \
      --form-string caption="$caption" \
      -F document=@"$path" \
      >"$log_file" 2>&1; then
      # Success - check response for API errors
      if grep -q '"ok":true' "$log_file" 2>/dev/null; then
        rm -f "$log_file" 2>/dev/null || true
        return 0
      else
        log_err "Telegram API error for document: $(cat "$log_file" 2>/dev/null || 'unknown')"
      fi
    else
      log_err "sendDocument failed for: $path (attempt $((retry_count + 1))/$max_retries)"
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $((retry_count * 3))  # Exponential backoff for file uploads
    fi
  done
  
  log_err "API response: $(cat "$log_file" 2>/dev/null || 'unknown')"
  rm -f "$log_file" 2>/dev/null || true
  return 1
}

safe_send_doc_auto() {
  local path="$1"
  local caption="$2"
  [ -f "$path" ] || { log_err "File not found: $path"; return 0; }

  # Use shared constant for Telegram max document size
  local size max hsz
  size="$(stat -c%s "$path" 2>/dev/null || echo 0)"
  max="${TELEGRAM_MAX_DOC_SIZE:-${TELEGRAM_MAX_SIZE}}"
  hsz="$(human_size "$size")"

  if [ "$size" -le "$max" ]; then
    safe_send_doc_raw "$path" "${caption} <code>(${hsz})</code>" || return 0
    return 0
  fi

  # Check if file is too large for split upload
  # Telegram API limit for documents is 50MB, we split to stay well under
  local num_parts max_parts=50  # Conservative limit to avoid API issues
  num_parts=$(( (size + max - 1) / max ))
  if [ "$num_parts" -gt "$max_parts" ]; then
    log_err "File too large for Telegram split upload (${num_parts} parts needed, max ${max_parts})"
    return 0
  fi

  local base dir prefix
  base="$(basename "$path")"
  dir="$(dirname "$path")"
  prefix="${dir}/${base}.part-"

  # Safe deletion: list files specifically instead of wildcard
  for part in "${prefix}"*; do
    [ -f "$part" ] && rm -f "$part" 2>/dev/null || true
  done
  timeout 300 split -b "${max}" -d -a 2 "$path" "${prefix}" || return 0

  safe_send_msg "<b>📦 Large file</b>
<code>${base}</code> is <code>${hsz}</code>.
Uploading in parts…"

  local part
  for part in "${prefix}"*; do
    safe_send_doc_raw "$part" "${caption} <b>(part)</b> <code>$(basename "$part")</code>" || return 0
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
fi

# Script naturally exits here - no explicit exit needed
