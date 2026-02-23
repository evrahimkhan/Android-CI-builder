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

**Note:** This project uses **GNU ARM GCC** as the default compiler (instead of Clang).

### NetHunter Kernel Configuration

Enable NetHunter kernel configuration to build kernels compatible with Kali NetHunter penetration testing platform.

#### How to Enable NetHunter Support

1. **Fork this repository** (if not already done)
2. Go to **Actions** → **Android Kernel CI** → **Run workflow**
3. In the workflow dispatch form, set:
   - **Enable NetHunter kernel configuration**: `true`
   - **NetHunter configuration level**: Choose `basic` or `full`
4. Fill in other required parameters (kernel URL, branch, device, defconfig)
5. Click **Run workflow**

#### Configuration Levels

**Basic Level (Recommended for most users):**
- Essential NetHunter features
- USB gadget support (HID, mass storage, RNDIS)
- Bluetooth HID support
- Core networking (MAC80211, CFG80211)
- 25+ kernel configurations
- Smaller kernel size (~2-5MB increase)
- Works on all kernel versions (4.x, 5.x, 6.x+)

**Full Level (Advanced users):**
- Everything in basic level
- Wireless LAN drivers (Atheros, MediaTek, Realtek, Ralink)
- SDR support (RTL-SDR, HackRF)
- CAN bus support for vehicle diagnostics
- NFS client/server for network storage
- 90+ kernel configurations
- Larger kernel size (~5-10MB increase)
- Best for specialized penetration testing hardware

#### When to Use Each Level

**Use Basic if:**
- Building for daily driver phone
- Limited storage space on device
- Need stable, tested configuration
- Using NetHunter for basic pentesting (WiFi, Bluetooth, USB attacks)

**Use Full if:**
- Building dedicated pentesting device
- Need specialized hardware support
- Have adequate storage space
- Using external WiFi adapters or SDR hardware
- Need CAN bus for vehicle testing

#### Kernel Compatibility

The NetHunter configuration automatically adapts to your kernel version:

| Kernel Version | GKI Status | Compatibility | Notes |
|---------------|------------|---------------|-------|
| 4.x - 4.19 | Non-GKI | ✅ Full support | All configs available |
| 5.4 | GKI 1.0 | ✅ Good support | Some vendor modules separate |
| 5.10 - 5.15 | GKI 2.0 | ✅ Supported | USB gadget configs may be limited |
| 6.1+ | GKI 2.0 | ✅ Supported | Same as 5.10+ |

The configuration script automatically detects your kernel version and applies only compatible options.

#### What's Included

**Basic Level Features:**
```
USB Gadget Support:
  - USB HID (keyboard/mouse injection)
  - USB Mass Storage
  - USB RNDIS (networking)
  - USB CDC ACM (modem)

Bluetooth:
  - Classic Bluetooth HID
  - Bluetooth Low Energy
  - Multiple USB Bluetooth dongles

Networking:
  - Wireless extensions
  - MAC80211 (core WiFi)
  - cfg80211 (configuration)
```

**Full Level Additional Features:**
```
Wireless LAN Drivers:
  - Atheros: ATH9K, CARL9170, ATH6KL
  - MediaTek: MT7601U
  - Realtek: RTL8187, RTL8192CU
  - Ralink: RT2X00 series
  - ZyDAS: ZD1211

SDR (Software Defined Radio):
  - RTL-SDR support (RTL2830, RTL2832)
  - AirSpy
  - HackRF
  - Mirics MSi2500

CAN Bus:
  - CAN subsystem
  - CAN protocols (RAW, BCM, GW)
  - USB CAN adapters
  - Virtual CAN

Network File Systems:
  - NFS client v2/v3/v4
  - NFS server
  - Remote file access
```

#### Step-by-Step Usage Guide

**Step 1: Prepare Your Kernel Source**
Ensure your kernel repository:
- Is publicly accessible (or you have access)
- Has a valid defconfig file
- Compiles successfully without NetHunter

**Step 2: Run the Workflow**
1. Go to **Actions** tab in your forked repository
2. Click **Android Kernel CI**
3. Click **Run workflow** button
4. Fill in the form:
   ```
   Kernel source git URL: https://github.com/yourusername/your-kernel.git
   Kernel branch: main (or your branch)
   Device codename: yourdevice
   Kernel defconfig: vendor/yourdevice_defconfig
   Enable NetHunter kernel configuration: true
   NetHunter configuration level: basic (or full)
   ```

