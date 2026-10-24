#!/system/bin/sh
# GBOS System, Gaming, RAM, and Performance Optimization
# Configured for 16 GB PC hardware running from USB flash drive

sleep 6

# ==============================================================================
# 1. DISABLE SWAP (Protects USB flash drive from wear, latency spikes, and stalls)
# ==============================================================================
swapoff -a 2>/dev/null
if [ -e /sys/block/zram0/reset ]; then
    echo 1 > /sys/block/zram0/reset 2>/dev/null
fi
# Remove any residual swap backing files on flash storage
rm -rf /data/per_boot/zram_swap /data/vendor/swap 2>/dev/null

# Tune virtual memory kernel parameters for 16 GB RAM without swap:
# - swappiness = 0 (never attempt to swap pages)
# - dirty_ratio & dirty_background_ratio kept tight to avoid USB NAND write stalls
# - vfs_cache_pressure = 100 (standard balance between inode cache and page cache)
sysctl -w vm.swappiness=0 2>/dev/null
sysctl -w vm.dirty_background_ratio=5 2>/dev/null
sysctl -w vm.dirty_ratio=10 2>/dev/null
sysctl -w vm.vfs_cache_pressure=100 2>/dev/null

# ==============================================================================
# 2. OPTIMIZE HEADLESS USER 0 (Frees 2.5 - 3.0 GB of RAM)
# User 0 is headless (system only); User 10 is the interactive human user.
# Disable duplicate client apps & Google services in User 0 ONLY.
# User 10 remains 100% untouched so the user can run all apps normally.
# ==============================================================================
USER0_BLOAT="
com.google.android.apps.messaging
com.google.android.apps.photos
com.google.android.youtube
com.google.android.keep
com.google.android.apps.recorder
com.google.android.apps.bard
com.google.android.retaildemo
com.google.android.federatedcompute
com.google.android.ondevicepersonalization.services
com.google.android.aicore
com.google.android.marvin.talkback
com.android.vending
com.android.chrome
"
for pkg in $USER0_BLOAT; do
    am force-stop --user 0 "$pkg" 2>/dev/null
    pm disable-user --user 0 "$pkg" 2>/dev/null
done

# ==============================================================================
# 3. DISABLE GLOBAL SYSTEM BLOATWARE & TELEMETRY (For All Users)
# Things that serve zero purpose on a laptop PC (retail demo, telemetry trackers)
# ==============================================================================
GLOBAL_BLOAT="
com.google.android.retaildemo
com.google.android.federatedcompute
com.google.android.ondevicepersonalization.services
com.google.android.snapshotservice
com.android.simappdialog
com.android.emergency
com.android.eyedropper
"
for pkg in $GLOBAL_BLOAT; do
    am force-stop "$pkg" 2>/dev/null
    pm disable-user --user 10 "$pkg" 2>/dev/null
done

# ==============================================================================
# 4. SUPPORT USER BACKGROUND PROCESSES & MULTITASKING (User 10)
# Ensure Android does not aggressively kill user apps or background tasks.
# With 16 GB of RAM, we allow up to 64 cached processes and ample background tasks.
# ==============================================================================
setprop persist.sys.max_cached_processes 64
setprop ro.sys.fw.bg_apps_limit 64
setprop sys.use_fifo_ui 1

# Allow background playback & local network discovery for streaming/casting
pm grant --user 10 com.google.ambient.streaming android.permission.ACCESS_LOCAL_NETWORK 2>/dev/null

# ==============================================================================
# 5. HARDWARE, CPU & INPUT OPTIMIZATIONS
# ==============================================================================
# CPU frequency governor: balance_performance avoids micro-stutter when waking idle cores
for g in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo balance_performance > "$g" 2>/dev/null
done

# Disable USB autosuspend on mice/keyboards so there is no wake latency
for d in /sys/bus/usb/devices/*/power/control; do
    echo on > "$d" 2>/dev/null
done

# Suppress drmhwc 60 FPS gamma log spam that causes SurfaceFlinger frame pacing jitter
setprop log.tag.drmhwc WARN
setprop persist.log.tag.drmhwc WARN
setprop service.adb.tcp.port 5555

# ==============================================================================
# 6. APP COMPAT & GAMING ANR FIXES (Unity / Pokémon UNITE)
# ==============================================================================
am compat enable OVERRIDE_ENABLE_COMPAT_FAKE_FOCUS jp.pokemon.pokemonunite 2>/dev/null
am compat enable SKIP_ACTIVITY_RECREATION_ON_CONFIG_CHANGE jp.pokemon.pokemonunite 2>/dev/null
am compat enable OVERRIDE_EXCLUDE_CAPTION_INSETS_FROM_APP_BOUNDS jp.pokemon.pokemonunite 2>/dev/null
cmd game set --fps 60 jp.pokemon.pokemonunite 2>/dev/null
cmd game mode custom jp.pokemon.pokemonunite 2>/dev/null

sync
