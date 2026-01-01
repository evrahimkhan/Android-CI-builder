#!/usr/bin/env bash
set -euo pipefail

CODENAME="$1"
DEFCONFIG="$2"
KERNEL_REPO="$3"
KERNEL_BRANCH="$4"
ENABLE_KSU="$5"

START=$(date +%s)

tg_msg() {
  [ -z "${TG_TOKEN:-}" ] && return
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d text="$1" >/dev/null
}

tg_file() {
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendDocument" \
    -F chat_id="$TG_CHAT_ID" \
    -F document=@"$1" >/dev/null
}

tg_msg "🚀 Kernel build started
📱 Device: $CODENAME
⚙️ Defconfig: $DEFCONFIG"

# Clone kernel
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" kernel

# Proton clang
git clone --depth=1 https://github.com/kdrag0n/proton-clang clang
export PATH="$PWD/clang/bin:$PATH"

export ARCH=arm64
export CC=clang
export LLVM=1
export LLVM_IAS=1
export HOSTCC=gcc
export HOSTCXX=g++

cd kernel
mkdir -p out

make O=out "$DEFCONFIG"

# vdso32 auto-disable
if grep -q CONFIG_COMPAT_VDSO=y out/.config; then
  scripts/config --file out/.config \
    -d CONFIG_COMPAT_VDSO -d CONFIG_VDSO32
  make O=out olddefconfig
fi

# KernelSU-Next
if [ "$ENABLE_KSU" = "true" ]; then
  curl -LSs https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh | bash -
fi

make -j$(nproc) O=out 2>&1 | tee build.log || {
  mv build.log error.log
  tg_msg "❌ Build failed for $CODENAME"
  tg_file error.log
  exit 1
}

VMLINUX="out/arch/arm64/boot/Image"

# AnyKernel3
git clone --depth=1 https://github.com/osm0sis/AnyKernel3 ak3
cp "$VMLINUX" ak3/Image
cd ak3
zip -r9 "../AnyKernel3-$CODENAME.zip" ./*
cd ..

# mkbootimg (AOSP)
git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg tools/mkbootimg
python3 tools/mkbootimg/mkbootimg.py \
  --kernel "$VMLINUX" \
  --header_version 4 \
  -o boot.img

END=$(date +%s)
TIME=$((END-START))

tg_msg "✅ Build success
📱 $CODENAME
⏱ Time: ${TIME}s"

tg_file AnyKernel3-"$CODENAME".zip
tg_file boot.img
tg_file build.log
