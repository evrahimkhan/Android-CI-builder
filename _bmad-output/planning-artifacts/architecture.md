# Architecture Documentation - Android-CI-builder

## Executive Summary
Android-CI-builder is a CI/CD automation platform designed for building Android kernels using GitHub Actions. The system provides a universal solution for kernel developers to automate the compilation, packaging, and distribution of custom Android kernels.

## Technology Stack
| Category | Technology | Version/Details |
|----------|------------|-----------------|
| **Platform** | GitHub Actions | Ubuntu 22.04 runner |
| **Scripting** | Bash | Standard shell scripting |
| **Compiler** | Proton Clang | Cached via GitHub Actions |
| **Caching** | ccache | 5GB cache limit |
| **Compression** | xz, zip | For packaging artifacts |
| **Notifications** | Telegram API | Via webhook integration |

## Architecture Pattern
The system implements a **CI/CD Pipeline Architecture** with the following characteristics:

### 1. Event-Driven Processing
- Triggered by manual dispatch in GitHub Actions
- Parameterized inputs for flexible kernel building
- Asynchronous processing with status tracking

### 2. Modular Script Architecture
- Separated concerns across multiple bash scripts
- Each script handles a specific aspect of the build process
- Reusable components with clear interfaces

### 3. Caching and Optimization
- Multi-layer caching (dependencies, compiler, build artifacts)
- Efficient resource utilization through caching
- Parallel processing where possible

## Data Architecture
### Input Data
- **Kernel Source**: Git URL pointing to kernel repository
- **Kernel Branch**: Git branch to build from
- **Device Codename**: For naming and identification
- **Defconfig**: Kernel configuration file name
- **Base Images**: Optional boot/vendor_boot/init_boot images for safe repacking
- **Custom Configurations**: Kconfig branding options

### Output Data
- **Compiled Kernel**: Built kernel image (Image.gz, Image, etc.)
- **Flashable ZIP**: AnyKernel-based installation package
- **Repacked Images**: Modified boot/vendor_boot/init_boot images
- **Build Logs**: Compilation output and error logs
- **Artifacts**: Packaged files for distribution

## API Design
### GitHub Actions Interface
The system exposes a parameterized GitHub Actions workflow with the following inputs:

```
kernel_source: string (required) - Git URL of kernel source
kernel_branch: string (required) - Git branch to build
device: string (required) - Device codename for naming
defconfig: string (required) - Kernel defconfig name
base_boot_img_url: string (optional) - Base boot.img URL
enable_custom_config: choice (required) - Enable custom Kconfig branding
config_localversion: string (optional) - Custom localversion string
config_default_hostname: string (optional) - Custom hostname
config_uname_override_string: string (optional) - Custom uname string
config_cc_version_text: string (optional) - Custom compiler version text
```

### Script Interfaces
Each CI script accepts specific parameters:
- `build_kernel.sh`: defconfig name
- `clone_kernel.sh`: kernel source URL and branch
- `package_anykernel.sh`: device name and optional base image URLs

## Component Overview
### 1. CI/CD Orchestration Layer
- **Component**: `.github/workflows/kernel-ci.yml`
- **Responsibility**: Workflow orchestration and scheduling
- **Technology**: GitHub Actions
- **Interface**: Manual dispatch with parameters

### 2. Build System Layer
- **Components**: `ci/*.sh` scripts
- **Responsibilities**: Kernel compilation, packaging, and artifact generation
- **Technology**: Bash scripting with Linux tools
- **Interfaces**: Command-line parameters and environment variables

### 3. Packaging Layer
- **Component**: `anykernel/` directory
- **Responsibility**: Creating flashable kernel packages
- **Technology**: AnyKernel3 installer framework
- **Interface**: Template-based customization

### 4. Notification Layer
- **Component**: `ci/telegram.sh`
- **Responsibility**: Build status notifications
- **Technology**: Telegram Bot API
- **Interface**: Webhook integration

## Source Tree
See `source-tree-analysis.md` for detailed directory structure and file purposes.

## Development Workflow
1. **Initialization**: Dependencies installed via `install_deps.sh`
2. **Setup**: Tools cached and prepared (mkbootimg, clang, ccache)
3. **Source Retrieval**: Kernel cloned via `clone_kernel.sh`
4. **Compilation**: Kernel built via `build_kernel.sh`
5. **Detection**: GKI status determined via `detect_gki.sh`
6. **Packaging**: Artifacts created via `package_anykernel.sh` (repack_images REMOVED)
7. **Distribution**: Artifacts uploaded via GitHub Actions
8. **Notification**: Status sent via `telegram.sh`

## Deployment Architecture
The system is designed to run exclusively in GitHub Actions environment:
- **Runtime**: Ubuntu 22.04 virtual machines
- **Storage**: GitHub Actions workspace and artifact storage
- **Networking**: Internet access for git cloning and notifications
- **Security**: Standard GitHub Actions security model
- **Scalability**: Scales with GitHub Actions infrastructure

## Testing Strategy
The system includes:
- **Build Verification**: Each kernel build produces logs for verification
- **Success/Failure Tracking**: Environment variables track build outcomes
- **Artifact Validation**: Generated files are automatically uploaded for inspection
- **Error Handling**: Comprehensive error detection and logging