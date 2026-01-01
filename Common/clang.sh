#!/usr/bin/env bash

# Function to show an informational message
msg() {
    echo -e "\e[1;32m$*\e[0m"
}
err() {
    echo -e "\e[1;41m$*\e[0m"
}

# Get home directory
DIR="$(pwd)"
install=$DIR/install

# LLVM/Clang version to download
LLVM_VERSION="17.0.6"
LLVM_RELEASE_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-22.04.tar.xz"

msg "Downloading pre-built LLVM/Clang ${LLVM_VERSION}..."
wget -q --show-progress "$LLVM_RELEASE_URL" -O clang-llvm.tar.xz || {
    err "Failed to download LLVM/Clang!"
    exit 1
}

msg "Extracting LLVM/Clang..."
mkdir -p "$install"
tar -xf clang-llvm.tar.xz --strip-components=1 -C "$install" || {
    err "Failed to extract LLVM/Clang!"
    exit 1
}

# Clean up downloaded archive
rm -f clang-llvm.tar.xz

# Verify installation
if [ ! -f "$install/bin/clang" ]; then
    err "Clang binary not found after extraction!"
    exit 1
fi

msg "LLVM/Clang ${LLVM_VERSION} successfully installed at: $install"

# Get clang version info
clang_version="$($install/bin/clang --version | head -n1)"
msg "Clang version: $clang_version"

# Add clang to PATH for current session
export PATH="$install/bin:$PATH"

msg "Clang is ready to use!"
msg "Clang path: $install/bin/clang"
msg "To use clang in your build, add it to PATH:"
msg "  export PATH=\"$install/bin:\$PATH\""
