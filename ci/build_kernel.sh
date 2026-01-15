#!/usr/bin/env bash
set -euo pipefail

DEFCONFIG="${1:?defconfig required}"

# Validate DEFCONFIG parameter to prevent path traversal and command injection
if [[ ! "$DEFCONFIG" =~ ^[a-zA-Z0-9/_.-]+$ ]] || [[ "$DEFCONFIG" =~ \.\. ]] || [[ "$DEFCONFIG" =~ /\* ]] || [[ "$DEFCONFIG" =~ \*/ ]]; then
  echo "ERROR: Invalid defconfig format: $DEFCONFIG" >&2
  exit 1
fi

# Validate GITHUB_WORKSPACE and GITHUB_ENV to prevent path traversal
if [[ ! "$GITHUB_WORKSPACE" =~ ^/ ]]; then
  echo "ERROR: GITHUB_WORKSPACE must be an absolute path: $GITHUB_WORKSPACE" >&2
  exit 1
fi

if [[ "$GITHUB_WORKSPACE" == *".."* ]]; then
  echo "ERROR: GITHUB_WORKSPACE contains invalid characters: $GITHUB_WORKSPACE" >&2
  exit 1
fi

if [[ ! "$GITHUB_ENV" =~ ^/ ]]; then
  echo "ERROR: GITHUB_ENV must be an absolute path: $GITHUB_ENV" >&2
  exit 1
fi

if [[ "$GITHUB_ENV" == *".."* ]]; then
  echo "ERROR: GITHUB_ENV contains invalid characters: $GITHUB_ENV" >&2
  exit 1
fi

export PATH="${GITHUB_WORKSPACE}/clang/bin:${PATH}"

echo "SUCCESS=0" >> "$GITHUB_ENV"

ccache -M 5G || true
ccache -z || true

export CC="ccache clang"
export CXX="ccache clang++"
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip

# Prevent interactive configuration prompts
export KCONFIG_NOTIMESTAMP=1
export KERNELRELEASE=""
export KBUILD_BUILD_TIMESTAMP=""
export KBUILD_BUILD_USER="android"
export KBUILD_BUILD_HOST="android-build"

cd kernel
mkdir -p out

run_oldconfig() {
  set +e
  set +o pipefail
  # Use yes "" to auto-answer prompts with defaults, but also redirect stdin to avoid hanging
  yes "" | make O=out oldconfig 2>/dev/null || true
  local rc=$?
  set -o pipefail
  set -e
  return "$rc"
}

cfg_tool() {
  if [ -f scripts/config ]; then
    chmod +x scripts/config || true
    echo "scripts/config"
  else
    echo ""
  fi
}

