#!/usr/bin/env bash
# NetHunter Configuration Test Suite
# Tests for ci/apply_nethunter_config.sh

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${GITHUB_WORKSPACE:-/tmp}/.test_nethunter_$$"
TEST_KERNEL_DIR="${TEST_DIR}/kernel"
TEST_OUT_DIR="${TEST_KERNEL_DIR}/out"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Setup test environment
setup() {
  echo "Setting up test environment..."
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_OUT_DIR"
  
  # Create a mock .config file
  cat > "${TEST_OUT_DIR}/.config" << 'EOF'
# Mock kernel config for testing
CONFIG_SYSVIPC=y
CONFIG_MODULES=y
CONFIG_BT=y
EOF

  # Create mock Kconfig files
  mkdir -p "${TEST_KERNEL_DIR}/arch/arm64"
  cat > "${TEST_KERNEL_DIR}/arch/arm64/Kconfig" << 'EOF'
config SYSVIPC
	bool "System V IPC"

config MODULES
	bool "Enable loadable module support"

config BT
	bool "Bluetooth subsystem support"
EOF

  cat > "${TEST_KERNEL_DIR}/Kconfig" << 'EOF'
source "arch/arm64/Kconfig"

config USB_ACM
	bool "USB Modem (CDC ACM) support"

config USB_GADGET
	bool "USB Gadget Support"
EOF
}

# Cleanup test environment
teardown() {
  rm -rf "$TEST_DIR"
}

# Test helper functions
assert_true() {
  local msg="$1"
  shift
  if "$@"; then
    echo "✓ PASS: $msg"
    ((TESTS_PASSED++)) || true
  else
    echo "✗ FAIL: $msg"
    ((TESTS_FAILED++)) || true
  fi
}

assert_false() {
  local msg="$1"
  shift
  if ! "$@"; then
    echo "✓ PASS: $msg"
    ((TESTS_PASSED++)) || true
  else
    echo "✗ FAIL: $msg"
    ((TESTS_FAILED++)) || true
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  
  if [ "$expected" = "$actual" ]; then
    echo "✓ PASS: $msg"
    ((TESTS_PASSED++)) || true
  else
    echo "✗ FAIL: $msg"
    echo "  Expected: '$expected'"
    echo "  Actual:   '$actual'"
    ((TESTS_FAILED++)) || true
  fi
}

# Source the script under test (with mocked functions)
source_nethunter_script() {
  # Create a modified version for testing
  local script_path="${SCRIPT_DIR}/../ci/apply_nethunter_config.sh"
  
  # Validate script path exists
  if [ ! -f "$script_path" ]; then
    echo "ERROR: Script not found at $script_path" >&2
    return 1
  fi
  
  # Override KERNEL_DIR for testing
  export KERNEL_DIR="$TEST_KERNEL_DIR"
  
  # Source with test mocks - fail on error
  if ! source "$script_path" 2>/dev/null; then
    echo "ERROR: Failed to source $script_path" >&2
    return 1
  fi
}

# Test 1: Config existence check
test_check_config_exists() {
  echo ""
  echo "=== Test: check_config_exists ==="
  
  # Test existing config
  if check_config_exists "SYSVIPC"; then
    echo "✓ PASS: check_config_exists finds existing config"
    ((TESTS_PASSED++)) || true
  else
    echo "✗ FAIL: check_config_exists should find SYSVIPC"
    ((TESTS_FAILED++)) || true
  fi
  
  # Test non-existing config
  if ! check_config_exists "NONEXISTENT_CONFIG_XYZ"; then
    echo "✓ PASS: check_config_exists returns false for non-existing config"
    ((TESTS_PASSED++)) || true
  else
    echo "✗ FAIL: check_config_exists should not find non-existent config"
    ((TESTS_FAILED++)) || true
  fi
}

# Test 2: Config level validation
test_validate_config_level() {
  echo ""
  echo "=== Test: validate_config_level ==="
  
  # Valid levels
  assert_true "validate_config_level accepts 'basic'" validate_config_level "basic"
  assert_true "validate_config_level accepts 'full'" validate_config_level "full"
  assert_true "validate_config_level accepts empty string" validate_config_level ""
  
  # Invalid level
  assert_false "validate_config_level rejects invalid value" validate_config_level "invalid"
}

