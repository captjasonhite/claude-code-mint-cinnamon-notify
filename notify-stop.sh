#!/usr/bin/env bash

hook_input="$(cat)"
info="$(printf '%s' "$hook_input" | python3 -c '
import json, sys, os, datetime

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

session_id = data.get("session_id", "")
cwd = data.get("cwd", "") or os.getcwd()
transcript_path = data.get("transcript_path", "")
project = os.path.basename(cwd.rstrip("/")) or cwd

elapsed = "?"
try:
    import subprocess
    tail = subprocess.run(["tail", "-n", "2000", transcript_path],
                           capture_output=True, text=True, timeout=5).stdout
    last_ts = None
    for line in tail.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue
        if entry.get("type") == "user":
            content = (entry.get("message") or {}).get("content")
            if isinstance(content, str):
                ts = entry.get("timestamp")
                if ts:
                    last_ts = ts
    if last_ts:
        then = datetime.datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
        now = datetime.datetime.now(datetime.timezone.utc)
        secs = max(int((now - then).total_seconds()), 0)
        h, rem = divmod(secs, 3600)
        m, s = divmod(rem, 60)
        elapsed = f"{h}h{m:02d}m" if h else (f"{m}m{s:02d}s" if m else f"{s}s")
except Exception:
    pass

print(f"{session_id}|{project}|{elapsed}")
' 2>/dev/null)"

IFS='|' read -r session_id project elapsed <<< "$info"
[[ -n "$session_id" ]] || session_id="$PPID"
[[ -n "$project" ]] || project="?"
[[ -n "$elapsed" ]] || elapsed="?"
current_time="$(date +"%-I:%M %p")"
notify_body="${current_time} - ${project} - ${elapsed} - Idle"
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
    "$notify_body" 2>&1)"
notify_exit=$?

# Play a sound via PipeWire/PulseAudio
export XDG_RUNTIME_DIR="/run/user/$uid"
paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null &

echo "$(date) [$$]: hook fired | session=${session_id} id=${notify_id} | notify-send exit: ${notify_exit}${notify_err:+ | err: ${notify_err}}" >> /tmp/claude-notify.log
