# AGENTS.md - Agent Coding Guidelines

This file provides guidelines for AI agents operating in this Android Kernel CI Builder repository.

## Repository Overview

This project builds Android kernels using GitHub Actions and creates AnyKernel flashable ZIP files. Supports custom kernel repos, NetHunter config, RTL8188eu WiFi driver, and multiple device defconfigs.

## Language & Tools

- **Primary Language**: Bash (shell scripts)
- **CI Platform**: GitHub Actions (YAML)
- **Testing**: Shell script-based tests

## Build/Lint/Test Commands

### Syntax Checking
```bash
bash -n ci/*.sh
bash -n ci/build_kernel.sh
```

### YAML Validation
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/kernel-ci.yml'))"
```

### Running Tests
```bash
# Run NetHunter configuration tests
bash ci/test_nethunter_config.sh

# Verify configuration
bash ci/verify_nethunter_config.sh basic
KERNEL_DIR=./kernel bash ci/verify_nethunter_config.sh full

# Build kernel
DEFCONFIG=stone_defconfig bash ci/build_kernel.sh stone_defconfig
```

## Code Style Guidelines

### Shell Scripts

- Use 2 spaces for indentation, max 120 chars per line
- Use `set -euo pipefail` at script start
- Use `#!/usr/bin/env bash` shebang

### Variable Naming
- Lowercase with underscores: `my_variable`
- Constants: `UPPER_CASE`
- Environment: `USER_NAME` (uppercase)
- Local: `local my_var`

### Functions
```bash
function my_function() {
  local arg1="$1"
  printf "[info] %s\n" "$arg1"
}
```

### Error Handling
```bash
set -euo pipefail
log_error() { printf "[ERROR] %s\n" "$*" >&2; }
log_info() { printf "[INFO] %s\n" "$*"; }

if [ -z "${1:-}" ]; then
  log_error "Argument required"
  exit 1
fi
```

### Quotes and Expansions
```bash
# Always quote variables
echo "$my_var"
cp "$source_file" "$dest_file"

# Use single quotes for literal strings
echo 'No expansion here: $VAR'

# Use $(command) instead of backticks
output=$(my_command)
```

### Conditionals
```bash
if [ "$var" = "value" ]; then
  echo "Match"
fi

if [[ "$var" =~ ^[a-z]+$ ]]; then
  echo "Valid"
fi
```

## GitHub Actions YAML

```yaml
name: Workflow Name
on:
  workflow_dispatch:
    inputs:
      input_name:
        description: 'Description'
        required: true
        default: 'value'
        type: choice
        options: ['opt1', 'opt2']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Step Name
        run: |
          set -euo pipefail
          echo "Commands"
```

### Best Practices
- Use `set -euo pipefail` in run blocks
- Capture exit codes: `EXIT_CODE=${PIPESTATUS[0]:-$?}`
- Log with timestamps: `printf "[%s] %s\n" "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "message"`

## Import/Dependency Management
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/validate.sh" ]]; then
  source "${SCRIPT_DIR}/lib/validate.sh"
fi
```

## Security Guidelines

### Path Traversal Prevention
```bash
if [[ "$input_path" =~ \.\. ]]; then
  echo "Error: Path traversal detected"
  exit 1
fi
```

### Command Injection Prevention
```bash
if [[ ! "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid characters"
  exit 1
fi
```

- Never log secrets: `echo "Token: ***"`
- Use GitHub secrets for sensitive values

## Naming Conventions

- Shell scripts: `snake_case.sh`
- CI scripts: `action_name.sh`
- Test files: `test_*.sh`
- Workflows: `kebab-case.yml`
- Jobs: `snake_case`
- Steps: `Title Case`

## Common Patterns

### Kernel Build Flow
1. `install_deps.sh` - Install system packages
2. `setup_gcc.sh` - Setup cross-compiler
3. `clone_kernel.sh` - Clone kernel source
4. `fix_kernel_config.sh` - Initial config fixes
5. `apply_nethunter_config.sh` - Apply NetHunter configs
6. `build_kernel.sh` - Compile kernel
7. `package_anykernel.sh` - Create flashable ZIP

## Notes for AI Agents

1. **Always check syntax** before committing: `bash -n script.sh`
2. **Validate YAML** when editing workflows
3. **Test changes** using workflow dispatch
4. **Check git status** before making changes
5. **Use validation functions** from `ci/lib/validate.sh`
6. **Never hardcode secrets** - use environment variables
7. **Preserve existing code style** when making modifications
