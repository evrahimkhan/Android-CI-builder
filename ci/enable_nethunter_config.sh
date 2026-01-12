#!/usr/bin/env bash
set -euo pipefail

# NetHunter Configuration Integration Script
# This script adds NetHunter-specific kernel configurations to the kernel .config file

DEFCONFIG="${1:?defconfig required}"

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
cp kernel/out/.config kernel/out/.config.original

echo "Applying NetHunter kernel configurations..."

# Add NetHunter-specific configurations based on the documentation
# These are common configurations needed for NetHunter functionality

# USB Modem and networking configurations
cat >> kernel/out/.config << 'EOF'

# NetHunter-specific configurations
CONFIG_USB_NET_DRIVERS=y
CONFIG_USB_USBNET=y
CONFIG_USB_NET_AX8817X=y
CONFIG_USB_NET_CDCETHER=y
CONFIG_USB_NET_CDC_SUBSETTER=y
CONFIG_USB_NET_DM9601=y
CONFIG_USB_NET_SMSC75XX=y
CONFIG_USB_NET_SMSC95XX=y
CONFIG_USB_NET_GL620A=y
CONFIG_USB_NET_MCS7830=y
CONFIG_USB_NET_RNDIS_HOST=y
CONFIG_USB_NET_CDC_NCM=y
CONFIG_USB_NET_HUAWEI_CDC_NCM=y
CONFIG_USB_NET_CDC_MBIM=y

# Wireless configurations for penetration testing
CONFIG_CFG80211=m
CONFIG_MAC80211=m
CONFIG_MAC80211_MESH=y
CONFIG_WIRELESS_EXT=y
CONFIG_WEXT_CORE=y
CONFIG_WEXT_PROC=y
CONFIG_WEXT_SPY=y
CONFIG_WEXT_PRIV=y

# Enable wireless extensions
CONFIG_WIRELESS=y
CONFIG_CFG80211_INTERNAL_REGDB=y
CONFIG_CFG80211=m
CONFIG_CFG80211=m
CONFIG_CFG80211=m

# Bluetooth support
CONFIG_BT=m
CONFIG_BT_BREDR=y
CONFIG_BT_HCIBTUSB=m
CONFIG_BT_HCIUART=m
CONFIG_BT_HCIUART_BCSP=y
CONFIG_BT_HCIUART_LL=y
CONFIG_BT_HCIUART_3WIRE=y
CONFIG_BT_HCIUART_H4=y

# NFC support
CONFIG_NFC=m
CONFIG_NFC_NCI=m
CONFIG_NFC_DIGITAL=m
CONFIG_NFC_LLCP=m

# Enable debugfs for monitoring
CONFIG_DEBUG_FS=y

# Enable overlay filesystem (needed for chroot environments)
CONFIG_OVERLAY_FS=m

# Enable FUSE (for filesystem in userspace)
CONFIG_FUSE_FS=m

# Enable binderfs (for Android binderfs functionality)
CONFIG_ANDROID_BINDERFS=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"

# Enable SELinux support
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_SELINUX_DEVELOP=y

# Enable namespaces for containerization
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y

# Enable cgroups
CONFIG_CGROUPS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_PIDS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CPUSETS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_MEMCG=y

# Enable usermode helper
CONFIG_SYSCTL_SYSCALL=y

# Enable module signing (may need to be disabled for custom modules)
CONFIG_MODULE_SIG=n
CONFIG_MODULE_SIG_FORCE=n

# Enable wireless regulatory database
CONFIG_CFG80211_INTERNAL_REGDB=y

# Enable rfkill for wireless kill switch support
CONFIG_RFKILL=m
CONFIG_RFKILL_INPUT=y
CONFIG_RFKILL_GPIO=m

# Enable LED triggers for wireless
CONFIG_LEDS_TRIGGER_PHY=y

# Enable USB serial support
CONFIG_USB_SERIAL=y
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_SERIAL_FTDI_SIO=y
CONFIG_USB_SERIAL_PL2303=y
CONFIG_USB_SERIAL_CH341=y

# Enable GPIO support for hardware interfacing
CONFIG_GPIOLIB=y
CONFIG_OF_GPIO=y
CONFIG_DEBUG_GPIO=y

# Enable SPI support for hardware interfacing
CONFIG_SPI=y
CONFIG_SPI_MASTER=y

# Enable I2C support for hardware interfacing
CONFIG_I2C=y
CONFIG_I2C_CHARDEV=y

# Enable hardware random number generator
CONFIG_HW_RANDOM=y

# Enable crypto algorithms needed for security tools
CONFIG_CRYPTO_AES=y
CONFIG_CRYPTO_ARC4=y
CONFIG_CRYPTO_DES=y
CONFIG_CRYPTO_TWOFISH=y
CONFIG_CRYPTO_SERPENT=y
CONFIG_CRYPTO_CAMELLIA=y
CONFIG_CRYPTO_BLOWFISH=y
CONFIG_CRYPTO_CAST5=y
CONFIG_CRYPTO_CAST6=y
CONFIG_CRYPTO_KHAZAD=y
CONFIG_CRYPTO_ANUBIS=y
CONFIG_CRYPTO_KHAZAD=y
CONFIG_CRYPTO_TEA=y
CONFIG_CRYPTO_ARC4=y
CONFIG_CRYPTO_MICHAEL_MIC=y
CONFIG_CRYPTO_CRC32C=y
CONFIG_CRYPTO_CRC32=y
CONFIG_CRYPTO_DEFLATE=y
CONFIG_CRYPTO_ZLIB=y
CONFIG_CRYPTO_LZO=y
CONFIG_CRYPTO_LZ4=y
CONFIG_CRYPTO_ADIANTUM=y
CONFIG_CRYPTO_XTS=y
CONFIG_CRYPTO_KEYWRAP=y
CONFIG_CRYPTO_CMAC=y
CONFIG_CRYPTO_GCM=y
CONFIG_CRYPTO_CHACHA20POLY1305=y
CONFIG_CRYPTO_ECHAINIV=y
CONFIG_CRYPTO_ABLK_HELPER=y
CONFIG_CRYPTO_GF128MUL=y
CONFIG_CRYPTO_SEQIV=y
CONFIG_CRYPTO_LRW=y
CONFIG_CRYPTO_PCBC=y
CONFIG_CRYPTO_AUTHENC=y
CONFIG_CRYPTO_TEST=m

