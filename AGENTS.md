# AGENTS.md

This file contains guidelines and commands for agentic coding agents working in this Android CI builder repository.

## Project Overview

This is an Android kernel build automation system that:
- Builds Android kernels from source using Proton Clang
- Creates AnyKernel flashable ZIP files for custom recovery installation
- Provides automated CI/CD via GitHub Actions
- Includes retry mechanisms and Polly flag patching
- Supports Telegram notifications and file sharing

## Build Commands

### Kernel Build Commands
```bash
# Configure kernel with defconfig
make O=out <defconfig>

# Build kernel with Proton Clang
make -j$(nproc) O=out LLVM=1 LLVM_IAS=1

# Update config with defaults (non-interactive)
make O=out olddefconfig

# Interactive config update (use with caution)
make O=out oldconfig
```

### CI Scripts Usage
```bash
# Install build dependencies
ci/install_deps.sh

# Clone kernel source
ci/clone_kernel.sh <git_url> <branch>

# Setup Proton Clang toolchain
ci/setup_proton_clang.sh

# Build kernel with error handling
ci/build_kernel.sh <defconfig>

# Package AnyKernel ZIP
ci/package_anykernel.sh <device_codename>

# Patch Polly flags on build failure
ci/patch_polly.sh

# Detect GKI kernel
ci/detect_gki.sh

# Apply NetHunter kernel configuration
ci/apply_nethunter_config.sh

# Test NetHunter configuration
ci/test_nethunter_config.sh
```

### Running Single Tests

#### NetHunter Configuration Tests
A comprehensive test suite is available for NetHunter configuration:
```bash
# Run NetHunter configuration test suite
bash ci/test_nethunter_config.sh

# The test suite includes:
# - Config existence checks
# - Config level validation (basic/full)
# - Safe config setters
# - GKI detection
# - Backup/restore functionality
# - Integration tests
# - Edge cases (invalid inputs, missing directories)
```

#### Kernel Build Tests
Traditional build validation:
```bash
# Test kernel build (run from kernel directory)
make O=out <defconfig> && make -j$(nproc) O=out LLVM=1 LLVM_IAS=1
```

## Code Style Guidelines

### Bash Scripting Standards

#### Shebang and Error Handling
- Always use `#!/usr/bin/env bash` as shebang
- Include `set -euo pipefail` immediately after shebang
- Use parameter expansion with `:?` for required arguments
- Validate all user inputs to prevent injection attacks

#### Input Validation Pattern
```bash
# Validate defconfig format
if [[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]]; then
  echo "ERROR: Invalid defconfig format: $DEFCONFIG" >&2
  exit 1
fi

# Validate git URLs
if [[ ! "$SRC" =~ ^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(:[0-9]+)?(/[a-zA-Z0-9._-]+)+\.git$ ]]; then
  echo "ERROR: Invalid git URL format: $SRC" >&2
  exit 1
fi
```

#### Function Naming and Structure
- Use snake_case for function names
- Prefix functions with descriptive verbs (set_, get_, validate_, etc.)
- Use local variables inside functions
- Return meaningful exit codes

```bash
set_kcfg_str() {
  local key="$1"
  local val="$2"
  # Sanitize inputs
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: Invalid key format: $key" >&2
    return 1
  fi
  # Function implementation
}
```

#### Variable Naming
- Use UPPER_CASE for environment variables and constants
- Use lower_case for local variables
- Use descriptive names (e.g., `KERNEL_VERSION` not `kv`)

#### Error Handling
- Always check command exit codes
- Use `|| true` for non-critical commands that may fail
- Provide meaningful error messages to stderr
- Exit with appropriate codes (0 for success, 1+ for errors)

#### Quoting and Expansion
- Quote all variable expansions: `"$VAR"`
- Use `printf` instead of `echo` for safety
- Escape special characters in user input

### YAML Standards (GitHub Actions)

#### Structure
- Use 2-space indentation
- Group related steps with descriptive names
- Use `if` conditions for optional steps
- Provide clear step descriptions

#### Environment Variables
```yaml
env:
  ARCH: arm64
  SUBARCH: arm64
  CCACHE_DIR: ${{ github.workspace }}/.ccache
```

#### Step Patterns
```yaml
- name: Descriptive step name
  if: env.SUCCESS == '1'
  shell: bash
  run: ci/run_logged.sh ci/script.sh "${{ inputs.parameter }}"
```

### Security Guidelines

#### Input Sanitization
- Validate all user-provided parameters
- Prevent path traversal attacks
- Sanitize strings before shell command execution
- Use allowlists rather than blocklists when possible

#### Command Injection Prevention
```bash
# Good: Use arrays to avoid word splitting
cmd=("clang" "--version")
"${cmd[@]}"

# Bad: Direct string expansion
cmd="clang --version"
$cmd
```

#### File Operations
- Validate file paths are within expected directories
- Use absolute paths when possible
- Check file existence before operations

### Import and Module Standards

#### Script Organization
- Keep CI scripts in `ci/` directory
- Make all scripts executable (`chmod +x`)
- Use consistent naming: `verb-noun.sh` pattern
- Include parameter validation at script start

#### Reusable Functions
- Create helper functions for common operations
- Use `ci/run_logged.sh` wrapper for consistent logging
- Share functions via sourcing when needed

### Testing and Validation

#### Build Validation
- Kernel build success is primary validation
- Check for required output files
- Validate kernel image format
- Test AnyKernel ZIP structure

#### Manual Testing
- Test generated ZIP files in recovery environment
- Verify kernel boot functionality
- Check device compatibility

### Documentation Standards

#### Comments
- Add comments for complex logic
- Document security validations
- Explain non-obvious parameter requirements
- Include usage examples in scripts

#### Commit Messages
- Use conventional commit format when possible
- Focus on "why" rather than "what"
- Reference relevant issues or PRs

## Development Workflow

### Making Changes
1. Test changes locally before committing
2. Validate all input parameters
3. Ensure scripts remain executable
4. Test with various kernel configurations

### CI/CD Integration
- Use GitHub Actions for automated testing
- Validate workflow syntax
- Test with different input combinations
- Monitor build success rates

### Security Considerations
- Never log sensitive information
- Validate all external inputs
- Use secure temporary file handling
- Follow principle of least privilege

## Common Patterns

### Logging Pattern
```bash
ui() { 
  if command -v ui_print >/dev/null 2>&1; then 
    ui_print "$1"
  else 
    echo "$1"
  fi
}
```

### Retry Pattern
```bash
# First attempt
if ci/build_kernel.sh "$defconfig"; then
  echo "SUCCESS=true" >> "$GITHUB_ENV"
else
  # Retry with patches
  ci/patch_polly.sh
  ci/build_kernel.sh "$defconfig"
fi
```

### Environment Setup Pattern
```bash
export CC="ccache clang"
export CXX="ccache clang++"
export LD=ld.lld
export AR=llvm-ar
```

This AGENTS.md file should be updated when new patterns emerge or coding standards evolve.