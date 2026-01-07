#!/usr/bin/env bash
set -euo pipefail

if [ ! -d aosp-mkbootimg/.git ]; then
  git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg aosp-mkbootimg
fi

MKBOOTIMG="$(find aosp-mkbootimg -maxdepth 4 -type f \( -name 'mkbootimg.py' -o -name 'mkbootimg' \) | head -n1 || true)"
UNPACKBOOTIMG="$(find aosp-mkbootimg -maxdepth 4 -type f \( -name 'unpack_bootimg.py' -o -name 'unpack_bootimg' \) | head -n1 || true)"

if [ -z "$MKBOOTIMG" ]; then
  echo "ERROR: Could not find mkbootimg entrypoint in aosp-mkbootimg" >&2
  find aosp-mkbootimg -maxdepth 3 -type f | sed 's|^|  |' >&2 || true
  exit 1
fi

mkdir -p tools/mkbootimg-bin

cat > tools/mkbootimg-bin/mkbootimg <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 "${GITHUB_WORKSPACE}/${MKBOOTIMG}" "\$@"
EOF
chmod +x tools/mkbootimg-bin/mkbootimg

if [ -n "$UNPACKBOOTIMG" ]; then
  cat > tools/mkbootimg-bin/unpack_bootimg <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 "${GITHUB_WORKSPACE}/${UNPACKBOOTIMG}" "\$@"
EOF
  chmod +x tools/mkbootimg-bin/unpack_bootimg
fi

echo "${GITHUB_WORKSPACE}/tools/mkbootimg-bin" >> "$GITHUB_PATH"
