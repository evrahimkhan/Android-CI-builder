# Deployment Guide - Android-CI-builder

## Overview
Android-CI-builder is designed to run exclusively in GitHub Actions environment. This guide covers how to set up and use the system for building Android kernels.

## Infrastructure Requirements
### GitHub Repository Setup
- Public or private GitHub repository
- Git submodules support (for recursive checkout)
- GitHub Actions enabled with sufficient minutes quota
- Secrets management for optional features (Telegram notifications)

### Resource Requirements
- GitHub Actions runner: Ubuntu 22.04
- Minimum 7GB disk space for build process
- Minimum 2-core CPU recommended for reasonable build times
- Internet access for Git cloning and dependency downloads
- Memory: At least 7GB RAM recommended for kernel compilation

## Deployment Process
### 1. Repository Setup
1. Fork or create a copy of the Android-CI-builder repository
2. Ensure GitHub Actions are enabled in repository settings
3. If using submodules, ensure they are properly configured

### 2. Secret Configuration (Optional)
For Telegram notifications, configure these secrets in your repository:
- `TG_TOKEN`: Telegram bot API token
- `TG_CHAT_ID`: Telegram chat ID for notifications

To add secrets:
1. Go to repository Settings
2. Navigate to Secrets and variables → Actions
3. Add new repository secrets with the above names

### 3. Workflow Activation
The workflow is automatically available in your repository under:
`.github/workflows/kernel-ci.yml`

## Configuration
### GitHub Actions Workflow Configuration
The main configuration is in `.github/workflows/kernel-ci.yml` which defines:
- Input parameters for the workflow
- Runner environment (Ubuntu 22.04)
- Caching strategies
- Notification settings
- Artifact retention settings

### Caching Configuration
The workflow implements multiple caching layers:
- Compiler cache (Proton Clang): Key based on version
- AOSP mkbootimg: Fixed key `aosp-mkbootimg-v1`
- ccache: Key based on runner OS, kernel branch, defconfig, and commit SHA

## Deployment Steps
### 1. Manual Dispatch
1. Navigate to Actions tab in your repository
2. Select "Android Kernel CI" workflow
3. Click "Run workflow"
4. Fill in the required parameters:
   - Kernel source Git URL
   - Kernel branch name
   - Device codename
   - Defconfig name
5. Fill in optional parameters as needed
6. Click "Run workflow"

### 2. Parameter Configuration
#### Required Parameters:
- **kernel_source**: Git URL of kernel source repository
  - Example: `https://github.com/LineageOS/android_kernel_xiaomi_sm6150.git`
- **kernel_branch**: Git branch to build from
  - Example: `lineage-20.0`
- **device**: Device codename for naming
  - Example: `sweet`
- **defconfig**: Kernel defconfig name
  - Example: `vendor/sweet_defconfig`

#### Optional Parameters:
- **base_boot_img_url**: URL to base boot.img for safe repacking
- **base_vendor_boot_img_url**: URL to base vendor_boot.img
- **base_init_boot_img_url**: URL to base init_boot.img
- **enable_custom_config**: Enable custom Kconfig branding
- **config_localversion**: Custom localversion string
- **config_default_hostname**: Custom hostname
- **config_uname_override_string**: Custom uname string
- **config_cc_version_text**: Custom compiler version text

## Post-Deployment Verification
### 1. Workflow Execution Check
- Monitor the workflow execution in GitHub Actions
- Check for any errors in the logs
- Verify that all steps complete successfully

### 2. Artifact Verification
After successful build, verify these artifacts are created:
- Build logs (`kernel/build.log`)
- Error logs (if any errors occurred)
- Flashable ZIP file (`Kernel-*.zip`) or repacked images
- GitHub release with tagged artifacts

### 3. Telegram Notifications (if configured)
- Verify that start, success, or failure notifications are sent
- Check that the correct device and build information is included

## Scaling Considerations
### Concurrency
- GitHub Actions concurrency limits apply
- Multiple simultaneous runs may be queued depending on your plan
- Consider using workflow dispatch conditions to prevent unwanted runs

### Resource Optimization
- Use ccache to speed up subsequent builds
- Leverage caching for compiler and tools
- Consider build matrix for multiple defconfigs if needed

## Maintenance and Updates
### 1. Updating the CI System
1. Pull latest changes from the main Android-CI-builder repository
2. Test changes with a non-critical kernel source
3. Update your repository with the changes

### 2. Monitoring Build Performance
- Monitor build times and resource usage
- Check ccache effectiveness
- Review logs for optimization opportunities

### 3. Security Considerations
- Regularly audit secrets and access tokens
- Keep dependencies updated through the `install_deps.sh` script
- Review any kernel sources for security implications

## Troubleshooting
### Common Issues
1. **Build failures**: Check `kernel/error.log` for specific error details
2. **Dependency issues**: Verify that `install_deps.sh` runs successfully
3. **Caching problems**: Clear caches if builds fail unexpectedly
4. **Permission errors**: Ensure the repository has proper permissions

### Debugging Steps
1. Examine the GitHub Actions logs for the failed step
2. Check the generated build logs in the artifacts
3. Verify all input parameters are correct
4. Test with a known working kernel source if issues persist

## Rollback Procedures
### Rolling Back Workflow Changes
1. Identify the commit that introduced the issue
2. Revert the changes or reset to a previous working commit
3. Test with a small kernel repository before full deployment