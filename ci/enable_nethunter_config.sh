#!/usr/bin/env bash
set -euo pipefail

# NetHunter Configuration Integration Script
# This script adds NetHunter-specific kernel configurations to the kernel .config file

echo "Adding NetHunter kernel configurations..."

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

# Check if kernel config exists
if [ ! -f "kernel/out/.config" ]; then
  echo "ERROR: Kernel config file not found at kernel/out/.config" >&2
  exit 1
fi

# Backup original config
cp kernel/out/.config kernel/out/.config.nethunter.bak

echo "Applying NetHunter kernel configurations..."

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
  if grep -q "^# ${option} is not set\\|^${option}=" kernel/out/.config; then
    # Option exists, update it
    sed -i "s/^# ${option} is not set$/${option}=${value}/" kernel/out/.config || {
      echo "ERROR: Failed to update ${option} in kernel config" >&2
      return 1
    }
    sed -i "s/^${option}=.*/${option}=${value}/" kernel/out/.config || {
      echo "ERROR: Failed to update ${option} in kernel config" >&2
      return 1
    }
  else
    # Option doesn't exist, append it
    echo "${option}=${value}" >> kernel/out/.config || {
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
add_kconfig_option "CONFIG_CFG80211" "m"
add_kconfig_option "CONFIG_MAC80211" "m"
add_kconfig_option "CONFIG_MAC80211_MESH" "y"
add_kconfig_option "CONFIG_WIRELESS_EXT" "y"
add_kconfig_option "CONFIG_WEXT_CORE" "y"
add_kconfig_option "CONFIG_WEXT_PROC" "y"
add_kconfig_option "CONFIG_WEXT_SPY" "y"
add_kconfig_option "CONFIG_WEXT_PRIV" "y"

# Enable wireless extensions
add_kconfig_option "CONFIG_WIRELESS" "y"
add_kconfig_option "CONFIG_CFG80211_INTERNAL_REGDB" "y"

# Bluetooth support
add_kconfig_option "CONFIG_BT" "m"
add_kconfig_option "CONFIG_BT_BREDR" "y"
add_kconfig_option "CONFIG_BT_HCIBTUSB" "m"
add_kconfig_option "CONFIG_BT_HCIUART" "m"
add_kconfig_option "CONFIG_BT_HCIUART_BCSP" "y"
add_kconfig_option "CONFIG_BT_HCIUART_LL" "y"
add_kconfig_option "CONFIG_BT_HCIUART_3WIRE" "y"
add_kconfig_option "CONFIG_BT_HCIUART_H4" "y"

# NFC support
add_kconfig_option "CONFIG_NFC" "m"
add_kconfig_option "CONFIG_NFC_NCI" "m"
add_kconfig_option "CONFIG_NFC_DIGITAL" "m"
add_kconfig_option "CONFIG_NFC_LLCP" "m"

# Enable debugfs for monitoring
add_kconfig_option "CONFIG_DEBUG_FS" "y"

# Enable overlay filesystem (needed for chroot environments)
add_kconfig_option "CONFIG_OVERLAY_FS" "m"

# Enable FUSE (for filesystem in userspace)
add_kconfig_option "CONFIG_FUSE_FS" "m"

# Enable binderfs (for Android binderfs functionality)
add_kconfig_option "CONFIG_ANDROID_BINDERFS" "y"
add_kconfig_option "CONFIG_ANDROID_BINDER_DEVICES" '"binder,hwbinder,vndbinder"'

# Enable SELinux support (keeping security but allowing development features)
add_kconfig_option "CONFIG_SECURITY_SELINUX" "y"
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
add_kconfig_option "CONFIG_CFG80211_INTERNAL_REGDB" "y"

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

echo "NetHunter configurations applied successfully!"
echo "NETHUNTER_CONFIG_ENABLED=true" >> "$GITHUB_ENV"
echo "NETHUNTER_CONFIG_APPLIED=true" >> "$GITHUB_ENV"