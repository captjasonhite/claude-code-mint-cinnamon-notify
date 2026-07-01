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

### 2026-06-29 — Fix notification stacking + add audio bell

**Symptoms:** Multiple notifications stacking up, each requiring individual dismissal. No audio alert.

**Changes made to `~/.claude/notify-stop.sh`:**
1. Changed `-r "$$"` → `-r "$PPID"` — uses the Claude Code parent process PID as the notification ID; same session replaces its own notification rather than stacking, while multiple sessions still get independent slots
2. Added `paplay /usr/share/sounds/freedesktop/stereo/bell.oga` via PipeWire — plays audible bell on each stop event
   - Terminal tty approach failed: Claude Code's Node.js process has `tty_nr=0` (no controlling terminal), so `/proc/$PPID/fd/1` is a pipe, not a tty
   - `XDG_RUNTIME_DIR` must be set explicitly for paplay to find PipeWire socket

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
    -r "$PPID" \
    "Claude Code" \
    "Waiting for your input." 2>&1)"
notify_exit=$?

# Play a sound via PipeWire/PulseAudio
export XDG_RUNTIME_DIR="/run/user/$uid"
paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null &

echo "$(date) [$$]: hook fired | notify-send exit: ${notify_exit}${notify_err:+ | err: ${notify_err}}" >> /tmp/claude-notify.log
```

---

### 2026-07-01 — Fix multi-notification stacking (root cause of "-r PPID" fix not working)

**Symptoms:** Jason had to close 4-5 stacked notifications instead of one. The 2026-06-29 fix (`-r "$PPID"`) was supposed to make repeat Stop events in the same session replace each other, but it didn't actually work.

**Root cause:** `$PPID` inside the hook script is the immediate parent shell that Claude Code spawns to run the hook command. That parent process is re-created on every hook invocation, so its PID is *not* stable across Stop events within the same session — `-r "$PPID"` behaved almost like a random ID every time, so notifications kept stacking instead of replacing. Confirmed via `claude-code-guide` subagent + docs (https://code.claude.com/docs/en/hooks.md): Claude Code passes a JSON payload on **stdin** to hooks that includes a `session_id` field, which *is* stable for the lifetime of one session and differs across concurrent sessions.

**Changes made to `~/.claude/notify-stop.sh`:**
1. Read stdin JSON (`hook_input="$(cat)"`), extract `session_id` via a small inline Python snippet (falls back to `$PPID` if parsing fails/empty)
2. Hash `session_id` with `cksum`, mod `2147483647` (notify-send's `-r` rejects values above `INT32_MAX` — hit this immediately in testing: `Integer value "…" for -r out of range`) to get a stable per-session notification ID
3. Use that hashed ID for `-r` instead of `$PPID`
4. Log now includes `session=<id> id=<hash>` for future debugging

**Verified:** two calls with the same fake `session_id` on stdin produced the same hashed id and replaced each other; a different `session_id` produced a different id and notified independently.

**Note:** if Jason runs multiple concurrent Claude Code sessions, each session still gets its own notification (by design) — that's not stacking, that's one active session = one active notification.

---

### 2026-07-01 (later) — Richer notification body: project, time, elapsed

**Request:** Jason wanted the notification body changed from generic "Waiting for your input." to `Ready for input - <project name> - <current time> - <elapsed time of last prompt>`.

**Changes made to `~/.claude/notify-stop.sh`:**
1. Extract `cwd` from the hook's stdin JSON, derive `project` as `basename(cwd)`
2. Compute elapsed time: `tail -n 2000` the session's `transcript_path` (also from stdin JSON), find the last JSONL entry with `type == "user"` and a plain-string `message.content` (this excludes tool_result entries, which are also `type: "user"` in the transcript but have list content) — that's the last real user prompt. Diff its `timestamp` against now, format as `Xs` / `XmYYs` / `XhYYm`
3. Built `notify_body="Ready for input - ${project} - ${current_time} - ${elapsed}"`, current_time via `date +"%-I:%M %p"`
4. `tail -n 2000` (not reading the whole transcript) keeps this fast even on long sessions — the last real prompt is always near the end since the hook fires right after processing it

**Verified:** ran the script with a real session's `transcript_path`, confirmed it correctly found the last prompt timestamp and computed ~84s elapsed, and correctly derived project name from `cwd`.

---

### 2026-07-01 (final) — Reorder body, drop "Ready for input" prefix

Jason asked for field order `<current time> - <project name> - <elapsed time> - Idle` instead. `notify_body` is now:

```bash
notify_body="${current_time} - ${project} - ${elapsed} - Idle"
```

e.g. `1:43 PM - Apps - 1m24s - Idle`.

---

### 2026-07-01 (review pass) — reliability hardening after code review

Jason asked for a design/reliability review of the whole notify setup, then to fix everything found.

**Changes made to `notify-stop.sh`:**
1. Wrapped both `gdbus call GetServerInformation` and `notify-send` in `timeout 5` — previously a wedged (not dead) session bus could hang either call indefinitely, blocking the Stop hook (and Claude Code) instead of failing fast
2. Elapsed-time lookup now falls back to a much wider `tail` (200000 lines) if the last real user prompt isn't found in the first 2000 — tool-heavy sessions could push the last prompt outside the original small window, silently showing `?`
3. `paplay` is now also `disown`ed (in addition to backgrounding with `&`) and wrapped in `timeout 5`, so it can't be killed early if the hook's process group is torn down right after the script exits, and can't hang the script
4. Added log rotation: `/tmp/claude-notify.log` is truncated to the last 1000 lines once it exceeds 5000, so it doesn't grow unbounded across long uptimes

**Changes made to `install.sh`:**
1. Before overwriting `~/.claude/notify-stop.sh` or `notify-check.sh`, diffs the deployed copy against the repo copy — if they differ (e.g. a hand-edited hotfix that never made it back into the repo), backs it up to `<file>.bak.<timestamp>` instead of silently clobbering it
2. Backs up `~/.claude/settings.json` to `settings.json.bak.<timestamp>` before rewriting it

**Changes made to `notify-check.sh`:**
1. Added a "deployed vs repo drift" check comparing `~/Apps/claude-desktop-notify/notify-stop.sh` against `~/.claude/notify-stop.sh`, so drift is visible without having to diff manually

**Verified:** ran `notify-stop.sh` with a synthetic stdin payload (fake `session_id`, transcript with a timestamped user entry) — logged correctly with exit 0. Ran `install.sh`, confirmed it detected the then-current deployed copies differed from the just-updated repo copies and backed them up before overwriting. Ran `notify-check.sh` after — hook registered once, deployed script now matches repo, log intact.

---

## What to include when reporting a failure

1. Contents of `/tmp/claude-notify.log` — tells us if hook fired, if daemon was dead, or if notify-send errored
2. Whether notifications worked recently and when they stopped
3. Whether you restarted Claude Code or rebooted between working and broken
