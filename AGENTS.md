# AGENTS.md

Guidelines for agentic coding agents in this Android kernel CI builder repository.

## Project Overview

Automated Android kernel build system using Proton Clang with AnyKernel ZIP packaging and NetHunter configuration support.

## Build Commands

### Kernel Build
```bash
# Configure and build kernel
make O=out <defconfig>
make -j$(nproc) O=out LLVM=1 LLVM_IAS=1
```

### CI Scripts
```bash
# Run single test suite (NetHunter configuration)
bash ci/test_nethunter_config.sh

# Build kernel with retry handling
ci/build_kernel.sh <defconfig>

# Package AnyKernel ZIP
ci/package_anykernel.sh <device_codename>

# Apply NetHunter configuration
ci/apply_nethunter_config.sh basic|full
```

## Code Style Guidelines

### Bash Script Standards

**Headers:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Input Validation:**
```bash
PARAM="${1:?param required}"
if [[ ! "$PARAM" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$PARAM" =~ \.\. ]]; then
  echo "ERROR: Invalid format: $PARAM" >&2
  exit 1
fi
```

**Function Naming:** snake_case with verb prefix (`set_kcfg_str`, `validate_git_url`). Use `local` variables. Return meaningful exit codes.

**Quoting:** Always quote `"$VAR"`. Use `printf` instead of `echo`.

### YAML (GitHub Actions)

```yaml
env:
  ARCH: arm64
  SUBARCH: arm64
steps:
  - name: Descriptive step name
    shell: bash
    run: ci/run_logged.sh ci/script.sh "${{ inputs.param }}"
```

## Security Guidelines

- Validate all user inputs with regex allowlists
- Prevent path traversal (`..`, `/*`, `*/`)
- Use arrays for command execution: `cmd=("clang" "--version"); "${cmd[@]}"`
- Never log secrets or tokens
- Check file existence before operations

## Script Organization

- All CI scripts in `ci/` directory
- Shared utilities in `ci/lib/validate.sh`
- Executable permissions (`chmod +x`)
- Naming: `verb-noun.sh` pattern
- Parameter validation at script start
- Use `ci/run_logged.sh` for consistent logging

### Shared Library (ci/lib/validate.sh)

```bash
# Source at script start
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi

# Available constants
readonly CCACHE_SIZE="5G"
readonly TELEGRAM_MAX_SIZE=$((45 * 1024 * 1024))

# Available functions
validate_workspace        # Validates GITHUB_WORKSPACE
validate_github_env       # Validates GITHUB_ENV path
validate_defconfig        # Validates defconfig format
validate_device_name      # Validates device codename
sanitize_input            # Sanitizes user input
pick_latest               # Gets most recent file
human_size               # Formats bytes to human readable
```

## Testing

**Run single test:**
```bash
bash ci/test_nethunter_config.sh
```

The test suite validates: config existence, level validation, GKI detection, backup/restore, edge cases.

**Build validation:** Check for `Image.gz-dtb` or `Image` output, validate AnyKernel ZIP structure.

## Common Patterns

**Environment Setup:**
```bash
export CC="ccache clang"
export CXX="ccache clang++"
export LD=ld.lld
export AR=llvm-ar
```

**Retry Pattern:**
```bash
if ci/build_kernel.sh "$defconfig"; then
  echo "SUCCESS=true" >> "$GITHUB_ENV"
else
  ci/patch_polly.sh
  ci/build_kernel.sh "$defconfig"
fi
```

## Development Workflow

1. Test changes locally before committing
2. Validate all input parameters
3. Ensure scripts remain executable
4. Use GitHub Actions for CI testing