set_kcfg_str() {
  local key="$1"
  local val="$2"
  # Sanitize inputs to prevent command injection
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: Invalid key format: $key" >&2
    return 1
  fi

  # Escape special characters in value to prevent injection
  local sanitized_val
  sanitized_val=$(printf '%s\n' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')

  local tool; tool="$(cfg_tool)"
  if [ -n "$tool" ]; then
    "$tool" --file out/.config --set-str "$key" "$sanitized_val" >/dev/null 2>&1 || true
  else
    if grep -q "^CONFIG_${key}=" out/.config 2>/dev/null; then
      sed -i "s|^CONFIG_${key}=.*|CONFIG_${key}=\"${sanitized_val}\"|" out/.config || true
    else
      printf 'CONFIG_%s="%s"\n' "$key" "$sanitized_val" >> out/.config
    fi
  fi
}

set_kcfg_bool() {
  local key="$1"
  local yn="$2"
  # Sanitize inputs to prevent command injection
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: Invalid key format: $key" >&2
    return 1
  fi

  if [[ ! "$yn" =~ ^[yn]$ ]]; then
    echo "ERROR: Invalid yn value: $yn, must be 'y' or 'n'" >&2
    return 1
  fi

  local tool; tool="$(cfg_tool)"
  if [ -n "$tool" ]; then
    if [ "$yn" = "y" ]; then "$tool" --file out/.config -e "$key" >/dev/null 2>&1 || true
    else "$tool" --file out/.config -d "$key" >/dev/null 2>&1 || true
    fi
  else
    if [ "$yn" = "y" ]; then
      sed -i "s|^# CONFIG_${key} is not set|CONFIG_${key}=y|" out/.config 2>/dev/null || true
      grep -q "^CONFIG_${key}=y" out/.config 2>/dev/null || echo "CONFIG_${key}=y" >> out/.config
    else
      sed -i "/^CONFIG_${key}=y$/d;/^CONFIG_${key}=m$/d" out/.config 2>/dev/null || true
      grep -q "^# CONFIG_${key} is not set" out/.config 2>/dev/null || echo "# CONFIG_${key} is not set" >> out/.config
    fi
  fi
}

apply_custom_kconfig_branding() {
  if [ "${CUSTOM_CONFIG_ENABLED:-false}" != "true" ]; then
    return 0
  fi

  local localversion="${CFG_LOCALVERSION:--CI}"
  local hostname="${CFG_DEFAULT_HOSTNAME:-CI Builder}"
  local uname_override="${CFG_UNAME_OVERRIDE_STRING:-}"
  local cc_text_override="${CFG_CC_VERSION_TEXT:-}"

  local clang_ver
  clang_ver="$(clang --version | head -n1 | tr -d '\n' || true)"

  local cc_text="$cc_text_override"
  [ -z "$cc_text" ] && cc_text="$clang_ver"

  set_kcfg_str LOCALVERSION "$localversion"
  set_kcfg_str DEFAULT_HOSTNAME "$hostname"
  set_kcfg_str CC_VERSION_TEXT "$cc_text"
  set_kcfg_str UNAME_OVERRIDE_STRING "$uname_override"

  if [ -n "$uname_override" ]; then
    set_kcfg_bool UNAME_OVERRIDE y
  else
    set_kcfg_bool UNAME_OVERRIDE n
  fi

  set_kcfg_bool LOCALVERSION_AUTO n
  if ! make O=out olddefconfig; then
    # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
    if ! make O=out silentoldconfig; then
      # Fallback to oldconfig with yes "" if both fail
      run_oldconfig || true
    fi
  fi
}

make O=out "$DEFCONFIG"
# Use olddefconfig to automatically accept default values for new config options
if ! make O=out olddefconfig; then
  # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
  if ! make O=out silentoldconfig; then
    # Fallback to oldconfig with yes "" if both fail
    run_oldconfig || { echo "ERROR: oldconfig failed" > error.log; exit 0; }
  fi
fi

# Apply custom kconfig branding if enabled
apply_custom_kconfig_branding

# Run olddefconfig to ensure all new configurations are properly set without interactive prompts
if ! make O=out olddefconfig; then
  # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
  if ! make O=out silentoldconfig; then
    # Fallback to oldconfig with yes "" if both fail
    run_oldconfig || { echo "ERROR: oldconfig failed" > error.log; exit 0; }
  fi
fi

# Apply NetHunter configurations if enabled
if [ "${ENABLE_NETHUNTER_CONFIG:-false}" = "true" ]; then
  echo "Applying NetHunter configurations..."

  # Function to safely add or update a kernel config option
  add_kconfig_option() {
    local option="$1"
    local value="$2"

    # Validate option name to prevent injection
    if [[ ! "$option" =~ ^CONFIG_[A-Z0-9_]+$ ]]; then
      echo "ERROR: Invalid option name format: $option" >&2
      return 1
    fi

    # Validate value to prevent injection
    if [[ ! "$value" =~ ^[ymn]$ ]] && [[ ! "$value" =~ ^\".*\"$ ]] && [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      echo "ERROR: Invalid value format: $value" >&2
      return 1
    fi

    # Check if the option already exists in the config
    if grep -q "^# ${option} is not set\\|^${option}=" out/.config; then
      # Option exists, update it
      sed -i "s/^# ${option} is not set$/${option}=${value}/" out/.config || {
        echo "ERROR: Failed to update ${option} in kernel config" >&2
        return 1
      }
      sed -i "s/^${option}=.*/${option}=${value}/" out/.config || {
        echo "ERROR: Failed to update ${option} in kernel config" >&2
        return 1
      }
    else
      # Option doesn't exist, append it
      echo "${option}=${value}" >> out/.config || {
        echo "ERROR: Failed to append ${option} to kernel config" >&2
        return 1
      }
    fi
  }

  # NetHunter-specific configurations
  add_kconfig_option "CONFIG_USB_NET_DRIVERS" "y"
  add_kconfig_option "CONFIG_USB_USBNET" "y"
  add_kconfig_option "CONFIG_USB_NET_AX8817X" "y"
  add_kconfig_option "CONFIG_USB_NET_CDCETHER" "y"
  add_kconfig_option "CONFIG_USB_NET_CDC_SUBSETTER" "y"
  add_kconfig_option "CONFIG_USB_NET_DM9601" "y"
  add_kconfig_option "CONFIG_USB_NET_SMSC75XX" "y"
  add_kconfig_option "CONFIG_USB_NET_SMSC95XX" "y"
  add_kconfig_option "CONFIG_USB_NET_GL620A" "y"
  add_kconfig_option "CONFIG_USB_NET_MCS7830" "y"
  add_kconfig_option "CONFIG_USB_NET_RNDIS_HOST" "y"
  add_kconfig_option "CONFIG_USB_NET_CDC_NCM" "y"
  add_kconfig_option "CONFIG_USB_NET_HUAWEI_CDC_NCM" "y"
  add_kconfig_option "CONFIG_USB_NET_CDC_MBIM" "y"

  # Wireless configurations for penetration testing
  add_kconfig_option "CONFIG_CFG80211" "y"  # Built-in instead of module to ensure symbols are available
  add_kconfig_option "CONFIG_MAC80211" "y"  # Built-in instead of module to ensure symbols are available
  add_kconfig_option "CONFIG_MAC80211_MESH" "y"
  add_kconfig_option "CONFIG_WIRELESS_EXT" "y"
  add_kconfig_option "CONFIG_WEXT_CORE" "y"
  add_kconfig_option "CONFIG_WEXT_PROC" "y"
  add_kconfig_option "CONFIG_WEXT_SPY" "y"
  add_kconfig_option "CONFIG_WEXT_PRIV" "y"

  # Enable wireless extensions
  add_kconfig_option "CONFIG_WIRELESS" "y"
  add_kconfig_option "CONFIG_CFG80211_INTERNAL_REGDB" "y"

  # Enable cfg80211 features needed by various wireless drivers
  add_kconfig_option "CONFIG_CFG80211_WEXT" "y"
  add_kconfig_option "CONFIG_CFG80211_CRDA_SUPPORT" "y"
  add_kconfig_option "CONFIG_CFG80211_DEFAULT_PS" "y"
  add_kconfig_option "CONFIG_CFG80211_DEBUGFS" "y"
  add_kconfig_option "CONFIG_CFG80211_DEVELOPMENT" "y"
  add_kconfig_option "CONFIG_CFG80211_CERTIFICATION_ONUS" "y"
  add_kconfig_option "CONFIG_BT_HCIUART_LL" "y"
  add_kconfig_option "CONFIG_BT_HCIUART_3WIRE" "y"
  add_kconfig_option "CONFIG_BT_HCIUART_H4" "y"

  # NFC support
  add_kconfig_option "CONFIG_NFC" "m"
  add_kconfig_option "CONFIG_NFC_NCI" "m"
  add_kconfig_option "CONFIG_NFC_DIGITAL" "m"
  add_kconfig_option "CONFIG_NFC_LLCP" "m"
  # NOTE: SELINUX_DEVELOP increases security risk - only enable if needed
  # add_kconfig_option "CONFIG_SECURITY_SELINUX_DEVELOP" "y"

  # Enable namespaces for containerization
  add_kconfig_option "CONFIG_NAMESPACES" "y"
  add_kconfig_option "CONFIG_UTS_NS" "y"
  add_kconfig_option "CONFIG_IPC_NS" "y"
  add_kconfig_option "CONFIG_USER_NS" "y"
  add_kconfig_option "CONFIG_PID_NS" "y"
  add_kconfig_option "CONFIG_NET_NS" "y"

  # Enable cgroups
  add_kconfig_option "CONFIG_CGROUPS" "y"
  add_kconfig_option "CONFIG_CGROUP_FREEZER" "y"
  add_kconfig_option "CONFIG_CGROUP_PIDS" "y"
  add_kconfig_option "CONFIG_CGROUP_DEVICE" "y"
  add_kconfig_option "CONFIG_CPUSETS" "y"
  add_kconfig_option "CONFIG_CGROUP_CPUACCT" "y"
  add_kconfig_option "CONFIG_MEMCG" "y"

  # Enable usermode helper
  add_kconfig_option "CONFIG_SYSCTL_SYSCALL" "y"

  # NOTE: Module signing disabled for custom module loading capability
  # This reduces security - consider if this is acceptable for your use case
  add_kconfig_option "CONFIG_MODULE_SIG" "n"
  add_kconfig_option "CONFIG_MODULE_SIG_FORCE" "n"


  # Enable wireless regulatory database
  # (already configured above)

  # Enable rfkill for wireless kill switch support
  add_kconfig_option "CONFIG_RFKILL" "m"
  add_kconfig_option "CONFIG_RFKILL_INPUT" "y"
  add_kconfig_option "CONFIG_RFKILL_GPIO" "m"

  # Enable LED triggers for wireless
  add_kconfig_option "CONFIG_LEDS_TRIGGER_PHY" "y"


  # Enable USB serial support
  add_kconfig_option "CONFIG_USB_SERIAL" "y"
  add_kconfig_option "CONFIG_USB_SERIAL_GENERIC" "y"
  add_kconfig_option "CONFIG_USB_SERIAL_FTDI_SIO" "y"
  add_kconfig_option "CONFIG_USB_SERIAL_PL2303" "y"
  add_kconfig_option "CONFIG_USB_SERIAL_CH341" "y"

  # Enable GPIO support for hardware interfacing
  add_kconfig_option "CONFIG_GPIOLIB" "y"
  add_kconfig_option "CONFIG_OF_GPIO" "y"
  add_kconfig_option "CONFIG_DEBUG_GPIO" "y"

  # Enable SPI support for hardware interfacing
  add_kconfig_option "CONFIG_SPI" "y"
  add_kconfig_option "CONFIG_SPI_MASTER" "y"

  # Enable I2C support for hardware interfacing
  add_kconfig_option "CONFIG_I2C" "y"
  add_kconfig_option "CONFIG_I2C_CHARDEV" "y"

  # Enable hardware random number generator
  add_kconfig_option "CONFIG_HW_RANDOM" "y"

  # Enable crypto algorithms needed for security tools
  add_kconfig_option "CONFIG_CRYPTO_AES" "y"
  add_kconfig_option "CONFIG_CRYPTO_ARC4" "y"
  add_kconfig_option "CONFIG_CRYPTO_DES" "y"
  add_kconfig_option "CONFIG_CRYPTO_TWOFISH" "y"
  add_kconfig_option "CONFIG_CRYPTO_SERPENT" "y"
  add_kconfig_option "CONFIG_CRYPTO_CAMELLIA" "y"
  add_kconfig_option "CONFIG_CRYPTO_BLOWFISH" "y"
  add_kconfig_option "CONFIG_CRYPTO_CAST5" "y"
  add_kconfig_option "CONFIG_CRYPTO_CAST6" "y"
  add_kconfig_option "CONFIG_CRYPTO_ANUBIS" "y"
  add_kconfig_option "CONFIG_CRYPTO_TEA" "y"
  add_kconfig_option "CONFIG_CRYPTO_MICHAEL_MIC" "y"
  add_kconfig_option "CONFIG_CRYPTO_CRC32C" "y"
  add_kconfig_option "CONFIG_CRYPTO_CRC32" "y"
  add_kconfig_option "CONFIG_CRYPTO_DEFLATE" "y"
  add_kconfig_option "CONFIG_CRYPTO_ZLIB" "y"
  add_kconfig_option "CONFIG_CRYPTO_LZO" "y"
  add_kconfig_option "CONFIG_CRYPTO_LZ4" "y"
  add_kconfig_option "CONFIG_CRYPTO_ADIANTUM" "y"
  add_kconfig_option "CONFIG_CRYPTO_XTS" "y"
  add_kconfig_option "CONFIG_CRYPTO_KEYWRAP" "y"
  add_kconfig_option "CONFIG_CRYPTO_CMAC" "y"
  add_kconfig_option "CONFIG_CRYPTO_GCM" "y"
  add_kconfig_option "CONFIG_CRYPTO_CHACHA20POLY1305" "y"
  add_kconfig_option "CONFIG_CRYPTO_ECHAINIV" "y"
  add_kconfig_option "CONFIG_CRYPTO_ABLK_HELPER" "y"
  add_kconfig_option "CONFIG_CRYPTO_GF128MUL" "y"
  add_kconfig_option "CONFIG_CRYPTO_SEQIV" "y"
  add_kconfig_option "CONFIG_CRYPTO_LRW" "y"
  add_kconfig_option "CONFIG_CRYPTO_PCBC" "y"
  add_kconfig_option "CONFIG_CRYPTO_AUTHENC" "y"
  add_kconfig_option "CONFIG_CRYPTO_TEST" "m"

  # Enable network packet filtering (iptables)
  add_kconfig_option "CONFIG_NETFILTER" "y"
  add_kconfig_option "CONFIG_NETFILTER_ADVANCED" "y"

  # Enable iptables match modules
  add_kconfig_option "CONFIG_NETFILTER_XTABLES" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_COMMENT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNTRACK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MULTIPORT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_PKTTYPE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_BPF" "m"

  # Enable iptables target modules
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CLASSIFY" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CONNMARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CONNSECMARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_MARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NFLOG" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NFQUEUE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_SECMARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TCPMSS" "m"

  # Enable netfilter connection tracking
  add_kconfig_option "CONFIG_NF_CONNTRACK" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_IPV4" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_IPV6" "m"
  add_kconfig_option "CONFIG_NF_CT_PROTO_DCCP" "m"
  add_kconfig_option "CONFIG_NF_CT_PROTO_SCTP" "m"
  add_kconfig_option "CONFIG_NF_CT_PROTO_UDPLITE" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_EVENTS" "y"
  add_kconfig_option "CONFIG_NF_CONNTRACK_TIMEOUT" "y"
  add_kconfig_option "CONFIG_NF_CONNTRACK_TIMESTAMP" "y"

  # Enable iptables raw table
  add_kconfig_option "CONFIG_IP_NF_RAW" "m"

  # Enable iptables security table
  add_kconfig_option "CONFIG_IP_NF_SECURITY" "m"

  # Enable bridge support
  add_kconfig_option "CONFIG_BRIDGE" "m"
  add_kconfig_option "CONFIG_BRIDGE_IGMP_SNOOPING" "y"

  # Enable MACVLAN and IPVLAN
  add_kconfig_option "CONFIG_MACVLAN" "m"
  add_kconfig_option "CONFIG_IPVLAN" "m"

  # Enable Virtual Sockets (for Android inter-process communication)
  add_kconfig_option "CONFIG_VSOCKETS" "m"
  add_kconfig_option "CONFIG_VSOCKETS_DIAG" "m"
  add_kconfig_option "CONFIG_VSOCKETS_LOOPBACK" "y"

  # Enable TUN/TAP support (for VPN and tunneling)
  add_kconfig_option "CONFIG_TUN" "m"

  # Enable CAN bus support (for automotive/networking tools)
  add_kconfig_option "CONFIG_CAN" "m"
  add_kconfig_option "CONFIG_CAN_RAW" "m"
  add_kconfig_option "CONFIG_CAN_BCM" "m"
  add_kconfig_option "CONFIG_CAN_GW" "m"
  add_kconfig_option "CONFIG_CAN_J1939" "m"
  add_kconfig_option "CONFIG_CAN_ISOTP" "m"

  # Enable NFC subsystem
  add_kconfig_option "CONFIG_NFC" "m"
  add_kconfig_option "CONFIG_NFC_DIGITAL" "m"
  add_kconfig_option "CONFIG_NFC_NCI" "m"
  add_kconfig_option "CONFIG_NFC_HCI" "m"
  add_kconfig_option "CONFIG_NFC_SHDLC" "y"

  # Enable Infrared support
  add_kconfig_option "CONFIG_IR_CORE" "m"
  add_kconfig_option "CONFIG_IR_TUNER" "m"

  # Enable Sound support for audio-based tools
  add_kconfig_option "CONFIG_SOUND" "m"
  add_kconfig_option "CONFIG_SND" "m"
  add_kconfig_option "CONFIG_SND_HRTIMER" "m"
  add_kconfig_option "CONFIG_SND_SEQ_DUMMY" "m"
  add_kconfig_option "CONFIG_SND_DUMMY" "m"
  add_kconfig_option "CONFIG_SND_VIRMIDI" "m"
  add_kconfig_option "CONFIG_SND_MTPAV" "m"
  add_kconfig_option "CONFIG_SND_SERIAL_U16550" "m"
  add_kconfig_option "CONFIG_SND_MPU401_UART" "m"

  # Enable video input for camera-based tools
  add_kconfig_option "CONFIG_VIDEO_DEV" "m"
  add_kconfig_option "CONFIG_VIDEO_V4L2" "m"
  add_kconfig_option "CONFIG_VIDEO_CAPTURE_DRIVERS" "y"

  # Enable framebuffer console for debugging
  add_kconfig_option "CONFIG_FRAMEBUFFER_CONSOLE" "y"
  add_kconfig_option "CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY" "y"
  add_kconfig_option "CONFIG_FRAMEBUFFER_CONSOLE_ROTATION" "y"

  # Enable early printk for debugging
  add_kconfig_option "CONFIG_EARLY_PRINTK" "y"

  # Enable crash dump support
  add_kconfig_option "CONFIG_PROC_VMCORE" "y"
  add_kconfig_option "CONFIG_PROC_PAGE_MONITOR" "y"

  # Enable kprobes for dynamic instrumentation
  add_kconfig_option "CONFIG_KPROBES" "y"
  add_kconfig_option "CONFIG_KPROBE_EVENTS" "y"

  # Enable uprobes for userspace dynamic instrumentation
  add_kconfig_option "CONFIG_UPROBES" "y"
  add_kconfig_option "CONFIG_UPROBE_EVENTS" "y"

  # Enable trace events
  add_kconfig_option "CONFIG_TRACEPOINTS" "y"

  # Enable ftrace for function tracing
  add_kconfig_option "CONFIG_FUNCTION_TRACER" "y"
  add_kconfig_option "CONFIG_IRQSOFF_TRACER" "y"
  add_kconfig_option "CONFIG_PREEMPT_TRACER" "y"
  add_kconfig_option "CONFIG_SCHED_TRACER" "y"
  add_kconfig_option "CONFIG_ENABLE_DEFAULT_TRACERS" "y"
  add_kconfig_option "CONFIG_STACK_TRACER" "y"
  add_kconfig_option "CONFIG_BLK_TRACER" "y"
  add_kconfig_option "CONFIG_PROVEVENT" "y"
  add_kconfig_option "CONFIG_EVENT_TRACING" "y"
  add_kconfig_option "CONFIG_CONTEXT_SWITCH_TRACER" "y"
  add_kconfig_option "CONFIG_CMDLINE_FROM_BOOTLOADER" "y"

  # Enable kernel hacking options for development
  add_kconfig_option "CONFIG_MAGIC_SYSRQ" "y"
  add_kconfig_option "CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE" "0x01b6"

  # Universal NetHunter configurations for various kernel architectures
  add_kconfig_option "CONFIG_EMBEDDED" "y"
  add_kconfig_option "CONFIG_EXPERT" "y"
  add_kconfig_option "CONFIG_SYSVIPC" "y"
  add_kconfig_option "CONFIG_POSIX_MQUEUE" "y"
  add_kconfig_option "CONFIG_CHECKPOINT_RESTORE" "y"
  add_kconfig_option "CONFIG_BPF_SYSCALL" "y"
  add_kconfig_option "CONFIG_BPF_JIT" "y"
  add_kconfig_option "CONFIG_FTRACE" "y"
  add_kconfig_option "CONFIG_DYNAMIC_DEBUG" "y"
  add_kconfig_option "CONFIG_DEBUG_INFO" "y"
  add_kconfig_option "CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT" "y"
  add_kconfig_option "CONFIG_DEBUG_FS" "y"
  add_kconfig_option "CONFIG_HEADERS_INSTALL" "y"
  add_kconfig_option "CONFIG_MODULES" "y"
  add_kconfig_option "CONFIG_MODULE_UNLOAD" "y"
  add_kconfig_option "CONFIG_MODVERSIONS" "y"
  add_kconfig_option "CONFIG_MODULE_SRCVERSION_CB" "y"
  add_kconfig_option "CONFIG_KALLSYMS" "y"
  add_kconfig_option "CONFIG_KALLSYMS_ALL" "y"
  add_kconfig_option "CONFIG_PRINTK" "y"
  add_kconfig_option "CONFIG_BUG" "y"
  add_kconfig_option "CONFIG_ELF_CORE" "y"
  add_kconfig_option "CONFIG_PROC_VMCORE" "y"
  add_kconfig_option "CONFIG_PROC_PAGE_MONITOR" "y"
  add_kconfig_option "CONFIG_STRICT_KERNEL_RWX" "y"
  add_kconfig_option "CONFIG_STRICT_MODULE_RWX" "y"
  add_kconfig_option "CONFIG_LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY" "n"
  add_kconfig_option "CONFIG_SECURITY_LOCKDOWN_LSM" "y"
  add_kconfig_option "CONFIG_SECURITY_LOCKDOWN_LSM_EARLY" "y"
  add_kconfig_option "CONFIG_BPFILTER" "m"
  add_kconfig_option "CONFIG_NETFILTER_INGRESS" "y"
  add_kconfig_option "CONFIG_NETFILTER_EGRESS" "y"
  add_kconfig_option "CONFIG_NET_CLS_BPF" "m"
  add_kconfig_option "CONFIG_NET_CLS_FLOWER" "m"
  add_kconfig_option "CONFIG_NET_CLS_ACT" "m"
  add_kconfig_option "CONFIG_NET_ACT_BPF" "m"
  add_kconfig_option "CONFIG_NET_ACT_CONNMARK" "m"
  add_kconfig_option "CONFIG_NET_ACT_CSUM" "m"
  add_kconfig_option "CONFIG_NET_ACT_GACT" "m"
  add_kconfig_option "CONFIG_NET_ACT_IPT" "m"
  add_kconfig_option "CONFIG_NET_ACT_NAT" "m"
  add_kconfig_option "CONFIG_NET_ACT_PEDIT" "m"
  add_kconfig_option "CONFIG_NET_ACT_SIMP" "m"
  add_kconfig_option "CONFIG_NET_ACT_SKBEDIT" "m"
  add_kconfig_option "CONFIG_NET_ACT_VLAN" "m"
  add_kconfig_option "CONFIG_NET_SCH_INGRESS" "m"
  add_kconfig_option "CONFIG_NET_SCH_SFQ" "m"
  add_kconfig_option "CONFIG_NET_SCH_TBF" "m"
  add_kconfig_option "CONFIG_NET_SCH_HTB" "m"
  add_kconfig_option "CONFIG_NET_SCH_HFSC" "m"
  add_kconfig_option "CONFIG_NET_SCH_PRIO" "m"
  add_kconfig_option "CONFIG_NET_SCH_MULTIQ" "m"
  add_kconfig_option "CONFIG_NET_SCH_RED" "m"
  add_kconfig_option "CONFIG_NET_SCH_TEQL" "m"
  add_kconfig_option "CONFIG_NET_SCH_NETEM" "m"
  add_kconfig_option "CONFIG_NET_SCH_DRR" "m"
  add_kconfig_option "CONFIG_NET_SCH_CHOKE" "m"
  add_kconfig_option "CONFIG_NET_SCH_QFQ" "m"
  add_kconfig_option "CONFIG_NET_SCH_CODEL" "m"
  add_kconfig_option "CONFIG_NET_SCH_FQ_CODEL" "m"
  add_kconfig_option "CONFIG_NET_SCH_FQ" "m"
  add_kconfig_option "CONFIG_NET_SCH_HHF" "m"
  add_kconfig_option "CONFIG_NET_SCH_PIE" "m"
  add_kconfig_option "CONFIG_NET_SCH_FQ_PIE" "m"
  add_kconfig_option "CONFIG_NET_SCH_INGRESS" "m"
  add_kconfig_option "CONFIG_NET_ACT_POLICE" "m"
  add_kconfig_option "CONFIG_NET_ACT_GACT" "m"
  add_kconfig_option "CONFIG_DCB" "y"
  add_kconfig_option "CONFIG_DNS_RESOLVER" "y"
  add_kconfig_option "CONFIG_SW_SYNC" "y"
  add_kconfig_option "CONFIG_SW_SYNC_USER" "y"
  add_kconfig_option "CONFIG_CMA" "y"
  add_kconfig_option "CONFIG_CMA_SIZE_MBYTES" "320"
  add_kconfig_option "CONFIG_CMA_ALIGNMENT" "8"
  add_kconfig_option "CONFIG_DMA_CMA" "y"
  add_kconfig_option "CONFIG_DMA_CMA_ALIGNMENT" "8"
  add_kconfig_option "CONFIG_CGROUP_BPF" "y"
  add_kconfig_option "CONFIG_NETFILTER_XT_SET" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_IDLETIMER" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_LOG" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_MARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NETMAP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NFLOG" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NFQUEUE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_REDIRECT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_SECMARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TCPMSS" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TCPOPTSTRIP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TEE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TRACE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_TARGET_XT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_BPF" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CGROUP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CLUSTER" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_COMMENT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNBYTES" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNLABEL" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNMARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNTRACK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CPU" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_DCCP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_DEVGROUP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_DSCP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_ECN" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_ESP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_HASHLIMIT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_HELPER" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_HL" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_IPCOMP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_IPRANGE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_L2TP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_LENGTH" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_LIMIT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MAC" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MARK" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MULTIPORT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_NFACCT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_OSF" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_OWNER" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_PHYSDEV" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_PKTTYPE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_POLICY" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_QUOTA" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_RATEEST" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_REALM" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_RECENT" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_SCTP" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_SOCKET" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_STATE" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_STATISTIC" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_STRING" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_TCPMSS" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_TIME" "m"
  add_kconfig_option "CONFIG_NETFILTER_XT_MATCH_U32" "m"
  add_kconfig_option "CONFIG_NETFILTER_NETLINK" "m"
  add_kconfig_option "CONFIG_NETFILTER_NETLINK_ACCT" "m"
  add_kconfig_option "CONFIG_NETFILTER_NETLINK_QUEUE" "m"
  add_kconfig_option "CONFIG_NETFILTER_NETLINK_LOG" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_TIMEOUT" "y"
  add_kconfig_option "CONFIG_NF_CONNTRACK_EVENTS" "y"
  add_kconfig_option "CONFIG_NF_CONNTRACK_TIMESTAMP" "y"
  add_kconfig_option "CONFIG_NF_CONNTRACK_LABELS" "y"
  add_kconfig_option "CONFIG_NF_CONNTRACK_ZONES" "y"
  add_kconfig_option "CONFIG_NF_CT_PROTO_DCCP" "m"
  add_kconfig_option "CONFIG_NF_CT_PROTO_GRE" "m"
  add_kconfig_option "CONFIG_NF_CT_PROTO_SCTP" "m"
  add_kconfig_option "CONFIG_NF_CT_PROTO_UDPLITE" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_AMANDA" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_FTP" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_H323" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_IRC" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_NETBIOS_NS" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_SNMP" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_PPTP" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_SANE" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_SIP" "m"
  add_kconfig_option "CONFIG_NF_CONNTRACK_TFTP" "m"
  add_kconfig_option "CONFIG_NF_CT_NETLINK" "m"
  add_kconfig_option "CONFIG_NF_CT_NETLINK_TIMEOUT" "m"
  add_kconfig_option "CONFIG_NF_CT_NETLINK_HELPER" "m"
  add_kconfig_option "CONFIG_NETFILTER_NETLINK_GLUE_CT" "y"
  add_kconfig_option "CONFIG_NF_TABLES" "m"
  add_kconfig_option "CONFIG_NF_TABLES_INET" "y"
  add_kconfig_option "CONFIG_NF_TABLES_NETDEV" "y"
  add_kconfig_option "CONFIG_NFT_NUMGEN" "m"
  add_kconfig_option "CONFIG_NFT_CT" "m"
  add_kconfig_option "CONFIG_NFT_FLOW_OFFLOAD" "m"
  add_kconfig_option "CONFIG_NFT_COUNTER" "m"
  add_kconfig_option "CONFIG_NFT_CONNLIMIT" "m"
  add_kconfig_option "CONFIG_NFT_LOG" "m"
  add_kconfig_option "CONFIG_NFT_LIMIT" "m"
  add_kconfig_option "CONFIG_NFT_MASQ" "m"
  add_kconfig_option "CONFIG_NFT_REDIR" "m"
  add_kconfig_option "CONFIG_NFT_NAT" "m"
  add_kconfig_option "CONFIG_NFT_TUNNEL" "m"
  add_kconfig_option "CONFIG_NFT_OBJREF" "m"
  add_kconfig_option "CONFIG_NFT_QUEUE" "m"
  add_kconfig_option "CONFIG_NFT_QUOTA" "m"
  add_kconfig_option "CONFIG_NFT_REJECT" "m"
  add_kconfig_option "CONFIG_NFT_REJECT_INET" "m"
  add_kconfig_option "CONFIG_NFT_COMPAT" "m"
  add_kconfig_option "CONFIG_NFT_DUP_NETDEV" "m"
  add_kconfig_option "CONFIG_NFT_FWD_NETDEV" "m"
  add_kconfig_option "CONFIG_NFT_HOOK" "m"
  add_kconfig_option "CONFIG_NFT_TRACETYPES" "16"
  add_kconfig_option "CONFIG_NFT_TRACETYPE_DEFAULT" "0"
  add_kconfig_option "CONFIG_NFT_SYNPROXY" "m"
  add_kconfig_option "CONFIG_NFT_DYNLINK" "m"
  add_kconfig_option "CONFIG_NFT_SET_RBTREE" "m"
  add_kconfig_option "CONFIG_NFT_SET_HASH" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_BITMAP" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_BYTEORDER" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_CHAIN" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_CMP" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_CONNLIMIT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_CT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_DYNLINK" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_FLOWOFFLOAD" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_FWD" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_HASH" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_LIMIT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_LOG" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_LOOKUP" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_META" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_NAT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_PAYLOAD" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_QUEUE" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_REJECT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_RT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_SOCKET" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_SYNPROXY" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_TARGET" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_TUNNEL" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_XFRM" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_CGROUP" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_DUP" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_FIB" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_IFINDEX" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_NUMGEN" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_OBJREF" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_OSF" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_PUNCT" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_QUEUE" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_QUOTA" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_RANGE" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_REDIR" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_SOCKET" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_TPROXY" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_TRACE" "m"
  add_kconfig_option "CONFIG_NFT_EXPR_XFRM" "m"
  add_kconfig_option "CONFIG_NFT_CHAIN_ROUTE_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_CHAIN_NAT_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_REJECT_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_DUP_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_FIB_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_NAT_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_CHAIN_ROUTE_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_CHAIN_NAT_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_REJECT_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_DUP_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_FIB_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_NAT_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_MASQ_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_REDIR_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_MASQ_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_REDIR_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_OBJREF" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_INET" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_IPV4" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_IPV6" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_UNIX" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_NETLINK" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_PACKET" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKADDR" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKOPT" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKSTAT" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKTYPE" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKUID" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKGID" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKPID" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKCOMM" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKSTATE" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKPROTO" "m"
  add_kconfig_option "CONFIG_NFT_SOCKET_SOCKDOMAIN" "m"

  echo "NetHunter configurations applied successfully!"
  echo "NETHUNTER_CONFIG_ENABLED=true" >> "$GITHUB_ENV"
  echo "NETHUNTER_CONFIG_APPLIED=true" >> "$GITHUB_ENV"

  # Run olddefconfig again to ensure all new configurations are properly set without interactive prompts
  if ! make O=out olddefconfig; then
    # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
    if ! make O=out silentoldconfig; then
      # Fallback to oldconfig with yes "" if both fail
      run_oldconfig || true
    fi
  fi
fi

# Final configuration validation to ensure no interactive prompts during build
echo "Validating final kernel configuration..."
if ! make O=out olddefconfig; then
  # If olddefconfig fails, use silentoldconfig to avoid interactive prompts
  if ! make O=out silentoldconfig; then
    # Fallback to oldconfig with yes "" if both fail
    run_oldconfig || { echo "ERROR: Final configuration validation failed" > error.log; exit 0; }
  fi
fi

START="$(date +%s)"
if make -j"$(nproc)" O=out LLVM=1 LLVM_IAS=1 2>&1 | tee build.log; then
  echo "SUCCESS=1" >> "$GITHUB_ENV"
else
  echo "SUCCESS=0" >> "$GITHUB_ENV"
  cp -f build.log error.log
fi
END="$(date +%s)"
echo "BUILD_TIME=$((END-START))" >> "$GITHUB_ENV"

KVER="$(make -s kernelversion | tr -d '\n' || true)"
CLANG_VER="$(clang --version | head -n1 | tr -d '\n' || true)"
printf "KERNEL_VERSION=%s\n" "${KVER:-unknown}" >> "$GITHUB_ENV"
printf "CLANG_VERSION=%s\n" "${CLANG_VER:-unknown}" >> "$GITHUB_ENV"

mkdir -p "${GITHUB_WORKSPACE}/kernel" || true
cat build.log >> "${GITHUB_WORKSPACE}/kernel/build.log" 2>/dev/null || true
[ -f error.log ] && cat error.log >> "${GITHUB_WORKSPACE}/kernel/error.log" 2>/dev/null || true

ccache -s || true
exit 0
