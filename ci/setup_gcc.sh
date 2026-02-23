#!/usr/bin/env bash
set -euo pipefail

# GCC ARM Toolchain Setup Script
# Downloads and sets up GNU ARM Embedded Toolchain for Android kernel building
# Supports both ARM64 (aarch64) and ARM32 (armv7) architectures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# GCC version - using stable release
GCC_VERSION="${GCC_VERSION:-13.2.rel1}"

# Architecture selection
ARCH="${ARCH:-arm64}"

# Kernel directory
if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
  KERNEL_DIR="${GITHUB_WORKSPACE}/kernel"
  WORKSPACE="${GITHUB_WORKSPACE}"
else
  KERNEL_DIR="kernel"
  WORKSPACE="$(pwd)"
fi

GCC_DIR="${WORKSPACE}/gcc"

log_info() { printf "[gcc-setup] %s\n" "$*"; }
log_error() { printf "[gcc-setup ERROR] %s\n" "$*" >&2; }

# Download using GitHub mirror (more reliable than ARM website)
download_gcc() {
  local gcc_file="$1"
  local gcc_url="$2"
  
  log_info "Downloading: $gcc_file"
  
  if ! curl -L --retry 3 --retry-delay 5 -o "$gcc_file" "$gcc_url" 2>&1; then
    log_error "Download failed: $gcc_url"
    return 1
  fi
  
  # Check if file is valid (not HTML redirect)
  if head -c 100 "$gcc_file" | grep -q "<!DOCTYPE\|<html\|<head"; then
    log_error "Downloaded file is HTML (redirect or error page)"
    rm -f "$gcc_file"
    return 1
  fi
  
  log_info "Download complete"
  return 0
}

# Download and extract ARM64 GCC from GitHub mirror
setup_gcc_arm64() {
  local gcc_file="arm-gnu-toolchain-${GCC_VERSION}-x86_64-aarch64-none-linux-gnueabi.tar.xz"
  
  # Try multiple sources in order of preference
  local sources=(
    "https://github.com/Archomeda/arm-gnu-toolchain/releases/download/${GCC_VERSION}/${gcc_file}"
    "https://github.com/mvaisakh/gcc-arm64/releases/download/gcc-13.2/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnueabi.tar.xz"
  )
  
  log_info "Setting up ARM64 GCC..."
  
  if [ -d "${GCC_DIR}/aarch64-none-linux-gnueabi" ]; then
    log_info "ARM64 GCC already exists, skipping download"
    return 0
  fi
  
  # Try each source
  for gcc_url in "${sources[@]}"; do
    log_info "Trying: $gcc_url"
    if download_gcc "$gcc_file" "$gcc_url"; then
      log_info "Extracting ARM64 GCC..."
      if tar -xf "$gcc_file"; then
        # Find and move the extracted directory
        local extracted_dir
        extracted_dir=$(find . -maxdepth 1 -type d -name "arm-gnu-toolchain-*" | head -1)
        if [ -n "$extracted_dir" ]; then
          mv "$extracted_dir" "${GCC_DIR}/aarch64-none-linux-gnueabi"
          rm -f "$gcc_file"
          log_info "ARM64 GCC setup complete"
          return 0
        fi
      fi
    fi
    rm -f "$gcc_file" 2>/dev/null || true
  done
  
  log_error "Failed to download ARM64 GCC from all sources"
  return 1
}

