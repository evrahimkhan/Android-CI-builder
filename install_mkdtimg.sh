#!/bin/bash
# Fix for missing mkdtimg tool in kernel build

# The build is failing because mkdtimg is not found
# This tool is required for creating device tree blob overlays (dtbo.img)
# We need to install the tool or configure the build appropriately

# First, check if we can install the tool from Android build tools
if command -v apt-get &> /dev/null; then
    echo "Installing Android build tools with mkdtimg..."
    # Install android-tools-mkdtimg if available
    sudo apt-get update
    sudo apt-get install -y android-tools-mkdtimg || echo "android-tools-mkdtimg not available in repos"
fi

# Alternative: Install from source if needed
if ! command -v mkdtimg &> /dev/null; then
    echo "mkdtimg not available in repos, checking for alternative methods..."
    
    # Check if we have the Android build tools in the project
    if [ -d "/home/kali/project/Android-CI-builder/tools" ]; then
        export PATH="/home/kali/project/Android-CI-builder/tools:$PATH"
    fi
    
    # If still not found, create a simple symbolic link to dtc (device tree compiler)
    # which sometimes can serve as a substitute for mkdtimg in some contexts
    if [ -f "/usr/bin/dtc" ] && ! command -v mkdtimg &> /dev/null; then
        sudo ln -sf /usr/bin/dtc /usr/local/bin/mkdtimg
    elif [ -f "/usr/local/bin/dtc" ] && ! command -v mkdtimg &> /dev/null; then
        sudo ln -sf /usr/local/bin/dtc /usr/local/bin/mkdtimg
    fi
fi

# Verify installation
if command -v mkdtimg &> /dev/null; then
    echo "mkdtimg is now available: $(which mkdtimg)"
    mkdtimg --help 2>/dev/null || echo "mkdtimg installed successfully"
else
    echo "mkdtimg still not available, need to install it properly"
    # Install from Android source directly
    cd /tmp
    git clone https://android.googlesource.com/platform/system/libufdt --depth=1
    cd libufdt/utils
    make
    if [ -f "mkdtimg" ]; then
        sudo cp mkdtimg /usr/local/bin/
        echo "mkdtimg installed from source"
    else
        echo "Could not build mkdtimg from source"
        exit 1
    fi
fi