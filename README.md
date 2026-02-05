# Android-CI
Build Kernel and Create AnyKernel Flashable ZIP Using Github Action

## Overview
This project builds Android kernels and creates AnyKernel flashable ZIP files for easy installation.

## Key Features
- Builds Android kernels from source
- Creates AnyKernel flashable ZIP files (these work reliably)
- Preserves all kernel functionality
- Flash the generated ZIP file using custom recoveries like TWRP or OrangeFox

## How to Use

### Forking the Repository
1. Click the "Fork" button at the top-right corner of this repository
2. Choose your personal account or organization to fork to
3. Wait for the forking process to complete

### Environment and Setup Process
1. Navigate to your forked repository
2. Go to Settings > Secrets and Variables > Actions
3. Add the following secrets (optional):
   - `TG_TOKEN`: Telegram bot token for notifications and direct file upload (optional)
   - `TG_CHAT_ID`: Telegram chat ID for notifications and direct file upload (optional)
4. Go to Actions tab and enable workflows for your repository
5. Ensure GitHub Actions are enabled in your repository settings

### Using the Kernel Building Workflow
1. Go to the "Actions" tab in your repository
2. Select "Android Kernel CI" from the left sidebar
3. Click "Run workflow"
4. Fill in the required parameters:
    - **Kernel source git URL**: URL to your kernel source repository
    - **Kernel branch**: Branch name in the kernel repository
    - **Device codename**: Device codename for naming purposes
    - **Kernel defconfig**: Defconfig file (e.g., vendor/moonstone_defconfig)
    - **Enable custom Kconfig branding**: Whether to enable custom branding
    - **CONFIG_LOCALVERSION**: Local version string (optional)
    - **CONFIG_DEFAULT_HOSTNAME**: Hostname for the kernel (optional)
    - **CONFIG_UNAME_OVERRIDE_STRING**: Uname override string (optional)
    - **CONFIG_CC_VERSION_TEXT**: Compiler version text override (optional)
    - **Enable NetHunter kernel configuration**: Enable Kali NetHunter compatibility (optional)
    - **NetHunter configuration level**: Choose "basic" or "full" (optional, default: basic)
5. Click "Run workflow" to start the build process

### NetHunter Kernel Configuration

Enable NetHunter kernel configuration to build kernels compatible with Kali NetHunter penetration testing platform.

**Configuration Options:**
- **Enable NetHunter kernel configuration**: Set to `true` to enable NetHunter-specific kernel configs
- **NetHunter configuration level**: Choose between two levels:
  - **basic**: Essential NetHunter features (USB, Bluetooth, core networking)
  - **full**: Complete NetHunter support including WiFi drivers, SDR, CAN bus, and NFS

**Kernel Compatibility:**
The NetHunter configuration is designed to work universally across all modern Android kernel versions:
- Kernel 4.x (Legacy devices)
- Kernel 5.x (GKI 1.0/2.0 devices)
- Kernel 6.x+ (Latest devices)

The configuration automatically detects your kernel version and applies only compatible options. For GKI 2.0 kernels (5.10+), certain configurations are skipped as they are better handled as vendor modules.

**What's Included:**
- **Basic Level (25+ configs)**: USB gadget support, Bluetooth HID, wireless extensions, core networking
- **Full Level (90+ configs)**: All basic features plus wireless LAN drivers (Atheros, MediaTek, Realtek, Ralink), SDR support (RTL-SDR, HackRF), CAN bus support, NFS client/server

**Note**: Full configuration may increase kernel size. Use basic level for devices with limited storage.

### Understanding the Build Process
- The workflow will clone your kernel source and build it using Proton Clang
- It will create an AnyKernel flashable ZIP file
- If the first build fails, it will automatically patch and retry 2nd time
- NetHunter configurations (if enabled) are applied with automatic kernel version detection
- Artifacts will be available for download after completion
- Telegram notifications and direct file will be sent if `TG_TOKEN` and `TG_CHAT_ID` configured.
