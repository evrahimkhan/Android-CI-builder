#!/usr/bin/env bash
set -euo pipefail

# Validate GITHUB_WORKSPACE to prevent command injection
if [[ ! "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  echo "ERROR: GITHUB_WORKSPACE must be an absolute path: $GITHUB_WORKSPACE" >&2
  exit 1
fi

if [[ "$GITHUB_WORKSPACE" == *".."* ]]; then
  echo "ERROR: GITHUB_WORKSPACE contains invalid characters: $GITHUB_WORKSPACE" >&2
  exit 1
fi

if [ ! -d aosp-mkbootimg/.git ]; then
  git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg  aosp-mkbootimg
fi

MKBOOTIMG="$(find aosp-mkbootimg -maxdepth 4 -type f \( -name 'mkbootimg.py' -o -name 'mkbootimg' \) | head -n1 || true)"
UNPACKBOOTIMG="$(find aosp-mkbootimg -maxdepth 4 -type f \( -name 'unpack_bootimg.py' -o -name 'unpack_bootimg' \) | head -n1 || true)"

if [ -z "$MKBOOTIMG" ]; then
  echo "ERROR: Could not find mkbootimg entrypoint in aosp-mkbootimg" >&2
  find aosp-mkbootimg -maxdepth 3 -type f | sed 's|^|  |' >&2 || true
  exit 1
fi

mkdir -p tools/mkbootimg-bin

# Sanitize paths to prevent command injection in heredoc
SANITIZED_MKBOOTIMG="${GITHUB_WORKSPACE}/${MKBOOTIMG}"
# Additional validation to ensure path is safe
if [[ ! "$SANITIZED_MKBOOTIMG" =~ ^/ ]]; then
  echo "ERROR: MKBOOTIMG path is not absolute: $SANITIZED_MKBOOTIMG" >&2
  exit 1
fi

cat > tools/mkbootimg-bin/mkbootimg <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 "${SANITIZED_MKBOOTIMG}" "\$@"
EOF
chmod +x tools/mkbootimg-bin/mkbootimg

if [ -n "$UNPACKBOOTIMG" ]; then
  SANITIZED_UNPACKBOOTIMG="${GITHUB_WORKSPACE}/${UNPACKBOOTIMG}"
  # Additional validation to ensure path is safe
  if [[ ! "$SANITIZED_UNPACKBOOTIMG" =~ ^/ ]]; then
    echo "ERROR: UNPACKBOOTIMG path is not absolute: $SANITIZED_UNPACKBOOTIMG" >&2
    exit 1
  fi

  cat > tools/mkbootimg-bin/unpack_bootimg <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 "${SANITIZED_UNPACKBOOTIMG}" "\$@"
EOF
  chmod +x tools/mkbootimg-bin/unpack_bootimg
fi

# Validate GITHUB_PATH before appending
if [[ ! "$GITHUB_PATH" =~ ^/ ]]; then
  echo "ERROR: GITHUB_PATH must be an absolute path: $GITHUB_PATH" >&2
  exit 1
fi

echo "${GITHUB_WORKSPACE}/tools/mkbootimg-bin" >> "$GITHUB_PATH"