# Test 3: Safe config setters (mocked)
test_safe_set_kcfg() {
  echo ""
  echo "=== Test: safe_set_kcfg functions ==="
  
  # Mock set_kcfg_bool for testing
  set_kcfg_bool() {
    echo "MOCK: set_kcfg_bool $1=$2" >> "${TEST_OUT_DIR}/config_changes.log"
  }
  
  # Test safe_set_kcfg_bool with existing config
  safe_set_kcfg_bool "SYSVIPC" "y" 2>/dev/null
  if [ -f "${TEST_OUT_DIR}/config_changes.log" ]; then
    echo "✓ PASS: safe_set_kcfg_bool calls setter for existing config"
    ((TESTS_PASSED++))
    rm -f "${TEST_OUT_DIR}/config_changes.log"
  else
    echo "✗ FAIL: safe_set_kcfg_bool should have called setter"
    ((TESTS_FAILED++))
  fi
  
  # Test safe_set_kcfg_bool with non-existing config (should not call setter)
  safe_set_kcfg_bool "NONEXISTENT" "y" 2>/dev/null
  if [ ! -f "${TEST_OUT_DIR}/config_changes.log" ]; then
    echo "✓ PASS: safe_set_kcfg_bool skips non-existing config"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: safe_set_kcfg_bool should skip non-existing config"
    ((TESTS_FAILED++))
  fi
}

# Test 4: GKI detection
test_check_gki_status() {
  echo ""
  echo "=== Test: check_gki_status ==="
  
  # Test without GKI
  if ! check_gki_status 2>/dev/null; then
    echo "✓ PASS: check_gki_status returns false without CONFIG_GKI"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: check_gki_status should return false without GKI"
    ((TESTS_FAILED++))
  fi
  
  # Test with GKI
  echo "CONFIG_GKI=y" >> "${TEST_OUT_DIR}/.config"
  if check_gki_status 2>/dev/null; then
    echo "✓ PASS: check_gki_status returns true with CONFIG_GKI"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: check_gki_status should return true with GKI"
    ((TESTS_FAILED++))
  fi
  
  # Reset
  sed -i '/CONFIG_GKI=y/d' "${TEST_OUT_DIR}/.config"
}

# Test 5: Backup and restore
test_backup_restore() {
  echo ""
  echo "=== Test: backup/restore functionality ==="
  
  # Create original config
  echo "ORIGINAL_CONFIG=y" > "${TEST_OUT_DIR}/.config"
  
  # Test backup
  backup_kernel_config 2>/dev/null
  if [ -f "${TEST_OUT_DIR}/.config.backup.nethunter" ]; then
    echo "✓ PASS: backup_kernel_config creates backup"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: backup_kernel_config should create backup file"
    ((TESTS_FAILED++))
  fi
  
  # Modify config
  echo "MODIFIED_CONFIG=y" > "${TEST_OUT_DIR}/.config"
  
  # Test restore
  restore_kernel_config 2>/dev/null
  if grep -q "ORIGINAL_CONFIG=y" "${TEST_OUT_DIR}/.config"; then
    echo "✓ PASS: restore_kernel_config restores original"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: restore_kernel_config should restore original config"
    ((TESTS_FAILED++))
  fi
  
  # Test cleanup
  cleanup_kernel_config_backup 2>/dev/null
  if [ ! -f "${TEST_OUT_DIR}/.config.backup.nethunter" ]; then
    echo "✓ PASS: cleanup_kernel_config_backup removes backup"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: cleanup_kernel_config_backup should remove backup"
    ((TESTS_FAILED++))
  fi
}

