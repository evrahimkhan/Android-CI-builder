# API Contracts - Android-CI-builder

## Overview
Android-CI-builder is a CI/CD automation system for building Android kernels. Rather than traditional APIs, it exposes interfaces through GitHub Actions workflow parameters and command-line script arguments.

## GitHub Actions Interface
### Workflow Endpoint: `.github/workflows/kernel-ci.yml`

#### Manual Dispatch Parameters
The workflow accepts the following parameters when triggered manually:

**Required Parameters:**
- `kernel_source` (string)
  - Description: Git URL of the kernel source repository
  - Example: `"https://github.com/LineageOS/android_kernel_xiaomi_sm6150.git"`
  - Validation: Must be a valid Git repository URL

- `kernel_branch` (string)
  - Description: Git branch to build from the kernel source
  - Example: `"lineage-20.0"` or `"android-4.19-stable"`
  - Validation: Must be a valid branch name in the repository

- `device` (string)
  - Description: Device codename for naming artifacts and identification
  - Example: `"sweet"` or `"raphael"`
  - Validation: Alphanumeric with hyphens/underscores allowed

- `defconfig` (string)
  - Description: Kernel defconfig file name to use for building
  - Example: `"vendor/sweet_defconfig"` or `"msmperf_defconfig"`
  - Validation: Must correspond to an actual defconfig file in the kernel source

**Optional Parameters:**
- `base_boot_img_url` (string)
  - Description: URL to a base boot.img for safe repacking
  - Default: `""` (empty)
  - Example: `"https://example.com/boot.img"`

- `base_vendor_boot_img_url` (string)
  - Description: URL to a base vendor_boot.img for safe repacking
  - Default: `""` (empty)
  - Example: `"https://example.com/vendor_boot.img"`

- `base_init_boot_img_url` (string)
  - Description: URL to a base init_boot.img for safe repacking
  - Default: `""` (empty)
  - Example: `"https://example.com/init_boot.img"`

- `enable_custom_config` (choice)
  - Description: Enable custom Kconfig branding options
  - Default: `"false"`
  - Options: `["false", "true"]`

- `config_localversion` (string)
  - Description: Custom value for CONFIG_LOCALVERSION
  - Default: `"-CI"`
  - Example: `"-custom-build"`

- `config_default_hostname` (string)
  - Description: Custom value for CONFIG_DEFAULT_HOSTNAME
  - Default: `"CI Builder"`
  - Example: `"MyKernelBuilder"`

- `config_uname_override_string` (string)
  - Description: Custom value for CONFIG_UNAME_OVERRIDE_STRING
  - Default: `""` (empty)
  - Example: `"Custom Kernel 1.0"`

- `config_cc_version_text` (string)
  - Description: Override for CONFIG_CC_VERSION_TEXT
  - Default: `""` (auto-detected)
  - Example: `"clang-custom"`

## Script Command-Line Interfaces

### `ci/clone_kernel.sh`
**Endpoint**: Command-line script
**Method**: Execute
**Parameters**:
- `$1` (string, required): Kernel source Git URL
- `$2` (string, required): Kernel branch name

**Example**:
```bash
./ci/clone_kernel.sh "https://github.com/kernel/repo.git" "main"
```

**Response**: Clones the kernel source to the `kernel/` directory

### `ci/build_kernel.sh`
**Endpoint**: Command-line script
**Method**: Execute
**Parameters**:
- `$1` (string, required): Defconfig name

**Example**:
```bash
./ci/build_kernel.sh "vendor/device_defconfig"
```

**Response**: 
- Sets environment variables: `SUCCESS`, `BUILD_TIME`, `KERNEL_VERSION`, `CLANG_VERSION`
- Creates build artifacts in `kernel/out/`
- Generates `build.log` and potentially `error.log`

### `ci/detect_gki.sh`
**Endpoint**: Command-line script
**Method**: Execute
**Parameters**: None

**Response**:
- Sets environment variable: `KERNEL_TYPE` to either `"GKI"` or `"NON-GKI"`

### `ci/package_anykernel.sh`
**Endpoint**: Command-line script
**Method**: Execute
**Parameters**:
- `$1` (string, required): Device codename
- `$2` (string, optional): Base boot.img URL
- `$3` (string, optional): Base vendor_boot.img URL
- `$4` (string, optional): Base init_boot.img URL

**Response**: Creates a flashable AnyKernel ZIP file

### `ci/repack_images.sh`
**Endpoint**: Command-line script
**Method**: Execute
**Parameters**:
- `$1` (string, required): Device codename
- `$2` (string, optional): Base boot.img URL
- `$3` (string, optional): Base vendor_boot.img URL
- `$4` (string, optional): Base init_boot.img URL

**Response**: Creates repacked boot images (compressed with xz)

## Environment Variables Interface
The system uses several environment variables for configuration and communication:

### Input Variables (Set by Workflow)
- `ARCH`: Target architecture (typically "arm64")
- `SUBARCH`: Sub-architecture (typically "arm64")
- `TG_TOKEN`: Telegram bot token (optional)
- `TG_CHAT_ID`: Telegram chat ID (optional)
- `CCACHE_DIR`: Directory for ccache storage
- `CUSTOM_CONFIG_ENABLED`: Flag to enable custom Kconfig branding
- `CFG_*`: Various configuration values for kernel branding

### Output Variables (Set by Scripts)
- `SUCCESS`: Build success status (0=failure, 1=success)
- `BUILD_TIME`: Time taken for build in seconds
- `KERNEL_VERSION`: Kernel version string
- `CLANG_VERSION`: Clang compiler version
- `KERNEL_TYPE`: Kernel type ("GKI" or "NON-GKI")

## Notification Interface
### Telegram API Integration
The system integrates with Telegram API through `ci/telegram.sh`:

**Endpoints**:
- `start`: Notify build start
- `success`: Notify build success
- `failure`: Notify build failure

**Parameters**:
- `$1`: Device codename
- Additional parameters depending on notification type

## Authentication Requirements
- GitHub Actions: Authenticates using repository permissions
- Telegram API: Requires `TG_TOKEN` and `TG_CHAT_ID` secrets
- Git repositories: Public repositories accessible by default; private repositories require appropriate tokens

## Example Requests
### GitHub Actions Dispatch
```yaml
curl -X POST \
  -H "Authorization: token YOUR_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/USER/REPO/actions/workflows/kernel-ci.yml/dispatches \
  -d '{
    "ref": "main",
    "inputs": {
      "kernel_source": "https://github.com/kernel/repo.git",
      "kernel_branch": "main",
      "device": "test-device",
      "defconfig": "vendor/device_defconfig"
    }
  }'
```

### Local Script Execution
```bash
# Clone kernel
./ci/clone_kernel.sh "https://github.com/kernel/repo.git" "main"

# Build kernel
./ci/build_kernel.sh "vendor/device_defconfig"

# Package for flashing
./ci/package_anykernel.sh "test-device" "" "" ""
```