# Download and extract ARM32 GCC from GitHub mirror
setup_gcc_arm32() {
  local gcc_file="arm-gnu-toolchain-${GCC_VERSION}-x86_64-arm-none-linux-gnueabihf.tar.xz"
  
  # Try multiple sources in order of preference  
  local sources=(
    "https://github.com/Archomeda/arm-gnu-toolchain/releases/download/${GCC_VERSION}/${gcc_file}"
    "https://github.com/mvaisakh/gcc-arm64/releases/download/gcc-13.2/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz"
  )
  
  log_info "Setting up ARM32 GCC..."
  
  if [ -d "${GCC_DIR}/arm-none-linux-gnueabihf" ]; then
    log_info "ARM32 GCC already exists, skipping download"
    return 0
  fi
  
  # Try each source
  for gcc_url in "${sources[@]}"; do
    log_info "Trying: $gcc_url"
    if download_gcc "$gcc_file" "$gcc_url"; then
      log_info "Extracting ARM32 GCC..."
      if tar -xf "$gcc_file"; then
        # Find and move the extracted directory
        local extracted_dir
        extracted_dir=$(find . -maxdepth 1 -type d -name "arm-gnu-toolchain-*" | head -1)
        if [ -n "$extracted_dir" ]; then
          mv "$extracted_dir" "${GCC_DIR}/arm-none-linux-gnueabihf"
          rm -f "$gcc_file"
          log_info "ARM32 GCC setup complete"
          return 0
        fi
      fi
    fi
    rm -f "$gcc_file" 2>/dev/null || true
  done
  
  log_error "Failed to download ARM32 GCC from all sources"
  return 1
}

# Setup symlinks for easier usage
setup_symlinks() {
  log_info "Setting up symlinks..."
  
  # Create bin directory if it doesn't exist
  mkdir -p "${GCC_DIR}/bin"
  
  # ARM64 symlinks
  if [ -d "${GCC_DIR}/aarch64-none-linux-gnueabi/bin" ]; then
    for tool in gcc g++ cpp ld ar nm objcopy objdump strip readelf size; do
      if [ ! -f "${GCC_DIR}/bin/aarch64-linux-gnu-${tool}" ]; then
        ln -sf "${GCC_DIR}/aarch64-none-linux-gnueabi/bin/aarch64-none-linux-gnueabi-${tool}" "${GCC_DIR}/bin/aarch64-linux-gnu-${tool}" 2>/dev/null || true
      fi
    done
  fi
  
  # ARM32 symlinks
  if [ -d "${GCC_DIR}/arm-none-linux-gnueabihf/bin" ]; then
    for tool in gcc g++ cpp ld ar nm objcopy objdump strip readelf size; do
      if [ ! -f "${GCC_DIR}/bin/arm-linux-gnueabihf-${tool}" ]; then
        ln -sf "${GCC_DIR}/arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-${tool}" "${GCC_DIR}/bin/arm-linux-gnueabihf-${tool}" 2>/dev/null || true
      fi
    done
  fi
  
  log_info "Symlinks setup complete"
}

# Main function
main() {
  log_info "Starting GCC ARM Toolchain setup..."
  log_info "GCC Version: $GCC_VERSION"
  log_info "Architecture: $ARCH"
  
  # Create GCC directory
  mkdir -p "$GCC_DIR"
  
  # Setup based on architecture
  case "$ARCH" in
    arm64|aarch64)
      setup_gcc_arm64
      ;;
    arm|arm32|armv7)
      setup_gcc_arm32
      ;;
    both)
      setup_gcc_arm64
      setup_gcc_arm32
      ;;
    *)
      log_error "Unknown architecture: $ARCH"
      log_info "Supported: arm64, arm32, both"
      exit 1
      ;;
  esac
  
  # Setup symlinks
  setup_symlinks
  
  # Verify installation
  if [ -d "${GCC_DIR}/aarch64-none-linux-gnueabi" ]; then
    log_info "ARM64 GCC Path: ${GCC_DIR}/aarch64-none-linux-gnueabi"
    "${GCC_DIR}/aarch64-none-linux-gnueabi/bin/aarch64-none-linux-gnueabi-gcc" --version | head -1
  fi
  
  if [ -d "${GCC_DIR}/arm-none-linux-gnueabihf" ]; then
    log_info "ARM32 GCC Path: ${GCC_DIR}/arm-none-linux-gnueabihf"
    "${GCC_DIR}/arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-gcc" --version | head -1
  fi
  
  log_info "GCC setup complete!"
}

main "$@"
