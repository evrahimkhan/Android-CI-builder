#!/usr/bin/env bash
set -euo pipefail

# GCC ARM Toolchain Setup Script
# Downloads and sets up GNU ARM Embedded Toolchain for Android kernel building
# Supports both ARM64 (aarch64) and ARM32 (armv7) architectures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# GCC version - using latest stable
GCC_VERSION="${GCC_VERSION:-13.2.rel1}"
GCC_BASE_URL="https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel"

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

# Get latest GCC version from ARM website
get_latest_gcc_version() {
  # Try to get the latest version from the download page
  # Fall back to known stable version if unable to determine
  log_info "Checking for latest GCC version..."
  
  # Known stable versions - update as needed
  local known_versions=("14.2.rel1" "13.2.rel1" "12.3.rel1" "12.2.rel1")
  
  # For now, return the configured version
  echo "$GCC_VERSION"
}

# Download and extract ARM64 GCC
setup_gcc_arm64() {
  local gcc_file="arm-gnu-toolchain-${GCC_VERSION}-x86_64-aarch64-none-linux-gnueabi.tar.xz"
  local gcc_url="${GCC_BASE_URL}/${gcc_file}"
  
  log_info "Setting up ARM64 GCC..."
  log_info "URL: $gcc_url"
  
  if [ -d "${GCC_DIR}/aarch64-none-linux-gnueabi" ]; then
    log_info "ARM64 GCC already exists, skipping download"
    return 0
  fi
  
  # Download GCC
  if ! curl -L --retry 3 --retry-delay 5 -o "${gcc_file}" "$gcc_url" 2>&1; then
    log_error "Failed to download ARM64 GCC"
    log_error "URL: $gcc_url"
    exit 1
  fi
  
  # Extract GCC
  log_info "Extracting ARM64 GCC..."
  tar -xf "$gcc_file" || { log_error "Failed to extract ARM64 GCC"; exit 1; }
  
  # Move to gcc directory
  mv "arm-gnu-toolchain-${GCC_VERSION}-x86_64-aarch64-none-linux-gnueabi" "${GCC_DIR}/aarch64-none-linux-gnueabi" || {
    log_error "Failed to move ARM64 GCC to target directory"
    exit 1
  }
  
  # Clean up
  rm -f "$gcc_file"
  
  log_info "ARM64 GCC setup complete"
}

# Download and extract ARM32 GCC
setup_gcc_arm32() {
  local gcc_file="arm-gnu-toolchain-${GCC_VERSION}-x86_64-arm-none-linux-gnueabihf.tar.xz"
  local gcc_url="${GCC_BASE_URL}/${gcc_file}"
  
  log_info "Setting up ARM32 GCC..."
  log_info "URL: $gcc_url"
  
  if [ -d "${GCC_DIR}/arm-none-linux-gnueabihf" ]; then
    log_info "ARM32 GCC already exists, skipping download"
    return 0
  fi
  
  # Download GCC
  if ! curl -L --retry 3 --retry-delay 5 -o "${gcc_file}" "$gcc_url" 2>&1; then
    log_error "Failed to download ARM32 GCC"
    log_error "URL: $gcc_url"
    exit 1
  fi
  
  # Extract GCC
  log_info "Extracting ARM32 GCC..."
  tar -xf "$gcc_file" || { log_error "Failed to extract ARM32 GCC"; exit 1; }
  
  # Move to gcc directory
  mv "arm-gnu-toolchain-${GCC_VERSION}-x86_64-arm-none-linux-gnueabihf" "${GCC_DIR}/arm-none-linux-gnueabihf" || {
    log_error "Failed to move ARM32 GCC to target directory"
    exit 1
  }
  
  # Clean up
  rm -f "$gcc_file"
  
  log_info "ARM32 GCC setup complete"
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
