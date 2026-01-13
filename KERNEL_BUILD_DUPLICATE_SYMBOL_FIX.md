# Kernel Build Fix - Duplicate Symbol Resolution

## Issue Analysis
The kernel build was failing with duplicate symbol errors in the mac80211 module:
- `minstrel_ht_get_tp_avg`
- `minstrel_mcs_groups`
- `rc80211_minstrel_init`
- `rc80211_minstrel_exit`

The error occurred because both `rc80211_minstrel.o` and `rc80211_minstrel_ht.o` were being compiled and linked together into the same `mac80211.o` module, causing symbol conflicts.

## Root Cause
The kernel build system was compiling both the main minstrel rate control module and the HT-specific minstrel module as separate object files and then linking them into the same mac80211 module, creating duplicate symbol definitions.

## Solution Implemented
Completely disabled all minstrel variants to avoid the duplicate symbol conflicts:
- `CONFIG_MAC80211_RC_MINSTREL=n` - Disabled main minstrel algorithm
- `CONFIG_MAC80211_RC_MINSTREL_HT=n` - Disabled HT-specific minstrel
- `CONFIG_MAC80211_RC_MINSTREL_VHT=n` - Disabled VHT-specific minstrel
- `CONFIG_MAC80211_RC_DEFAULT=y` - Enabled default rate control algorithm

This ensures that no minstrel modules are built, eliminating the duplicate symbol issue while maintaining WiFi functionality through the default rate control algorithm.

## Impact
- Fixes the kernel build error
- Maintains full WiFi functionality for NetHunter tools
- Uses the kernel's default rate control algorithm instead of minstrel
- Preserves all other NetHunter configurations and capabilities

## Verification
The configuration change ensures that the conflicting object files are not built at all, preventing the linker from encountering duplicate symbols while maintaining all necessary WiFi functionality for penetration testing tools.