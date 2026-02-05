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
  echo "Applying universal NetHunter configurations..."

  # Function to safely add or update a kernel config option
  set_kconfig_option() {
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

  # Essential networking configurations for penetration testing
  set_kconfig_option "CONFIG_PACKET" "y"
  set_kconfig_option "CONFIG_PACKET_DIAG" "m"
  set_kconfig_option "CONFIG_UNIX" "y"
  set_kconfig_option "CONFIG_UNIX_DIAG" "m"
  set_kconfig_option "CONFIG_INET" "y"
  set_kconfig_option "CONFIG_IP_MULTICAST" "y"
  set_kconfig_option "CONFIG_IP_ADVANCED_ROUTER" "y"
  set_kconfig_option "CONFIG_IP_MULTIPLE_TABLES" "y"
  set_kconfig_option "CONFIG_IP_ROUTE_MULTIPATH" "y"
  set_kconfig_option "CONFIG_IP_ROUTE_VERBOSE" "y"
  set_kconfig_option "CONFIG_IP_PNP" "y"
  set_kconfig_option "CONFIG_IP_PNP_DHCP" "y"
  set_kconfig_option "CONFIG_IP_PNP_BOOTP" "y"
  set_kconfig_option "CONFIG_IP_PNP_RARP" "y"
  set_kconfig_option "CONFIG_NET_IPIP" "m"
  set_kconfig_option "CONFIG_NET_IPGRE_DEMUX" "m"
  set_kconfig_option "CONFIG_NET_IP_TUNNEL" "m"
  set_kconfig_option "CONFIG_NET_UDP_TUNNEL" "m"
  set_kconfig_option "CONFIG_INET_AH" "m"
  set_kconfig_option "CONFIG_INET_ESP" "m"
  set_kconfig_option "CONFIG_INET_IPCOMP" "m"
  set_kconfig_option "CONFIG_INET_XFRM_TUNNEL" "m"
  set_kconfig_option "CONFIG_INET_TUNNEL" "m"
  set_kconfig_option "CONFIG_INET_DIAG" "m"
  set_kconfig_option "CONFIG_INET_TCP_DIAG" "m"
  set_kconfig_option "CONFIG_INET_UDP_DIAG" "m"
  set_kconfig_option "CONFIG_INET_RAW_DIAG" "m"
  set_kconfig_option "CONFIG_INET_DIAG_DESTROY" "y"
  set_kconfig_option "CONFIG_TCP_CONG_ADVANCED" "y"
  set_kconfig_option "CONFIG_TCP_CONG_BIC" "m"
  set_kconfig_option "CONFIG_TCP_CONG_CUBIC" "m"
  set_kconfig_option "CONFIG_TCP_CONG_WESTWOOD" "m"
  set_kconfig_option "CONFIG_TCP_CONG_HTCP" "m"
  set_kconfig_option "CONFIG_TCP_CONG_HSTCP" "m"
  set_kconfig_option "CONFIG_TCP_CONG_HYBLA" "m"
  set_kconfig_option "CONFIG_TCP_CONG_VEGAS" "m"
  set_kconfig_option "CONFIG_TCP_CONG_NV" "m"
  set_kconfig_option "CONFIG_TCP_CONG_SCALABLE" "m"
  set_kconfig_option "CONFIG_TCP_CONG_LP" "m"
  set_kconfig_option "CONFIG_TCP_CONG_VENO" "m"
  set_kconfig_option "CONFIG_TCP_CONG_YEAH" "m"
  set_kconfig_option "CONFIG_TCP_CONG_ILLINOIS" "m"
  set_kconfig_option "CONFIG_TCP_CONG_DCTCP" "m"
  set_kconfig_option "CONFIG_TCP_CONG_CDG" "m"
  set_kconfig_option "CONFIG_TCP_CONG_BBR" "m"
  set_kconfig_option "CONFIG_DEFAULT_BBR" "y"
  set_kconfig_option "CONFIG_DEFAULT_TCP_CONG" "\"bbr\""
  set_kconfig_option "CONFIG_TCP_MD5SIG" "y"
  set_kconfig_option "CONFIG_IPV6" "y"
  set_kconfig_option "CONFIG_IPV6_ROUTER_PREF" "y"
  set_kconfig_option "CONFIG_IPV6_ROUTE_INFO" "y"
  set_kconfig_option "CONFIG_IPV6_OPTIMISTIC_DAD" "y"
  set_kconfig_option "CONFIG_INET6_AH" "m"
  set_kconfig_option "CONFIG_INET6_ESP" "m"
  set_kconfig_option "CONFIG_INET6_IPCOMP" "m"
  set_kconfig_option "CONFIG_IPV6_MIP6" "m"
  set_kconfig_option "CONFIG_IPV6_ILA" "m"
  set_kconfig_option "CONFIG_IPV6_SEG6_HMAC" "m"
  set_kconfig_option "CONFIG_IPV6_RPL_LWTUNNEL" "y"
  set_kconfig_option "CONFIG_IPV6_RPL" "m"
  set_kconfig_option "CONFIG_MPTCP" "y"
  set_kconfig_option "CONFIG_NETWORK_SECMARK" "y"
  set_kconfig_option "CONFIG_NETFILTER" "y"
  set_kconfig_option "CONFIG_NETFILTER_ADVANCED" "y"
  set_kconfig_option "CONFIG_BRIDGE_NETFILTER" "m"

  # Netfilter/iptables configurations for advanced firewalling
  set_kconfig_option "CONFIG_NETFILTER_XTABLES" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_CONNMARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_SET" "m"

  # Core Netfilter match modules
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_COMMENT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNBYTES" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNLABEL" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNMARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CONNTRACK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_CPU" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_DCCP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_DEVGROUP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_DSCP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_ECN" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_ESP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_HASHLIMIT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_HELPER" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_HL" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_IPCOMP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_IPRANGE" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_L2TP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_LENGTH" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_LIMIT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MAC" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_MULTIPORT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_NFACCT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_OSF" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_OWNER" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_PHYSDEV" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_PKTTYPE" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_POLICY" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_QUOTA" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_RATEEST" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_REALM" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_RECENT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_SCTP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_SOCKET" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_STATE" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_STATISTIC" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_STRING" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_TCPMSS" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_TIME" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_MATCH_U32" "m"

  # Core Netfilter target modules
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CLASSIFY" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CONNMARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CONNSECMARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_CT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_DSCP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_HL" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_HMARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_IDLETIMER" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_LED" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_LOG" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_MARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NETMAP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NFLOG" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_NFQUEUE" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_RATEEST" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_REDIRECT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_SECMARK" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TCPMSS" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TCPOPTSTRIP" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TCPREDIRECT" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TEE" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TPROXY" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_TRACE" "m"
  set_kconfig_option "CONFIG_NETFILTER_XT_TARGET_XT" "m"

  # NAT and connection tracking
  set_kconfig_option "CONFIG_NF_CONNTRACK" "m"
  set_kconfig_option "CONFIG_NF_LOG_COMMON" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_SECMARK" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_ZONES" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_PROCFS" "y"
  set_kconfig_option "CONFIG_NF_CONNTRACK_EVENTS" "y"
  set_kconfig_option "CONFIG_NF_CONNTRACK_TIMESTAMP" "y"
  set_kconfig_option "CONFIG_NF_CONNTRACK_LABELS" "y"
  set_kconfig_option "CONFIG_NF_CT_PROTO_DCCP" "m"
  set_kconfig_option "CONFIG_NF_CT_PROTO_GRE" "m"
  set_kconfig_option "CONFIG_NF_CT_PROTO_SCTP" "m"
  set_kconfig_option "CONFIG_NF_CT_PROTO_UDPLITE" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_AMANDA" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_FTP" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_H323" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_IRC" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_NETBIOS_NS" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_SNMP" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_PPTP" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_SANE" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_SIP" "m"
  set_kconfig_option "CONFIG_NF_CONNTRACK_TFTP" "m"
  set_kconfig_option "CONFIG_NF_CT_NETLINK" "m"
  set_kconfig_option "CONFIG_NF_CT_NETLINK_TIMEOUT" "m"
  set_kconfig_option "CONFIG_NF_CT_NETLINK_HELPER" "m"
  set_kconfig_option "CONFIG_NETFILTER_NETLINK_GLUE_CT" "y"
  set_kconfig_option "CONFIG_NF_NAT" "m"
  set_kconfig_option "CONFIG_NF_NAT_NEEDED" "y"
  set_kconfig_option "CONFIG_NF_NAT_PROTO_GRE" "m"
  set_kconfig_option "CONFIG_NF_NAT_PPTP" "m"
  set_kconfig_option "CONFIG_NF_NAT_SIP" "m"
  set_kconfig_option "CONFIG_NF_NAT_TFTP" "m"
  set_kconfig_option "CONFIG_NF_NAT_REDIRECT" "y"
  set_kconfig_option "CONFIG_NF_TABLES" "m"
  set_kconfig_option "CONFIG_NF_TABLES_INET" "y"
  set_kconfig_option "CONFIG_NF_TABLES_NETDEV" "y"
  set_kconfig_option "CONFIG_NFT_NUMGEN" "m"
  set_kconfig_option "CONFIG_NFT_CT" "m"
  set_kconfig_option "CONFIG_NFT_FLOW_OFFLOAD" "m"
  set_kconfig_option "CONFIG_NFT_COUNTER" "m"
  set_kconfig_option "CONFIG_NFT_CONNLIMIT" "m"
  set_kconfig_option "CONFIG_NFT_LOG" "m"
  set_kconfig_option "CONFIG_NFT_LIMIT" "m"
  set_kconfig_option "CONFIG_NFT_MASQ" "m"
  set_kconfig_option "CONFIG_NFT_REDIR" "m"
  set_kconfig_option "CONFIG_NFT_NAT" "m"
  set_kconfig_option "CONFIG_NFT_TUNNEL" "m"
  set_kconfig_option "CONFIG_NFT_OBJREF" "m"
  set_kconfig_option "CONFIG_NFT_QUEUE" "m"
  set_kconfig_option "CONFIG_NFT_QUOTA" "m"
  set_kconfig_option "CONFIG_NFT_REJECT" "m"
  set_kconfig_option "CONFIG_NFT_REJECT_INET" "m"
  set_kconfig_option "CONFIG_NFT_COMPAT" "m"
  set_kconfig_option "CONFIG_NFT_DUP_NETDEV" "m"
  set_kconfig_option "CONFIG_NFT_FWD_NETDEV" "m"
  set_kconfig_option "CONFIG_NFT_HOOK" "m"
  set_kconfig_option "CONFIG_NFT_TRACETYPES" "16"
  set_kconfig_option "CONFIG_NFT_TRACETYPE_DEFAULT" "0"
  set_kconfig_option "CONFIG_NFT_SYNPROXY" "m"
  set_kconfig_option "CONFIG_NFT_DYNLINK" "m"
  set_kconfig_option "CONFIG_NFT_SET_RBTREE" "m"
  set_kconfig_option "CONFIG_NFT_SET_HASH" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_BITMAP" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_BYTEORDER" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_CHAIN" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_CMP" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_CONNLIMIT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_CT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_DYNLINK" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_FLOWOFFLOAD" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_FWD" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_HASH" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_LIMIT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_LOG" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_LOOKUP" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_META" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_NAT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_PAYLOAD" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_QUEUE" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_REJECT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_RT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_SOCKET" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_SYNPROXY" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_TARGET" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_TUNNEL" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_XFRM" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_CGROUP" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_DUP" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_FIB" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_IFINDEX" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_NUMGEN" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_OBJREF" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_OSF" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_PUNCT" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_QUEUE" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_QUOTA" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_RANGE" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_REDIR" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_SOCKET" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_TPROXY" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_TRACE" "m"
  set_kconfig_option "CONFIG_NFT_EXPR_XFRM" "m"
  set_kconfig_option "CONFIG_NFT_CHAIN_ROUTE_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_CHAIN_NAT_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_REJECT_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_DUP_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_FIB_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_NAT_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_CHAIN_ROUTE_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_CHAIN_NAT_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_REJECT_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_DUP_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_FIB_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_NAT_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_MASQ_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_REDIR_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_MASQ_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_REDIR_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_OBJREF" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_INET" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_IPV4" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_IPV6" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_UNIX" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_NETLINK" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_PACKET" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKADDR" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKOPT" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKSTAT" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKTYPE" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKUID" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKGID" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKPID" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKCOMM" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKSTATE" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKPROTO" "m"
  set_kconfig_option "CONFIG_NFT_SOCKET_SOCKDOMAIN" "m"

  # Wireless configurations for penetration testing
  set_kconfig_option "CONFIG_WIRELESS" "y"
  set_kconfig_option "CONFIG_WIRELESS_EXT" "y"
  set_kconfig_option "CONFIG_WEXT_CORE" "y"
  set_kconfig_option "CONFIG_WEXT_PROC" "y"
  set_kconfig_option "CONFIG_WEXT_SPY" "y"
  set_kconfig_option "CONFIG_WEXT_PRIV" "y"
  set_kconfig_option "CONFIG_CFG80211" "y"
  set_kconfig_option "CONFIG_CFG80211_INTERNAL_REGDB" "y"
  set_kconfig_option "CONFIG_CFG80211_WEXT" "y"
  set_kconfig_option "CONFIG_CFG80211_CRDA_SUPPORT" "y"
  set_kconfig_option "CONFIG_CFG80211_DEFAULT_PS" "y"
  set_kconfig_option "CONFIG_CFG80211_DEBUGFS" "y"
  set_kconfig_option "CONFIG_CFG80211_DISABLE_BEACON_HINTS" "y"
  set_kconfig_option "CONFIG_CFG80211_MBO" "y"
  set_kconfig_option "CONFIG_MAC80211" "y"
  set_kconfig_option "CONFIG_MAC80211_MESH" "y"
  set_kconfig_option "CONFIG_MAC80211_LEDS" "y"
  set_kconfig_option "CONFIG_MAC80211_DEBUGFS" "y"
  set_kconfig_option "CONFIG_MAC80211_STA_HASH_MAX_SIZE" "0"
  set_kconfig_option "CONFIG_RFKILL" "m"
  set_kconfig_option "CONFIG_RFKILL_LEDS" "y"
  set_kconfig_option "CONFIG_RFKILL_INPUT" "y"
  set_kconfig_option "CONFIG_RFKILL_GPIO" "m"
  set_kconfig_option "CONFIG_ATH_COMMON" "m"
  set_kconfig_option "CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS" "y"
  set_kconfig_option "CONFIG_ATH_CARDS" "m"
  set_kconfig_option "CONFIG_ATH9K" "m"
  set_kconfig_option "CONFIG_ATH9K_AHB" "m"
  set_kconfig_option "CONFIG_ATH9K_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_DYN_ACK" "y"
  set_kconfig_option "CONFIG_ATH9K_WOW" "y"
  set_kconfig_option "CONFIG_ATH9K_RFKILL" "y"
  set_kconfig_option "CONFIG_ATH9K_CHANNEL_CONTEXT" "y"
  set_kconfig_option "CONFIG_ATH9K_PCOEM" "y"
  set_kconfig_option "CONFIG_ATH9K_PCI" "y"
  set_kconfig_option "CONFIG_ATH9K_HTC" "m"
  set_kconfig_option "CONFIG_ATH9K_HTC_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_WOW" "y"
  set_kconfig_option "CONFIG_ATH9K_RFKILL" "y"
  set_kconfig_option "CONFIG_ATH9K_CHANNEL_CONTEXT" "y"
  set_kconfig_option "CONFIG_ATH9K_PCOEM" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_CONTROL" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR" "y"
  set_kconfig_option "CONFIG_ATH9K_BTCOEX_SUPPORT" "y"
  set_kconfig_option "CONFIG_ATH9K_PS" "y"
  set_kconfig_option "CONFIG_ATH9K_TX99" "y"
  set_kconfig_option "CONFIG_ATH9K_AHB" "y"
  set_kconfig_option "CONFIG_ATH9K_DEBUG" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_DRIVER" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_DEBUG" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_DEBUG" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_DEBUG" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_TRACE" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUG" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_TRACE" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_TRACE" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_TRACE" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_TRACE" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_TRACE" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_DEBUGFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_PROC" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_SYSFS" "y"
  set_kconfig_option "CONFIG_ATH9K_RATE_AGGR_STATS_EVENTS_TRACE" "y"

  # Bluetooth support for penetration testing
  set_kconfig_option "CONFIG_BT" "y"
  set_kconfig_option "CONFIG_BT_RFCOMM" "y"
  set_kconfig_option "CONFIG_BT_RFCOMM_TTY" "y"
  set_kconfig_option "CONFIG_BT_BNEP" "y"
  set_kconfig_option "CONFIG_BT_BNEP_MC_FILTER" "y"
  set_kconfig_option "CONFIG_BT_BNEP_PROTO_FILTER" "y"
  set_kconfig_option "CONFIG_BT_HIDP" "y"
  set_kconfig_option "CONFIG_BT_HS" "y"
  set_kconfig_option "CONFIG_BT_LE" "y"
  set_kconfig_option "CONFIG_BT_LE_L2CAP" "y"
  set_kconfig_option "CONFIG_BT_SELFTEST" "y"
  set_kconfig_option "CONFIG_BT_DEBUGFS" "y"
  set_kconfig_option "CONFIG_BT_HCIUART" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_H4" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_BCSP" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_ATH3K" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_LL" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_3WIRE" "y"
  set_kconfig_option "CONFIG_BT_HCIBCM203X" "m"
  set_kconfig_option "CONFIG_BT_HCIBPA10X" "m"
  set_kconfig_option "CONFIG_BT_HCIBFUSB" "m"
  set_kconfig_option "CONFIG_BT_HCIDTL1" "m"
  set_kconfig_option "CONFIG_BT_HCIBT3C" "m"
  set_kconfig_option "CONFIG_BT_HCIBLUECARD" "m"
  set_kconfig_option "CONFIG_BT_HCISIBYTE" "m"
  set_kconfig_option "CONFIG_BT_HCIUART_BCM" "y"
  set_kconfig_option "CONFIG_BT_HCIBCM203X" "m"
  set_kconfig_option "CONFIG_BT_HCIBPA10X" "m"
  set_kconfig_option "CONFIG_BT_HCIBFUSB" "m"
  set_kconfig_option "CONFIG_BT_HCIDTL1" "m"
  set_kconfig_option "CONFIG_BT_HCIBT3C" "m"
  set_kconfig_option "CONFIG_BT_HCIBLUECARD" "m"
  set_kconfig_option "CONFIG_BT_HCISIBYTE" "m"
  set_kconfig_option "CONFIG_BT_HCIINTEL" "m"
  set_kconfig_option "CONFIG_BT_HCIRSI" "m"
  set_kconfig_option "CONFIG_BT_HCIBTUSB" "m"
  set_kconfig_option "CONFIG_BT_HCIBTSDIO" "m"
  set_kconfig_option "CONFIG_BT_HCIUART_INTEL" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_BREDR" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_LL" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_3WIRE" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_NATIVE_UART" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_PREFIX" "y"
  set_kconfig_option "CONFIG_BT_HCIUART_MRVL" "y"

  # USB support for various hardware interfaces
  set_kconfig_option "CONFIG_USB" "y"
  set_kconfig_option "CONFIG_USB_ANNOUNCE_NEW_DEVICES" "y"
  set_kconfig_option "CONFIG_USB_DYNAMIC_MINORS" "y"
  set_kconfig_option "CONFIG_USB_SUSPEND" "y"
  set_kconfig_option "CONFIG_USB_OTG" "y"
  set_kconfig_option "CONFIG_USB_MON" "m"
  set_kconfig_option "CONFIG_USB_WUSB" "y"
  set_kconfig_option "CONFIG_USB_WUSB_CBAF" "y"
  set_kconfig_option "CONFIG_USB_WUSB_WHCI" "y"
  set_kconfig_option "CONFIG_USB_WUSB_MMC" "y"
  set_kconfig_option "CONFIG_USB_UWB" "y"
  set_kconfig_option "CONFIG_USB_OTG_PRODUCT" "y"
  set_kconfig_option "CONFIG_USB_OTG_PERIPHERY" "y"
  set_kconfig_option "CONFIG_USB_OTG_UTILS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB_URBS" "y"
  set_kconfig_option "CONFIG_USB_OTG_DISABLE_EXTERNAL_HUB" "y"

  # USB networking support
  set_kconfig_option "CONFIG_USB_NET_DRIVERS" "y"
  set_kconfig_option "CONFIG_USB_USBNET" "y"
  set_kconfig_option "CONFIG_USB_NET_AX8817X" "y"
  set_kconfig_option "CONFIG_USB_NET_CDCETHER" "y"
  set_kconfig_option "CONFIG_USB_NET_CDC_SUBSETTER" "y"
  set_kconfig_option "CONFIG_USB_NET_DM9601" "y"
  set_kconfig_option "CONFIG_USB_NET_SMSC75XX" "y"
  set_kconfig_option "CONFIG_USB_NET_SMSC95XX" "y"
  set_kconfig_option "CONFIG_USB_NET_GL620A" "y"
  set_kconfig_option "CONFIG_USB_NET_MCS7830" "y"
  set_kconfig_option "CONFIG_USB_NET_RNDIS_HOST" "y"
  set_kconfig_option "CONFIG_USB_NET_CDC_NCM" "y"
  set_kconfig_option "CONFIG_USB_NET_HUAWEI_CDC_NCM" "y"
  set_kconfig_option "CONFIG_USB_NET_CDC_MBIM" "y"

  # USB serial support for hardware interfacing
  set_kconfig_option "CONFIG_USB_SERIAL" "y"
  set_kconfig_option "CONFIG_USB_SERIAL_GENERIC" "y"
  set_kconfig_option "CONFIG_USB_SERIAL_FTDI_SIO" "y"
  set_kconfig_option "CONFIG_USB_SERIAL_PL2303" "y"
  set_kconfig_option "CONFIG_USB_SERIAL_CH341" "y"

  # GPIO, SPI, I2C support for hardware interfacing
  set_kconfig_option "CONFIG_GPIOLIB" "y"
  set_kconfig_option "CONFIG_OF_GPIO" "y"
  set_kconfig_option "CONFIG_DEBUG_GPIO" "y"
  set_kconfig_option "CONFIG_SPI" "y"
  set_kconfig_option "CONFIG_SPI_MASTER" "y"
  set_kconfig_option "CONFIG_I2C" "y"
  set_kconfig_option "CONFIG_I2C_CHARDEV" "y"

  # Hardware random number generator
  set_kconfig_option "CONFIG_HW_RANDOM" "y"

  # Crypto algorithms needed for security tools
  set_kconfig_option "CONFIG_CRYPTO_AES" "y"
  set_kconfig_option "CONFIG_CRYPTO_ARC4" "y"
  set_kconfig_option "CONFIG_CRYPTO_DES" "y"
  set_kconfig_option "CONFIG_CRYPTO_TWOFISH" "y"
  set_kconfig_option "CONFIG_CRYPTO_SERPENT" "y"
  set_kconfig_option "CONFIG_CRYPTO_CAMELLIA" "y"
  set_kconfig_option "CONFIG_CRYPTO_BLOWFISH" "y"
  set_kconfig_option "CONFIG_CRYPTO_CAST5" "y"
  set_kconfig_option "CONFIG_CRYPTO_CAST6" "y"
  set_kconfig_option "CONFIG_CRYPTO_ANUBIS" "y"
  set_kconfig_option "CONFIG_CRYPTO_TEA" "y"
  set_kconfig_option "CONFIG_CRYPTO_MICHAEL_MIC" "y"
  set_kconfig_option "CONFIG_CRYPTO_CRC32C" "y"
  set_kconfig_option "CONFIG_CRYPTO_CRC32" "y"
  set_kconfig_option "CONFIG_CRYPTO_DEFLATE" "y"
  set_kconfig_option "CONFIG_CRYPTO_ZLIB" "y"
  set_kconfig_option "CONFIG_CRYPTO_LZO" "y"
  set_kconfig_option "CONFIG_CRYPTO_LZ4" "y"
  set_kconfig_option "CONFIG_CRYPTO_ADIANTUM" "y"
  set_kconfig_option "CONFIG_CRYPTO_XTS" "y"
  set_kconfig_option "CONFIG_CRYPTO_KEYWRAP" "y"
  set_kconfig_option "CONFIG_CRYPTO_CMAC" "y"
  set_kconfig_option "CONFIG_CRYPTO_GCM" "y"
  set_kconfig_option "CONFIG_CRYPTO_CHACHA20POLY1305" "y"
  set_kconfig_option "CONFIG_CRYPTO_ECHAINIV" "y"
  set_kconfig_option "CONFIG_CRYPTO_ABLK_HELPER" "y"
  set_kconfig_option "CONFIG_CRYPTO_GF128MUL" "y"
  set_kconfig_option "CONFIG_CRYPTO_SEQIV" "y"
  set_kconfig_option "CONFIG_CRYPTO_LRW" "y"
  set_kconfig_option "CONFIG_CRYPTO_PCBC" "y"
  set_kconfig_option "CONFIG_CRYPTO_AUTHENC" "y"
  set_kconfig_option "CONFIG_CRYPTO_TEST" "m"

  # Containerization and namespace support
  set_kconfig_option "CONFIG_NAMESPACES" "y"
  set_kconfig_option "CONFIG_UTS_NS" "y"
  set_kconfig_option "CONFIG_IPC_NS" "y"
  set_kconfig_option "CONFIG_USER_NS" "y"
  set_kconfig_option "CONFIG_PID_NS" "y"
  set_kconfig_option "CONFIG_NET_NS" "y"
  set_kconfig_option "CONFIG_CGROUPS" "y"
  set_kconfig_option "CONFIG_CGROUP_FREEZER" "y"
  set_kconfig_option "CONFIG_CGROUP_PIDS" "y"
  set_kconfig_option "CONFIG_CGROUP_DEVICE" "y"
  set_kconfig_option "CONFIG_CPUSETS" "y"
  set_kconfig_option "CONFIG_CGROUP_CPUACCT" "y"
  set_kconfig_option "CONFIG_MEMCG" "y"
  set_kconfig_option "CONFIG_SYSCTL_SYSCALL" "y"

  # Module signing disabled for custom module loading capability
  set_kconfig_option "CONFIG_MODULE_SIG" "n"
  set_kconfig_option "CONFIG_MODULE_SIG_FORCE" "n"

  # Virtual sockets and tunneling
  set_kconfig_option "CONFIG_VSOCKETS" "m"
  set_kconfig_option "CONFIG_VSOCKETS_DIAG" "m"
  set_kconfig_option "CONFIG_VSOCKETS_LOOPBACK" "y"
  set_kconfig_option "CONFIG_TUN" "m"

  # CAN bus support for automotive/networking tools
  set_kconfig_option "CONFIG_CAN" "m"
  set_kconfig_option "CONFIG_CAN_RAW" "m"
  set_kconfig_option "CONFIG_CAN_BCM" "m"
  set_kconfig_option "CONFIG_CAN_GW" "m"
  set_kconfig_option "CONFIG_CAN_J1939" "m"
  set_kconfig_option "CONFIG_CAN_ISOTP" "m"

  # NFC and infrared support
  set_kconfig_option "CONFIG_NFC" "m"
  set_kconfig_option "CONFIG_NFC_DIGITAL" "m"
  set_kconfig_option "CONFIG_NFC_NCI" "m"
  set_kconfig_option "CONFIG_NFC_HCI" "m"
  set_kconfig_option "CONFIG_NFC_SHDLC" "y"
  set_kconfig_option "CONFIG_IR_CORE" "m"
  set_kconfig_option "CONFIG_IR_TUNER" "m"

  # Audio and video support for tools
  set_kconfig_option "CONFIG_SOUND" "m"
  set_kconfig_option "CONFIG_SND" "m"
  set_kconfig_option "CONFIG_SND_HRTIMER" "m"
  set_kconfig_option "CONFIG_SND_SEQ_DUMMY" "m"
  set_kconfig_option "CONFIG_SND_DUMMY" "m"
  set_kconfig_option "CONFIG_SND_VIRMIDI" "m"
  set_kconfig_option "CONFIG_SND_MTPAV" "m"
  set_kconfig_option "CONFIG_SND_SERIAL_U16550" "m"
  set_kconfig_option "CONFIG_SND_MPU401_UART" "m"
  set_kconfig_option "CONFIG_VIDEO_DEV" "m"
  set_kconfig_option "CONFIG_VIDEO_V4L2" "m"
  set_kconfig_option "CONFIG_VIDEO_CAPTURE_DRIVERS" "y"

  # Debugging and development support
  set_kconfig_option "CONFIG_FRAMEBUFFER_CONSOLE" "y"
  set_kconfig_option "CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY" "y"
  set_kconfig_option "CONFIG_FRAMEBUFFER_CONSOLE_ROTATION" "y"
  set_kconfig_option "CONFIG_EARLY_PRINTK" "y"
  set_kconfig_option "CONFIG_PROC_VMCORE" "y"
  set_kconfig_option "CONFIG_PROC_PAGE_MONITOR" "y"
  set_kconfig_option "CONFIG_KPROBES" "y"
  set_kconfig_option "CONFIG_KPROBE_EVENTS" "y"
  set_kconfig_option "CONFIG_UPROBES" "y"
  set_kconfig_option "CONFIG_UPROBE_EVENTS" "y"
  set_kconfig_option "CONFIG_TRACEPOINTS" "y"
  set_kconfig_option "CONFIG_FUNCTION_TRACER" "y"
  set_kconfig_option "CONFIG_IRQSOFF_TRACER" "y"
  set_kconfig_option "CONFIG_PREEMPT_TRACER" "y"
  set_kconfig_option "CONFIG_SCHED_TRACER" "y"
  set_kconfig_option "CONFIG_ENABLE_DEFAULT_TRACERS" "y"
  set_kconfig_option "CONFIG_STACK_TRACER" "y"
  set_kconfig_option "CONFIG_BLK_TRACER" "y"
  set_kconfig_option "CONFIG_PROVEVENT" "y"
  set_kconfig_option "CONFIG_EVENT_TRACING" "y"
  set_kconfig_option "CONFIG_CONTEXT_SWITCH_TRACER" "y"
  set_kconfig_option "CONFIG_CMDLINE_FROM_BOOTLOADER" "y"
  set_kconfig_option "CONFIG_MAGIC_SYSRQ" "y"
  set_kconfig_option "CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE" "0x01b6"

  # Core kernel features
  set_kconfig_option "CONFIG_EMBEDDED" "y"
  set_kconfig_option "CONFIG_EXPERT" "y"
  set_kconfig_option "CONFIG_SYSVIPC" "y"
  set_kconfig_option "CONFIG_POSIX_MQUEUE" "y"
  set_kconfig_option "CONFIG_CHECKPOINT_RESTORE" "y"
  set_kconfig_option "CONFIG_BPF_SYSCALL" "y"
  set_kconfig_option "CONFIG_BPF_JIT" "y"
  set_kconfig_option "CONFIG_FTRACE" "y"
  set_kconfig_option "CONFIG_DYNAMIC_DEBUG" "y"
  set_kconfig_option "CONFIG_DEBUG_INFO" "y"
  set_kconfig_option "CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT" "y"
  set_kconfig_option "CONFIG_DEBUG_FS" "y"
  set_kconfig_option "CONFIG_HEADERS_INSTALL" "y"
  set_kconfig_option "CONFIG_MODULES" "y"
  set_kconfig_option "CONFIG_MODULE_UNLOAD" "y"
  set_kconfig_option "CONFIG_MODVERSIONS" "y"
  set_kconfig_option "CONFIG_MODULE_SRCVERSION_CB" "y"
  set_kconfig_option "CONFIG_KALLSYMS" "y"
  set_kconfig_option "CONFIG_KALLSYMS_ALL" "y"
  set_kconfig_option "CONFIG_PRINTK" "y"
  set_kconfig_option "CONFIG_BUG" "y"
  set_kconfig_option "CONFIG_ELF_CORE" "y"
  set_kconfig_option "CONFIG_PROC_VMCORE" "y"
  set_kconfig_option "CONFIG_PROC_PAGE_MONITOR" "y"
  set_kconfig_option "CONFIG_STRICT_KERNEL_RWX" "y"
  set_kconfig_option "CONFIG_STRICT_MODULE_RWX" "y"
  set_kconfig_option "CONFIG_LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY" "n"
  set_kconfig_option "CONFIG_SECURITY_LOCKDOWN_LSM" "y"
  set_kconfig_option "CONFIG_SECURITY_LOCKDOWN_LSM_EARLY" "y"
  set_kconfig_option "CONFIG_BPFILTER" "m"

  # Bridge and virtual networking
  set_kconfig_option "CONFIG_BRIDGE" "m"
  set_kconfig_option "CONFIG_BRIDGE_IGMP_SNOOPING" "y"
  set_kconfig_option "CONFIG_MACVLAN" "m"
  set_kconfig_option "CONFIG_IPVLAN" "m"

  # Memory management
  set_kconfig_option "CONFIG_CMA" "y"
  set_kconfig_option "CONFIG_CMA_SIZE_MBYTES" "320"
  set_kconfig_option "CONFIG_CMA_ALIGNMENT" "8"
  set_kconfig_option "CONFIG_DMA_CMA" "y"
  set_kconfig_option "CONFIG_DMA_CMA_ALIGNMENT" "8"
  set_kconfig_option "CONFIG_CGROUP_BPF" "y"

  echo "Universal NetHunter configurations applied successfully!"
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

# Disable DTBO build if mkdtimg is not available to prevent build failure
if ! command -v mkdtimg &> /dev/null; then
    echo "WARNING: mkdtimg not found, disabling DTBO build to prevent failure"
    # Add configuration to disable DTBO image creation if it exists
    if [ -f "out/.config" ]; then
        sed -i 's/CONFIG_BUILD_ARM64_DT_OVERLAY=y/# CONFIG_BUILD_ARM64_DT_OVERLAY is not set/g' out/.config || true
        sed -i 's/CONFIG_ARM64_DT_OVERLAY=y/# CONFIG_ARM64_DT_OVERLAY is not set/g' out/.config || true
    fi
fi

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
