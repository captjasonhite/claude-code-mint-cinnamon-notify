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

    def find_last_ts(n_lines):
        tail = subprocess.run(["tail", "-n", str(n_lines), transcript_path],
                               capture_output=True, text=True, timeout=5).stdout
        found = None
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
                        found = ts
        return found

    # Tool-heavy sessions can push the last real prompt past a small tail
    # window, so widen the scan if nothing turns up in the first pass.
    last_ts = find_last_ts(2000)
    if last_ts is None:
        last_ts = find_last_ts(200000)
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

NOTIFY_LOG="/tmp/claude-notify.log"

# Rotate the log so it doesn't grow unbounded across a long uptime.
if [[ -f "$NOTIFY_LOG" ]] && [[ $(wc -l < "$NOTIFY_LOG") -gt 5000 ]]; then
    tail -n 1000 "$NOTIFY_LOG" > "$NOTIFY_LOG.tmp" && mv "$NOTIFY_LOG.tmp" "$NOTIFY_LOG"
fi

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

# Verify daemon is alive before sending — notify-send exits 0 even when daemon is dead.
# Wrapped in `timeout` because a wedged bus can hang the call instead of failing fast,
# which would otherwise block this Stop hook (and Claude Code) indefinitely.
if ! timeout 5 gdbus call --session \
    --dest=org.freedesktop.Notifications \
    --object-path=/org/freedesktop/Notifications \
    --method=org.freedesktop.Notifications.GetServerInformation \
    >/dev/null 2>&1; then
    echo "$(date) [$$]: DAEMON DEAD | no notification sent" >> "$NOTIFY_LOG"
    exit 0
fi

notify_err="$(timeout 5 notify-send \
    --app-name="Claude Code" \
    --icon=dialog-information \
    --expire-time=8000 \
    --urgency=critical \
    -r "$notify_id" \
    "Claude Code" \
    "$notify_body" 2>&1)"
notify_exit=$?

# Play a sound via PipeWire/PulseAudio. Backgrounded + disowned so it isn't
# killed if the hook's process group is torn down as soon as this script exits.
export XDG_RUNTIME_DIR="/run/user/$uid"
timeout 5 paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null &
disown

echo "$(date) [$$]: hook fired | session=${session_id} id=${notify_id} | notify-send exit: ${notify_exit}${notify_err:+ | err: ${notify_err}}" >> "$NOTIFY_LOG"
