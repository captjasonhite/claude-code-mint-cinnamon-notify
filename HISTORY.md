# Claude Code Notification Hook — Change History

Send this file to Claude when notifications stop working.

---

## Current state

**Hook script:** `~/.claude/notify-stop.sh`
**Hook registered in:** `~/.claude/settings.json` (Stop hook)
**Log file:** `/tmp/claude-notify.log` (resets on reboot)

To check if the hook is firing at all:
```
cat /tmp/claude-notify.log
```

---

## Session log

### 2026-06-22 — Initial setup

- Created `~/.claude/notify-stop.sh` with D-Bus detection logic
- Registered Stop hook in `~/.claude/settings.json`
- Hook also accidentally added to `~/.claude/settings.local.json` (duplicate)
- Confirmed working at end of session

---

### 2026-06-23 — Broke after working briefly in the morning

**Symptoms:** Notifications stopped appearing. Worked briefly after a Claude restart, then went silent.

**Diagnosed:**
- Hook IS firing (confirmed via log file — script runs on every Stop event)
- `notify-send` exits 0 but notification does not appear
- Root cause of silent failure not yet confirmed
- Suspected: Cinnamon notification daemon becomes unresponsive over time

**Changes made:**
1. Removed duplicate Stop hook from `~/.claude/settings.local.json` (it was overriding or conflicting with `settings.json`)
2. Added logging to `~/.claude/notify-stop.sh`:
   - Logs `hook fired` timestamp on every invocation
   - Captures `notify-send` stderr and exit code

**Current `~/.claude/notify-stop.sh`:**
```bash
#!/usr/bin/env bash

echo "$(date): hook fired" >> /tmp/claude-notify.log

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

notify-send \
    --app-name="Claude Code" \
    --icon=dialog-information \
    --expire-time=5000 \
    --urgency=normal \
    -r 9999 \
    "Claude Code" \
    "Waiting for your input." 2>> /tmp/claude-notify.log
echo "notify-send exit: $?" >> /tmp/claude-notify.log
```

**Resolved:** Notifications confirmed working after 2026-06-23 fixes.

---

## What to include when reporting a failure

1. Contents of `/tmp/claude-notify.log` — tells us if the hook is firing and if notify-send errors
2. Whether notifications worked recently and when they stopped
3. Whether you restarted Claude Code or rebooted between working and broken