**Step 3: Monitor the Build**
- Watch the Actions tab for build progress
- NetHunter configuration is applied automatically after defconfig
- Check build logs for "NetHunter Kernel Configuration" section

**Step 4: Download and Flash**
1. Wait for build to complete
2. Download `Kernel-*.zip` from Artifacts
3. Flash via TWRP/OrangeFox recovery
4. Boot into NetHunter

#### Troubleshooting NetHunter Configuration

**Build fails after enabling NetHunter:**
```
1. Check build.log for error messages
2. Look for "Notice: CONFIG_XXX not available" - normal, configs skipped
3. If build fails, try basic level instead of full
4. Verify your kernel defconfig is valid
```

**Kernel boots but NetHunter doesn't work:**
```
1. Check if kernel was built with NetHunter enabled
2. Verify defconfig includes required options
3. Check NetHunter app for compatibility
4. Try different configuration level
```

**How to verify configs were applied:**
```bash
# Download and extract build artifact
cd /path/to/downloaded/artifact
tar -xzf kernel-build-logs.tar.gz

# Check for NetHunter configuration
grep -A 20 "NetHunter Kernel Configuration" build.log

# Look for:
# - "Detected kernel version: X.Y"
# - "GKI kernel detected" or "Non-GKI kernel detected"
# - "Configuration level: basic/full"
# - "NetHunter configuration applied successfully"
```

**Configs being skipped ("not available"):**
- This is **normal** and expected behavior
- The script skips configs not present in your kernel version
- This ensures compatibility across different kernel versions
- Check `build.log` for full list of applied vs skipped configs

**GKI 2.0 kernel limitations (5.10+):**
- Some USB gadget functions may be vendor modules
- Use full level for best hardware support
- Check your device vendor's kernel for missing modules
- Consider using older kernels (4.x-5.4) for maximum compatibility

#### Tips for Best Results

1. **Start with Basic Level**: Test basic level first, then try full if needed
2. **Check Kernel Version**: Know your kernel version before building
3. **Test Regular Build**: Ensure kernel builds without NetHunter first
4. **Monitor Storage**: Full level adds ~5-10MB to kernel size
5. **Use Compatible Devices**: Some devices work better with NetHunter than others
6. **Check Logs**: Always review build.log for NetHunter configuration messages

#### Additional Resources

- [Kali NetHunter Documentation](https://www.kali.org/docs/nethunter/)
- [NetHunter Kernel Configuration Guide](https://www.kali.org/docs/nethunter/nethunter-kernel-2-config-1/)
- [Supported Devices List](https://www.kali.org/docs/nethunter/supported-devices/)

### Understanding the Build Process
- The workflow will clone your kernel source and build it using **GCC ARM Toolchain**
- It will create an AnyKernel flashable ZIP file
- If the first build fails, it will automatically patch and retry 2nd time
- NetHunter configurations (if enabled) are applied with automatic kernel version detection
- Artifacts will be available for download after completion
- Telegram notifications and direct file will be sent if `TG_TOKEN` and `TG_CHAT_ID` configured.

### RTL8188eus USB WiFi Driver Support

This project supports building kernels with **RTL8188eus USB WiFi driver** built-in for external USB wireless adapters.

#### Supported Chips
- RTL8188EU
- RTL8188CU
- RTL8188RU
- RTL8723AU
- RTL8191CU
- RTL8192CU

#### How to Enable

1. Go to **Actions** → **Android Kernel CI** → **Run workflow**
2. In the workflow dispatch form, set:
   - **Enable RTL8188eus USB WiFi driver (built-in)**: `true`
3. Fill in other required parameters (kernel URL, branch, device, defconfig)
4. Click **Run workflow**

#### How It Works

- Uses the **in-kernel rtl8xxxu driver** (no external patching needed)
- Driver is **built directly into the kernel** (not as a loadable module)
- Works **independently** from NetHunter configuration
- Can be enabled with or without NetHunter support

#### Usage Notes

- The driver is built into the kernel Image, no separate `.ko` module needed
- Works with Kali NetHunter for external WiFi adapter support
- Compatible with kernel versions 4.x, 5.x, and 6.x+

#### Troubleshooting

**Driver not appearing in kernel:**
- Verify `enable_rtl8188eus_driver` is set to `true`
- Check build logs for "RTL8188eu driver" configuration messages
- The driver uses in-kernel `rtl8xxxu` - check if your kernel has this driver

**Build fails:**
- Check if your kernel source supports RTL8XXXU driver
- Try with a different kernel version
- Check build.log for specific errors
