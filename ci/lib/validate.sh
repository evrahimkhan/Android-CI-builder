#!/usr/bin/env bash
# Shared validation library for CI scripts
# Provides common validation functions and constants

set -euo pipefail

# ============================================
# Constants
# ============================================
readonly CCACHE_SIZE="5G"
readonly TELEGRAM_MAX_SIZE=$((45 * 1024 * 1024))

# ============================================
# Logging Functions
# ============================================

log_error() {
  log_err "[ERROR]" "$*"
}

log_err() {
  local prefix="${1:-[]}"
  printf "%s %s\n" "${prefix}" "$*" >&2
}

log_info() {
  local prefix="${1:-[validate]}"
  printf "%s %s\n" "${prefix}" "$*"
}

log_warn() {
  local prefix="${1:-[WARN]}"
  printf "%s %s\n" "${prefix}" "$*" >&2
}

# ============================================
# Path Validation Functions
# ============================================

validate_workspace() {
  local workspace="${GITHUB_WORKSPACE:-}"

  if [[ -z "$workspace" ]]; then
  log_error "GITHUB_WORKSPACE is not set"
    return 1
  fi

  if [[ ! "$workspace" =~ ^/ ]]; then
    log_error "GITHUB_WORKSPACE must be an absolute path: $workspace"
    return 1
  fi

  if [[ "$workspace" == *".."* ]]; then
    log_error "GITHUB_WORKSPACE contains invalid characters (..): $workspace"
    return 1
  fi

  return 0
}

validate_github_env() {
  local env_path="${1:-$GITHUB_ENV}"

  if [[ ! "$env_path" =~ ^/ ]]; then
    log_error "GITHUB_ENV must be an absolute path: $env_path"
    return 1
  fi

  if [[ "$env_path" == *".."* ]]; then
    log_error "GITHUB_ENV contains invalid characters (..): $env_path"
    return 1
  fi

  return 0
}

# ============================================
# Input Validation Functions
# ============================================

validate_git_url() {
  local url="$1"

  if [[ ! "$url" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(:[0-9]+)?(/[a-zA-Z0-9._-]+)+(\.git)?$ ]]; then
    printf "ERROR: Invalid git URL format: %s (must be HTTPS)\n" "$url" >&2
    return 1
  fi

  return 0
}

validate_defconfig() {
  local defconfig="$1"

  if [[ ! "$defconfig" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$defconfig" =~ \.\. ]]; then
    printf "ERROR: Invalid defconfig format: %s\n" "$defconfig" >&2
    return 1
  fi

  return 0
}

validate_device_name() {
  local device="$1"

  if [[ ! "$device" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "$device" =~ \.\. ]]; then
    printf "ERROR: Invalid device name format: %s\n" "$device" >&2
    return 1
  fi

  return 0
}

validate_branch_name() {
  local branch="$1"

  if [[ -n "$branch" ]] && ([[ ! "$branch" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$branch" =~ \.\. ]]); then
    printf "ERROR: Invalid branch name format: %s\n" "$branch" >&2
    return 1
  fi

  return 0
}

sanitize_input() {
  local input="$1"
  local allowed="${2:-a-zA-Z0-9/_.-}"

  printf '%s\n' "$input" | sed "s/[^${allowed}]/_/g"
}

# ============================================
# Utility Functions
# ============================================

pick_latest() {
  local dir="$1"
  ls -1t "$dir" 2>/dev/null | head -n1 || true
}

human_size() {
  local b="$1"

  if ! [[ "$b" =~ ^[0-9]+$ ]]; then
    printf "0 B\n" >&2
    return 1
  fi

  if [ "$b" -lt 1024 ]; then
    printf "%s B\n" "$b"
    return
  fi

  local kib=$((b / 1024))
  if [ "$kib" -lt 1024 ]; then
    printf "%s KiB\n" "$kib"
    return
  fi

  local mib=$((kib / 1024))
  if [ "$mib" -lt 1024 ]; then
    printf "%s MiB\n" "$mib"
    return
  fi

  local gib=$((mib / 1024))
  printf "%s GiB\n" "$gib"
}

# Export functions for use in other scripts
export -f log_err log_info log_error log_warn
export -f validate_workspace validate_github_env
export -f validate_git_url validate_defconfig validate_device_name validate_branch_name
export -f sanitize_input pick_latest human_size
