#!/usr/bin/env bash
set -euo pipefail

# Clone AOSP mkbootimg if not present
if [ ! -d aosp-mkbootimg/.git ]; then
  git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg aosp-mkbootimg
fi

# Find probable entrypoints (handle different filenames)
MKBOOTIMG_PY="$(find aosp-mkbootimg -maxdepth 2 -type f \( -name 'mkbootimg.py' -o -name 'mkbootimg' \) | head -n1 || true)"
UNPACKBOOTIMG_PY="$(find aosp-mkbootimg -maxdepth 2 -type f \( -name 'unpack_bootimg.py' -o -name 'unpack_bootimg.py' -o -name 'unpack_bootimg' \) | head -n1 || true)"

mkdir -p tools/mkbootimg-bin

# Wrapper: mkbootimg
cat > tools/mkbootimg-bin/mkbootimg <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 "${GITHUB_WORKSPACE}/$MKBOOTIMG_PY" "\$@"
EOF
chmod +x tools/mkbootimg-bin/mkbootimg

# Wrapper: unpack_bootimg (optional but useful)
if [ -n "$UNPACKBOOTIMG_PY" ]; then
  cat > tools/mkbootimg-bin/unpack_bootimg <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 "${GITHUB_WORKSPACE}/$UNPACKBOOTIMG_PY" "\$@"
EOF
  chmod +x tools/mkbootimg-bin/unpack_bootimg
fi

# Put wrappers on PATH for subsequent steps
echo "${GITHUB_WORKSPACE}/tools/mkbootimg-bin" >> "$GITHUB_PATH"

# Quick smoke info (won't fail build if help output differs)
mkbootimg --help >/dev/null 2>&1 || true
unpack_bootimg --help >/dev/null 2>&1 || true
