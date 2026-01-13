# Android-CI-builder Project Overview

## Project Name
Android-CI-builder - Build Kernel Universally Using Github Action

## Executive Summary
Android-CI-builder is a comprehensive CI/CD solution designed for building Android kernels using GitHub Actions. It provides a universal platform for kernel developers to build, package, and distribute custom Android kernels through automated workflows.

## Project Type Classification
Based on the analysis of the project structure and files, this project is classified as:
- **Primary Type**: Infrastructure/CI-CD automation
- **Secondary Type**: Embedded systems (Android kernel development)
- **Repository Type**: Monolith with focused functionality

## Technology Stack
- **Shell scripting**: Bash scripts for kernel building and automation
- **GitHub Actions**: CI/CD pipeline orchestration
- **Git**: Version control and kernel source management
- **Linux kernel build tools**: Clang, make, ccache, etc.
- **Compression tools**: xz, zip for packaging
- **Telegram API**: Notification system

## Architecture Pattern
The project follows a **CI/CD Pipeline Architecture** with the following characteristics:
- Modular shell script components
- GitHub Actions workflow orchestration
- Caching mechanisms (ccache, clang, mkbootimg)
- Artifact management and distribution
- Notification system integration

## Key Components
1. **CI Scripts** (`ci/` directory): Collection of bash scripts for kernel building process
2. **AnyKernel Template** (`anykernel/` directory): Template for kernel flashing packages
3. **GitHub Workflow** (`.github/workflows/kernel-ci.yml`): Main CI/CD pipeline definition
4. **Configuration System**: Parameterized build system with custom Kconfig options

## Repository Structure
```
Android-CI-builder/
├── anykernel/                 # AnyKernel template for flashable ZIPs
│   └── anykernel.sh           # Main AnyKernel installer script
├── ci/                        # CI/CD automation scripts
│   ├── build_kernel.sh        # Core kernel building logic
│   ├── clone_kernel.sh        # Kernel source cloning
│   ├── detect_gki.sh          # GKI detection logic
│   ├── install_deps.sh        # Dependency installation
│   ├── package_anykernel.sh   # AnyKernel packaging
│   ├── (removed) repack_images.sh       # Image repacking utilities - REMOVED
│   ├── telegram.sh            # Telegram notification system
│   └── ...                    # Additional utility scripts
├── .github/workflows/         # GitHub Actions workflows
│   └── kernel-ci.yml          # Main CI/CD workflow definition
└── README.md                  # Project documentation
```

## Development Workflow
1. **Trigger**: Manual dispatch with kernel source, branch, device, and defconfig parameters
2. **Setup**: Install dependencies, cache tools (clang, mkbootimg, ccache)
3. **Clone**: Download specified kernel source and branch
4. **Build**: Compile kernel with specified defconfig using clang
5. **Package**: Create AnyKernel flashable ZIP or repacked boot images
6. **Distribute**: Upload artifacts and create GitHub release
7. **Notify**: Send Telegram notifications on success/failure

## Key Features
- Universal kernel building support for various Android devices
- GKI (Generic Kernel Image) detection and handling
- Custom Kconfig branding options
- Telegram notification integration
- Caching mechanisms for faster builds
- Support for base boot images for safe repacking
- Artifact management and GitHub release creation