# Source Tree Analysis - Android-CI-builder

## Complete Directory Structure
```
Android-CI-builder/
├── anykernel/                 # AnyKernel template (Part: packaging)
│   └── anykernel.sh          # Main AnyKernel installer script - Defines kernel flashing logic
├── ci/                        # CI/CD automation scripts (Part: build-system)
│   ├── build_kernel.sh       # Core kernel building logic - Main compilation process
│   ├── clone_kernel.sh       # Kernel source cloning - Downloads kernel source
│   ├── detect_gki.sh         # GKI detection logic - Identifies GKI/non-GKI kernels
│   ├── ensure_anykernel_core.sh # Ensures AnyKernel core exists - Prepares packaging
│   ├── install_deps.sh       # Dependency installation - Sets up build environment
│   ├── package_anykernel.sh  # AnyKernel packaging - Creates flashable ZIP
│   ├── patch_polly.sh        # Patches unsupported Polly flags - Compiler compatibility
│   ├── repack_images.sh      # Image repacking utilities - Creates boot images
│   ├── run_logged.sh         # Wrapper for logged execution - Adds logging to commands
│   ├── setup_aosp_mkbootimg.sh # Sets up AOSP mkbootimg - Prepares image tools
│   ├── setup_proton_clang.sh # Sets up Proton Clang - Prepares compiler
│   └── telegram.sh           # Telegram notification system - Sends build notifications
├── .github/                   # GitHub configuration
│   └── workflows/            # GitHub Actions workflows
│       └── kernel-ci.yml     # Main CI/CD workflow definition - Orchestrates build process
├── .git/                     # Git metadata
├── .qwen/                    # Qwen configuration
├── _bmad/                    # BMAD framework files
├── _bmad-output/             # BMAD output artifacts
├── docs/                     # Documentation (created by BMAD)
└── README.md                 # Project overview and usage
```

## Critical Directories Explained

### `ci/` - Core Build System
This is the heart of the Android-CI-builder project containing all the automation scripts:
- **Purpose**: Contains all shell scripts that perform the kernel building process
- **Entry Points**: `build_kernel.sh`, `clone_kernel.sh`, `install_deps.sh`
- **Key Functions**: Kernel compilation, dependency management, artifact packaging
- **Integration Points**: Called by GitHub Actions workflow

### `anykernel/` - Packaging System
Template for creating flashable kernel ZIPs:
- **Purpose**: Provides a template for AnyKernel3-based kernel flashing packages
- **Key File**: `anykernel.sh` - Defines the installer logic
- **Integration Points**: Used by `package_anykernel.sh` to create distributable packages

### `.github/workflows/` - CI/CD Orchestration
Contains the GitHub Actions workflow:
- **Purpose**: Defines the CI/CD pipeline for kernel building
- **Entry Point**: `kernel-ci.yml` - Main workflow definition
- **Triggers**: Manual dispatch with configurable parameters
- **Functions**: Orchestrates the entire build process

## Entry Points

### GitHub Workflow Entry
- **File**: `.github/workflows/kernel-ci.yml`
- **Trigger**: Manual dispatch with parameters (kernel source, branch, device, defconfig)
- **Purpose**: Main entry point for the CI/CD process

### Shell Script Entry Points
- **`ci/build_kernel.sh`**: Entry point for kernel compilation (takes defconfig as parameter)
- **`ci/clone_kernel.sh`**: Entry point for kernel source cloning (takes source URL and branch)
- **`ci/install_deps.sh`**: Entry point for environment setup (installs required dependencies)

## Integration Points

### Between CI Scripts
- `run_logged.sh` wraps other scripts to add logging capabilities
- `build_kernel.sh` calls `detect_gki.sh` to determine kernel type
- `package_anykernel.sh` depends on successful build from `build_kernel.sh`

### External Integrations
- **Git**: Used by `clone_kernel.sh` to download kernel sources
- **GitHub Releases**: Artifacts uploaded via GitHub Actions
- **Telegram API**: Notifications sent via `telegram.sh`
- **AOSP Tools**: mkbootimg used for image manipulation
- **Proton Clang**: Compiler used for kernel compilation

## Key File Locations Highlighted

### Configuration & Parameters
- **Workflow Inputs**: Defined in `.github/workflows/kernel-ci.yml` (lines 7-37)
- **Environment Variables**: Set in workflow and passed to scripts
- **Custom Kconfig Options**: Handled in `build_kernel.sh` (lines 60-120)

### Build Process Flow
1. **Setup Phase**: `install_deps.sh` → `setup_aosp_mkbootimg.sh` → `setup_proton_clang.sh`
2. **Source Phase**: `clone_kernel.sh` (with source URL and branch)
3. **Build Phase**: `build_kernel.sh` (with defconfig parameter)
4. **Detection Phase**: `detect_gki.sh` (identifies kernel type)
5. **Packaging Phase**: `package_anykernel.sh` or `repack_images.sh`
6. **Notification Phase**: `telegram.sh` (with status updates)