# Test 5b: Invalid config level fallback
test_invalid_config_fallback() {
  echo ""
  echo "=== Test: Invalid Config Level Fallback ==="
  
  # Setup
  export NETHUNTER_ENABLED="true"
  export NETHUNTER_CONFIG_LEVEL="invalid_level"
  
  # Mock the apply functions
  apply_nethunter_universal_core() {
    return 0
  }
  
  apply_nethunter_android_binder() {
    return 0
  }
  
  # Run main function and capture output
  local output
  output=$(apply_nethunter_config 2>&1)
  
  # Check that it falls back to basic and completes successfully
  if echo "$output" | grep -q "Falling back to 'basic' level due to invalid input"; then
    echo "✓ PASS: Falls back to 'basic' on invalid config level"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: Should display fallback message for invalid config level"
    ((TESTS_FAILED++))
  fi
  
  # Check that it completes without error
  if apply_nethunter_config > /dev/null 2>&1; then
    echo "✓ PASS: Completes successfully with fallback"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: Should complete even with invalid config level"
    ((TESTS_FAILED++))
  fi
}

# Test 6: Integration test - basic workflow
test_integration_basic() {
  echo ""
  echo "=== Test: Integration - Basic Workflow ==="
  
  # Setup
  export NETHUNTER_ENABLED="true"
  export NETHUNTER_CONFIG_LEVEL="basic"
  
  # Mock the apply functions to avoid actual kernel operations
  apply_nethunter_universal_core() {
    echo "MOCK: apply_nethunter_universal_core called"
    return 0
  }
  
  apply_nethunter_android_binder() {
    echo "MOCK: apply_nethunter_android_binder called"
    return 0
  }
  
  # Run main function (it should complete without errors)
  if apply_nethunter_config > "${TEST_OUT_DIR}/test_output.log" 2>&1; then
    echo "✓ PASS: apply_nethunter_config completes successfully"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: apply_nethunter_config should complete without errors"
    ((TESTS_FAILED++))
  fi
  
  # Check that backup was cleaned up
  if [ ! -f "${TEST_OUT_DIR}/.config.backup.nethunter" ]; then
    echo "✓ PASS: Integration test cleans up backup"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: Integration test should clean up backup"
    ((TESTS_FAILED++))
  fi
}

# Test 7: Edge cases
test_edge_cases() {
  echo ""
  echo "=== Test: Edge Cases ==="
  
  # Test with special characters in config names (should be rejected)
  if ! check_config_exists "CONFIG_WITH;SHELL_INJECTION" 2>/dev/null; then
    echo "✓ PASS: Special characters in config names handled safely"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: Special characters should be rejected"
    ((TESTS_FAILED++))
  fi
  
  # Test with empty kernel directory
  KERNEL_DIR="/nonexistent/path"
  if ! check_config_exists "SYSVIPC" 2>/dev/null; then
    echo "✓ PASS: Empty kernel directory handled gracefully"
    ((TESTS_PASSED++))
  else
    echo "✗ FAIL: Should handle missing kernel directory"
    ((TESTS_FAILED++))
  fi
  KERNEL_DIR="$TEST_KERNEL_DIR"
}

# Main test runner
main() {
  echo "=============================================="
  echo "NetHunter Configuration Test Suite"
  echo "=============================================="
  echo ""
  
  # Setup
  setup
  
  # Ensure cleanup runs on exit
  trap teardown EXIT
  
  # Source the script
  if ! source_nethunter_script; then
    echo ""
    echo "=============================================="
    echo "Test Results"
    echo "=============================================="
    echo "Tests Passed: 0"
    echo "Tests Failed: 1"
    echo ""
    echo "❌ Test setup failed - could not source NetHunter config script!"
    exit 1
  fi
  
  # Run tests
  test_check_config_exists
  test_validate_config_level
  test_safe_set_kcfg
  test_check_gki_status
  test_backup_restore
  test_integration_basic
  test_invalid_config_fallback
  test_edge_cases
  
  # Cleanup
  teardown
  
  # Results
  echo ""
  echo "=============================================="
  echo "Test Results"
  echo "=============================================="
  echo "Tests Passed: $TESTS_PASSED"
  echo "Tests Failed: $TESTS_FAILED"
  echo ""
  
  if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
  else
    echo "❌ Some tests failed!"
    exit 1
  fi
}

# Run tests
main
