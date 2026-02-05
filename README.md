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
5. Click "Run workflow" to start the build process

### Understanding the Build Process
- The workflow will clone your kernel source and build it using Proton Clang
- It will create an AnyKernel flashable ZIP file
- If the first build fails, it will automatically patch and retry 2nd time
- Artifacts will be available for download after completion
- Telegram notifications and direct file will be sent if `TG_TOKEN` and `TG_CHAT_ID` configured.
