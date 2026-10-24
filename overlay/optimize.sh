#!/system/bin/sh
# GBOS System, Gaming and Hardware Optimization
sleep 8
setprop service.adb.tcp.port 5555
setprop log.tag.drmhwc WARN
setprop persist.log.tag.drmhwc WARN
for g in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo balance_performance > "$g" 2>/dev/null
done
for d in /sys/bus/usb/devices/*/power/control; do
    echo on > "$d" 2>/dev/null
done
# Unity / Pokémon UNITE window focus & frame pacing fixes
am compat enable OVERRIDE_ENABLE_COMPAT_FAKE_FOCUS jp.pokemon.pokemonunite 2>/dev/null
am compat enable SKIP_ACTIVITY_RECREATION_ON_CONFIG_CHANGE jp.pokemon.pokemonunite 2>/dev/null
am compat enable OVERRIDE_EXCLUDE_CAPTION_INSETS_FROM_APP_BOUNDS jp.pokemon.pokemonunite 2>/dev/null
cmd game set --fps 60 jp.pokemon.pokemonunite 2>/dev/null
cmd game mode custom jp.pokemon.pokemonunite 2>/dev/null
pm grant --user 10 com.google.ambient.streaming android.permission.ACCESS_LOCAL_NETWORK 2>/dev/null
sync
