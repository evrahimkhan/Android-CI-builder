# Android-CI
Build Kernel and Create AnyKernel Flashable ZIP Using Github Action

## Overview
This project builds Android kernels and creates AnyKernel flashable ZIP files for easy installation. The image repacking process has been removed to avoid boot issues when flashing individual boot.img files.

## Key Features
- Builds Android kernels from source
- Creates AnyKernel flashable ZIP files (these work reliably)
- No more problematic individual image files (boot.img, vendor_boot.img, etc.)
- Preserves all kernel build functionality

## Important Notes
- The build process now only creates AnyKernel ZIP files
- Individual boot images are no longer generated to prevent fastboot issues
- Flash the generated ZIP file using custom recoveries like TWRP or OrangeFox