# Enable network packet filtering (iptables)
CONFIG_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y

# Enable iptables match modules
CONFIG_NETFILTER_XTABLES=m
CONFIG_NETFILTER_XT_MATCH_COMMENT=m
CONFIG_NETFILTER_XT_MATCH_CONNTRACK=m
CONFIG_NETFILTER_XT_MATCH_MULTIPORT=m
CONFIG_NETFILTER_XT_MATCH_PKTTYPE=m
CONFIG_NETFILTER_XT_MATCH_BPF=m

# Enable iptables target modules
CONFIG_NETFILTER_XT_TARGET_CLASSIFY=m
CONFIG_NETFILTER_XT_TARGET_CONNMARK=m
CONFIG_NETFILTER_XT_TARGET_CONNSECMARK=m
CONFIG_NETFILTER_XT_TARGET_MARK=m
CONFIG_NETFILTER_XT_TARGET_NFLOG=m
CONFIG_NETFILTER_XT_TARGET_NFQUEUE=m
CONFIG_NETFILTER_XT_TARGET_SECMARK=m
CONFIG_NETFILTER_XT_TARGET_TCPMSS=m

# Enable netfilter connection tracking
CONFIG_NF_CONNTRACK=m
CONFIG_NF_CONNTRACK_IPV4=m
CONFIG_NF_CONNTRACK_IPV6=m
CONFIG_NF_CT_PROTO_DCCP=m
CONFIG_NF_CT_PROTO_SCTP=m
CONFIG_NF_CT_PROTO_UDPLITE=m
CONFIG_NF_CONNTRACK_EVENTS=y
CONFIG_NF_CONNTRACK_TIMEOUT=y
CONFIG_NF_CONNTRACK_TIMESTAMP=y

# Enable iptables raw table
CONFIG_IP_NF_RAW=m

# Enable iptables security table
CONFIG_IP_NF_SECURITY=m

# Enable bridge support
CONFIG_BRIDGE=m
CONFIG_BRIDGE_IGMP_SNOOPING=y

# Enable MACVLAN and IPVLAN
CONFIG_MACVLAN=m
CONFIG_IPVLAN=m

# Enable Virtual Sockets (for Android inter-process communication)
CONFIG_VSOCKETS=m
CONFIG_VSOCKETS_DIAG=m
CONFIG_VSOCKETS_LOOPBACK=y

# Enable TUN/TAP support (for VPN and tunneling)
CONFIG_TUN=m

# Enable CAN bus support (for automotive/networking tools)
CONFIG_CAN=m
CONFIG_CAN_RAW=m
CONFIG_CAN_BCM=m
CONFIG_CAN_GW=m
CONFIG_CAN_J1939=m
CONFIG_CAN_ISOTP=m

# Enable NFC subsystem
CONFIG_NFC=m
CONFIG_NFC_DIGITAL=m
CONFIG_NFC_NCI=m
CONFIG_NFC_HCI=m
CONFIG_NFC_SHDLC=y

# Enable Infrared support
CONFIG_IR_CORE=m
CONFIG_IR_TUNER=m

# Enable Sound support for audio-based tools
CONFIG_SOUND=m
CONFIG_SND=m
CONFIG_SND_HRTIMER=m
CONFIG_SND_SEQ_DUMMY=m
CONFIG_SND_DUMMY=m
CONFIG_SND_VIRMIDI=m
CONFIG_SND_MTPAV=m
CONFIG_SND_SERIAL_U16550=m
CONFIG_SND_MPU401_UART=m

# Enable video input for camera-based tools
CONFIG_VIDEO_DEV=m
CONFIG_VIDEO_V4L2=m
CONFIG_VIDEO_CAPTURE_DRIVERS=y

# Enable framebuffer console for debugging
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y

# Enable early printk for debugging
CONFIG_EARLY_PRINTK=y

# Enable crash dump support
CONFIG_PROC_VMCORE=y
CONFIG_PROC_PAGE_MONITOR=y

# Enable kprobes for dynamic instrumentation
CONFIG_KPROBES=y
CONFIG_KPROBE_EVENTS=y

# Enable uprobes for userspace dynamic instrumentation
CONFIG_UPROBES=y
CONFIG_UPROBE_EVENTS=y

# Enable trace events
CONFIG_TRACEPOINTS=y

# Enable ftrace for function tracing
CONFIG_FUNCTION_TRACER=y
CONFIG_IRQSOFF_TRACER=y
CONFIG_PREEMPT_TRACER=y
CONFIG_SCHED_TRACER=y
CONFIG_ENABLE_DEFAULT_TRACERS=y
CONFIG_STACK_TRACER=y
CONFIG_BLK_TRACER=y
CONFIG_PROVEVENT=y
CONFIG_EVENT_TRACING=y
CONFIG_CONTEXT_SWITCH_TRACER=y
CONFIG_CMDLINE_FROM_BOOTLOADER=y

# Enable kernel hacking options for development
CONFIG_MAGIC_SYSRQ=y
CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE=0x01b6

EOF

echo "NetHunter configurations applied successfully!"
echo "NetHunter configuration: enabled" >> "$GITHUB_ENV"