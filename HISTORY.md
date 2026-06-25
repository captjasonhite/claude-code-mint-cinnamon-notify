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

---

### 2026-06-24 — Multi-session stomping + hardening

**Symptoms:** Second Claude Code session (same folder, started 5 min earlier) never notified. First session worked fine.

**Diagnosed:**
- Both sessions used `-r 9999`, so the second session to fire replaced the first session's notification
- Hook was firing and `notify-send` exiting 0 in both sessions — confirmed via log
- Silent because identical replacement ID made one session's notifications invisible

**Changes made:**
1. Replaced `-r 9999` with `-r "$$"` (bash PID of the hook subprocess) — each invocation gets a unique notification slot, concurrent sessions can't stomp each other
2. Consolidated log to one line per event: `timestamp [pid]: hook fired | notify-send exit: N` with stderr inline if present
3. Added `notify-check.sh` — scans all Claude settings files, confirms hook is registered in exactly one place, tails recent log; install script now deploys it to `~/.claude/notify-check.sh`

**Resolved:** Both sessions notify independently.

---

### 2026-06-24 (evening) — hook fires but notifications still don't appear

**Symptoms:** Hook fires (log confirms it, `stop_hook_summary` present in JSONL for 2.1.191), notify-send exits 0, nothing visible on screen. Recurring pattern matching 2026-06-23.

**Diagnosed:**
- Hook IS firing — confirmed via `/tmp/claude-notify.log` and `stop_hook_summary` in session JSONL
- `notify-send` exits 0 even when Cinnamon notification daemon is dead/unresponsive — this is a libnotify behavior, not a bug in the script
- `gdbus call GetServerInformation` reliably fails when daemon is dead; `notify-send` does not report this
- DND settings (`display-notifications`, `show-banners`) were both `true` at time of check
- `--urgency=normal` can be suppressed by Cinnamon focus/applet state; `critical` bypasses this

**Changes made to `~/.claude/notify-stop.sh`:**
1. Added `gdbus call GetServerInformation` health check before sending — logs `DAEMON DEAD` explicitly when daemon is unresponsive; previously this silent failure looked identical to success
2. Changed `--urgency=normal` → `--urgency=critical` — harder for Cinnamon to suppress silently
3. Increased `--expire-time` 5000 → 8000 ms

**Current `~/.claude/notify-stop.sh`:**
```bash
#!/usr/bin/env bash

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
    -r "$$" \
    "Claude Code" \
    "Waiting for your input." 2>&1)"
notify_exit=$?

echo "$(date) [$$]: hook fired | notify-send exit: ${notify_exit}${notify_err:+ | err: ${notify_err}}" >> /tmp/claude-notify.log
```

**Root cause still unresolved.** If `DAEMON DEAD` appears in log next time, that confirms Cinnamon's notification applet is crashing periodically. Recovery: right-click taskbar → Troubleshoot → Restart Cinnamon, or `killall -HUP cinnamon`.

---

## What to include when reporting a failure

1. Contents of `/tmp/claude-notify.log` — tells us if hook fired, if daemon was dead, or if notify-send errored
2. Whether notifications worked recently and when they stopped
3. Whether you restarted Claude Code or rebooted between working and broken
