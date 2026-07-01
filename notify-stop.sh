#!/usr/bin/env bash

hook_input="$(cat)"
session_id="$(printf '%s' "$hook_input" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("session_id",""))
except Exception:
    print("")' 2>/dev/null)"
[[ -n "$session_id" ]] || session_id="$PPID"
notify_id="$(( $(printf '%s' "$session_id" | cksum | cut -d' ' -f1) % 2147483647 ))"

uid="$(id -u)"

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

# Verify daemon is alive before sending — notify-send exits 0 even when daemon is dead
if ! gdbus call --session \
    --dest=org.freedesktop.Notifications \
    --object-path=/org/freedesktop/Notifications \
    --method=org.freedesktop.Notifications.GetServerInformation \
    >/dev/null 2>&1; then
    echo "$(date) [$$]: DAEMON DEAD | no notification sent" >> /tmp/claude-notify.log
    exit 0
fi

notify_err="$(notify-send \
    --app-name="Claude Code" \
    --icon=dialog-information \
    --expire-time=8000 \
    --urgency=critical \
    -r "$notify_id" \
    "Claude Code" \
    "Waiting for your input." 2>&1)"
notify_exit=$?

# Play a sound via PipeWire/PulseAudio
export XDG_RUNTIME_DIR="/run/user/$uid"
paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null &

echo "$(date) [$$]: hook fired | session=${session_id} id=${notify_id} | notify-send exit: ${notify_exit}${notify_err:+ | err: ${notify_err}}" >> /tmp/claude-notify.log
