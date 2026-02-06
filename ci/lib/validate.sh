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

log_err() {
  local prefix="${1:-[]}"
  echo "${prefix} $*" >&2
}

log_info() {
  local prefix="${1:-[validate]}"
  echo "${prefix} $*"
}

# ============================================
# Path Validation Functions
# ============================================

validate_workspace() {
  local workspace="${GITHUB_WORKSPACE:-}"

  if [[ -z "$workspace" ]]; then
    log_err "GITHUB_WORKSPACE is not set"
    return 1
  fi

  if [[ ! "$workspace" =~ ^/ ]]; then
    log_err "GITHUB_WORKSPACE must be an absolute path: $workspace"
    return 1
  fi

  if [[ "$workspace" == *".."* ]]; then
    log_err "GITHUB_WORKSPACE contains invalid characters (..): $workspace"
    return 1
  fi

  return 0
}

validate_github_env() {
  local env_path="${1:-$GITHUB_ENV}"

  if [[ ! "$env_path" =~ ^/ ]]; then
    log_err "GITHUB_ENV must be an absolute path: $env_path"
    return 1
  fi

  if [[ "$env_path" == *".."* ]]; then
    log_err "GITHUB_ENV contains invalid characters (..): $env_path"
    return 1
  fi

  return 0
}

# ============================================
# Input Validation Functions
# ============================================

validate_defconfig() {
  local defconfig="$1"

  if [[ ! "$defconfig" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$defconfig" =~ \.\. ]]; then
    echo "ERROR: Invalid defconfig format: $defconfig" >&2
    return 1
  fi

  return 0
}

validate_device_name() {
  local device="$1"

  if [[ ! "$device" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ "$device" =~ \.\. ]]; then
    echo "ERROR: Invalid device name format: $device" >&2
    return 1
  fi

  return 0
}

validate_branch_name() {
  local branch="$1"

  if [[ -n "$branch" ]] && ([[ ! "$branch" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$branch" =~ \.\. ]]); then
    echo "ERROR: Invalid branch name format: $branch" >&2
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
    echo "0 B" >&2
    return 1
  fi

  if [ "$b" -lt 1024 ]; then
    echo "${b} B"
    return
  fi

  local kib=$((b / 1024))
  if [ "$kib" -lt 1024 ]; then
    echo "${kib} KiB"
    return
  fi

  local mib=$((kib / 1024))
  if [ "$mib" -lt 1024 ]; then
    echo "${mib} MiB"
    return
  fi

  local gib=$((mib / 1024))
  echo "${gib} GiB"
}

# Export functions for use in other scripts
export -f log_err log_info
export -f validate_workspace validate_github_env
export -f validate_defconfig validate_device_name validate_branch_name
export -f sanitize_input pick_latest human_size
