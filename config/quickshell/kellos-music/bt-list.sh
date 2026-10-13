#!/bin/sh
# Список Bluetooth-устройств для панели Kellos: MAC, paired, connected, icon, battery, name
bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off
bluetoothctl show 2>/dev/null | grep -q 'Discovering: yes' && echo scanning || echo idle
echo ---
for m in $(bluetoothctl devices 2>/dev/null | awk '{print $2}'); do
  bluetoothctl info "$m" 2>/dev/null | awk -v m="$m" '
    /^[ \t]*Alias:/ { sub(/^[ \t]*Alias: /, ""); n = $0 }
    /^[ \t]*Icon:/ { i = $2 }
    /^[ \t]*Paired:/ { p = $2 }
    /^[ \t]*Connected:/ { c = $2 }
    /Battery Percentage/ { b = $NF; gsub(/[()]/, "", b) }
    END { print m "\t" p "\t" c "\t" i "\t" b "\t" n }'
done
