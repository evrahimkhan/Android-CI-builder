#!/usr/bin/env bash
set -euo pipefail

# RTL8188eus Driver Integration Script
# Builds the rtl8188eus driver as an external module
# Driver source: https://github.com/aircrack-ng/rtl8188eus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

RTL8188EUS_REPO="${RTL8188EUS_REPO:-https://github.com/aircrack-ng/rtl8188eus}"
RTL8188EUS_BRANCH="${RTL8188EUS_BRANCH:-v5.7.6.1}"

# Kernel directory
if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
  KERNEL_DIR="${GITHUB_WORKSPACE}/kernel"
  EXTERNAL_DIR="${GITHUB_WORKSPACE}/external"
else
  KERNEL_DIR="kernel"
  EXTERNAL_DIR="external"
fi

# External driver directory
EXTERNAL_DRIVER_DIR="${EXTERNAL_DIR}/rtl8188eus"

log_info() { printf "[rtl8188eus] %s\n" "$*"; }
log_error() { printf "[rtl8188eus ERROR] %s\n" "$*" >&2; }

# Validate git URL
validate_rtl8188eus_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(:[0-9]+)?(/[a-zA-Z0-9._-]+)*(\.git)?$ ]]; then
    log_error "Invalid git URL: $url"
    return 1
  fi
  if [[ "$url" =~ \.\. ]]; then
    log_error "URL contains path traversal: $url"
    return 1
  fi
  return 0
}

# Clone driver to external directory
clone_driver() {
  log_info "Cloning RTL8188eus driver from: $RTL8188EUS_REPO"
  log_info "Branch: $RTL8188EUS_BRANCH"

  # Validate URL
  if ! validate_rtl8188eus_url "$RTL8188EUS_REPO"; then
    exit 1
  fi

  # Check if kernel directory exists
  if [ ! -d "$KERNEL_DIR" ]; then
    log_error "Kernel directory not found: $KERNEL_DIR"
    exit 1
  fi

  # Create external directory
  mkdir -p "$EXTERNAL_DIR"

  # Check if already cloned
  if [ -d "$EXTERNAL_DRIVER_DIR" ] && [ -f "$EXTERNAL_DRIVER_DIR/Makefile" ]; then
    log_info "Driver already cloned, updating..."
    cd "$EXTERNAL_DRIVER_DIR"
    git fetch origin
    git checkout "$RTL8188EUS_BRANCH" 2>/dev/null || true
    cd - >/dev/null
  else
    # Clone driver to external directory
    if ! git clone --depth=1 -b "$RTL8188EUS_BRANCH" "$RTL8188EUS_REPO" "$EXTERNAL_DRIVER_DIR" 2>&1; then
      log_error "Failed to clone RTL8188eus driver"
      exit 1
    fi
  fi

  log_info "Driver cloned to: $EXTERNAL_DRIVER_DIR"
}

# Build the driver as external module
build_driver() {
  log_info "Building RTL8188eus driver..."

  if [ ! -d "$EXTERNAL_DRIVER_DIR" ]; then
    log_error "Driver source not found: $EXTERNAL_DRIVER_DIR"
    exit 1
  fi

  cd "$EXTERNAL_DRIVER_DIR"

  # Set up build environment
  export ARCH="${ARCH:-arm64}"
  export SUBARCH="${SUBARCH:-arm64}"
  export KERNEL_DIR="$KERNEL_DIR"
  
  # Add clang to path if available
  if [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ -d "${GITHUB_WORKSPACE}/clang/bin" ]]; then
    export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"
  fi

  # Build as external module
  # Use the kernel's build system
  if [ -f "$KERNEL_DIR/scripts/config" ]; then
    chmod +x "$KERNEL_DIR/scripts/config" 2>/dev/null || true
  fi

  # Clean previous builds
  make clean 2>/dev/null || true

  # Build the module
  # Pass kernel source and use kernel build system
  if make -C "$KERNEL_DIR" M="$(pwd)" ARCH="$ARCH" CROSS_COMPILE="" modules 2>&1; then
    log_info "Driver built successfully"
    
    # Create modules directory in kernel output
    mkdir -p "${KERNEL_DIR}/out/modules"
    
    # Copy the built module to modules directory
    if [ -f "8188eu.ko" ]; then
      cp 8188eu.ko "${KERNEL_DIR}/out/modules/"
      log_info "Driver copied to: ${KERNEL_DIR}/out/modules/8188eu.ko"
    else
      # Try other possible names
      for ko_file in *.ko; do
        if [ -f "$ko_file" ]; then
          cp "$ko_file" "${KERNEL_DIR}/out/modules/"
          log_info "Driver copied: $ko_file"
        fi
      done
    fi
  else
    log_error "Driver build failed"
    exit 1
  fi

  cd - >/dev/null
}

# Main function
main() {
  log_info "Starting RTL8188eus driver integration..."
  
  clone_driver
  build_driver
  
  log_info "RTL8188eus driver integration complete!"
}

# Run main
main "$@"
