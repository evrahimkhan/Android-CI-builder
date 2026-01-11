# Development Guide - Android-CI-builder

## Prerequisites and Dependencies
### System Requirements
- Linux-based system (Ubuntu 22.04 recommended)
- Git for version control
- Bash shell environment
- Basic build tools (make, bc, flex, etc.)

### Required Tools
The system automatically installs dependencies via `ci/install_deps.sh`:
```bash
sudo apt-get update
sudo apt-get install -y \
  bc bison build-essential ccache curl flex git \
  libelf-dev libssl-dev make python3 rsync unzip wget zip zstd \
  dwarves xz-utils perl
```

## Environment Setup
### Local Development
1. Clone the repository:
```bash
git clone https://github.com/your-repo/Android-CI-builder.git
cd Android-CI-builder
```

2. Make CI scripts executable:
```bash
chmod +x ci/*.sh
```

### GitHub Actions Environment
The system is designed to run in GitHub Actions with:
- Ubuntu 22.04 runner
- Pre-installed Git, ccache, and compression tools
- Access to GitHub's artifact storage

## Local Development Commands
### Running Individual Scripts
Each script in the `ci/` directory can be run independently for testing:

```bash
# Install dependencies
./ci/install_deps.sh

# Clone a kernel source (example)
./ci/clone_kernel.sh "https://github.com/kernel-repo/kernel_source.git" "main"

# Build a kernel (example - requires kernel to be cloned first)
./ci/build_kernel.sh "vendor/device_defconfig"
```

### Testing the Build Process
1. Prepare environment:
```bash
chmod +x ci/*.sh
./ci/install_deps.sh
```

2. Clone a test kernel:
```bash
./ci/clone_kernel.sh "KERNEL_SOURCE_URL" "KERNEL_BRANCH"
```

3. Run the build:
```bash
./ci/build_kernel.sh "DEFCONFIG_NAME"
```

## Build Process
### Main Workflow Steps
1. **Dependency Installation**: `ci/install_deps.sh`
2. **Tool Setup**: Compiler (Proton Clang), mkbootimg, ccache
3. **Kernel Cloning**: `ci/clone_kernel.sh` with source URL and branch
4. **Kernel Building**: `ci/build_kernel.sh` with defconfig
5. **GKI Detection**: `ci/detect_gki.sh` to determine kernel type
6. **Packaging**: `ci/package_anykernel.sh` or `ci/repack_images.sh`
7. **Artifact Upload**: Automatic via GitHub Actions

### Configuration Options
The system supports custom Kconfig branding through environment variables:
- `CUSTOM_CONFIG_ENABLED`: Enable custom Kconfig branding
- `CFG_LOCALVERSION`: Custom localversion string
- `CFG_DEFAULT_HOSTNAME`: Custom hostname
- `CFG_UNAME_OVERRIDE_STRING`: Custom uname string
- `CFG_CC_VERSION_TEXT`: Custom compiler version text

## Testing Approach and Commands
### Unit Testing
Each script can be tested individually:
- Test dependency installation: `./ci/install_deps.sh`
- Test kernel cloning: `./ci/clone_kernel.sh <source> <branch>`
- Test kernel building: `./ci/build_kernel.sh <defconfig>`

### Integration Testing
The full workflow is tested through GitHub Actions:
- Manual dispatch with test parameters
- Verification of build logs
- Validation of generated artifacts

### Error Handling
- Build logs are captured in `build.log` and `error.log`
- Success/failure status tracked via `SUCCESS` environment variable
- Telegram notifications for build status (if configured)

## Common Development Tasks
### Adding New Device Support
1. Identify the correct defconfig name for the device
2. Ensure the kernel source supports the target device
3. Test the build process with the new defconfig

### Modifying Build Process
1. Edit the relevant script in `ci/` directory
2. Test changes with a small kernel repository
3. Submit pull request with changes

### Updating Compiler or Tools
1. Modify `ci/setup_proton_clang.sh` to use new compiler version
2. Update caching keys in GitHub workflow if needed
3. Test with various kernel sources

### Adding New Features
1. Create new script in `ci/` directory if needed
2. Update GitHub workflow to include new step
3. Add appropriate caching and error handling

## Code Style and Conventions
### Shell Scripting
- Use `#!/usr/bin/env bash` shebang
- Include `set -euo pipefail` for error handling
- Use descriptive variable names
- Add comments for complex operations
- Follow consistent indentation (2 spaces)

### Error Handling
- Use `|| true` for commands that may fail but shouldn't stop the workflow
- Use `set +e` and `set -e` appropriately for commands that may fail
- Log errors to appropriate files when needed

### Parameter Handling
- Use parameter expansion with defaults: `${VAR:-default}`
- Validate required parameters at the beginning of scripts
- Use meaningful error messages for missing parameters