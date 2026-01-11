# Component Inventory - Android-CI-builder

## Overview
This document catalogs all components in the Android-CI-builder project, categorizing them by type and function.

## Script Components

### Core Build Scripts
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| build_kernel | `ci/build_kernel.sh` | Build Script | Main kernel compilation logic with ccache integration, custom Kconfig support, and build time tracking |
| clone_kernel | `ci/clone_kernel.sh` | Utility Script | Clones kernel source from Git repository with specified branch |
| detect_gki | `ci/detect_gki.sh` | Utility Script | Detects if kernel is GKI (Generic Kernel Image) or non-GKI |
| install_deps | `ci/install_deps.sh` | Setup Script | Installs required build dependencies on Ubuntu system |

### Packaging Scripts
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| package_anykernel | `ci/package_anykernel.sh` | Packaging Script | Creates AnyKernel flashable ZIP from built kernel |
| repack_images | `ci/repack_images.sh` | Packaging Script | Repacks boot images with base images for safe flashing |
| ensure_anykernel_core | `ci/ensure_anykernel_core.sh` | Utility Script | Ensures AnyKernel core files exist before packaging |

### Setup Scripts
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| setup_aosp_mkbootimg | `ci/setup_aosp_mkbootimg.sh` | Setup Script | Downloads and compiles AOSP mkbootimg tool |
| setup_proton_clang | `ci/setup_proton_clang.sh` | Setup Script | Downloads and sets up Proton Clang compiler |
| patch_polly | `ci/patch_polly.sh` | Utility Script | Patches unsupported Polly compiler flags |

### Utility Scripts
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| run_logged | `ci/run_logged.sh` | Wrapper Script | Wrapper to add logging to command execution |
| telegram | `ci/telegram.sh` | Notification Script | Sends build status notifications via Telegram API |

## Configuration Components

### GitHub Actions Workflow
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| kernel-ci | `.github/workflows/kernel-ci.yml` | CI/CD Configuration | Main GitHub Actions workflow defining the kernel building pipeline |

### AnyKernel Template
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| anykernel | `anykernel/anykernel.sh` | Template Script | AnyKernel3 installer script template for creating flashable ZIPs |

## Documentation Components
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| README | `README.md` | Documentation | Project overview and basic usage instructions |

## BMAD Framework Components
| Component Name | File Path | Type | Description |
|----------------|-----------|------|-------------|
| _bmad | `_bmad/` | Framework | BMAD framework files and configuration |
| _bmad-output | `_bmad-output/` | Framework | BMAD output artifacts and documentation |

## Reusable vs Specific Components

### Reusable Components
- `run_logged.sh`: Generic wrapper for logging command execution
- `telegram.sh`: Generic notification system that can be adapted
- `install_deps.sh`: Generic dependency installation script
- AnyKernel template: Reusable for different kernel projects

### Specific Components
- `build_kernel.sh`: Specific to kernel building process
- `detect_gki.sh`: Specific to Android kernel GKI detection
- `package_anykernel.sh`: Specific to AnyKernel packaging
- `kernel-ci.yml`: Specific to GitHub Actions environment

## Design System Elements
### Shell Scripting Patterns
- Error handling with `set -euo pipefail`
- Parameter validation with `${1:?required parameter}`
- Environment variable management
- Logging and status tracking
- Caching strategies (ccache, compiler, tools)

### CI/CD Patterns
- Parameterized workflows
- Caching strategies
- Artifact management
- Notification systems
- Error handling and recovery

## Component Dependencies
### Build Process Dependencies
```
install_deps → setup_aosp_mkbootimg, setup_proton_clang
clone_kernel → (none, but kernel source required for build)
build_kernel → detect_gki, patch_polly (indirectly)
detect_gki → build_kernel (requires built kernel config)
package_anykernel → build_kernel (requires built kernel)
repack_images → build_kernel (requires built kernel)
```

### GitHub Actions Dependencies
```
kernel-ci workflow → All ci/*.sh scripts
```

### Notification Dependencies
```
telegram → build_kernel (depends on SUCCESS variable)
```