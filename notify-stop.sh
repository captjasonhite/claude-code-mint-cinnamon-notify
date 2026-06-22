#!/usr/bin/env bash

uid="$(id -u)"

# Use the standard systemd user bus socket; fall back to scanning the DE process env
if [[ -S "/run/user/$uid/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
else
    for proc in cinnamon gnome-shell plasmashell xfce4-session mate-session; do
        pid="$(pgrep -u "$uid" -x "$proc" | head -n1 || true)"
        [[ -n "$pid" ]] || continue
        dbus="$(tr '\0' '\n' < "/proc/$pid/environ" \
            | grep '^DBUS_SESSION_BUS_ADDRESS=' \
            | cut -d= -f2- || true)"
        [[ -n "$dbus" ]] && export DBUS_SESSION_BUS_ADDRESS="$dbus" && break
    done
fi

notify-send \
    --app-name="Claude Code" \
    --icon=dialog-information \
    --expire-time=5000 \
    --urgency=normal \
    -r 9999 \
    "Claude Code" \
    "Waiting for your input."

echo "$(date): hook fired" >> /tmp/claude-notify.log
