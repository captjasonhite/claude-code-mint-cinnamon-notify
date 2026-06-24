# claude-code-mint-cinnamon-notify

Desktop notification when Claude Code finishes a response — for Linux Mint / Cinnamon users.

## What it does

Fires a standard desktop notification (via `notify-send`) every time Claude Code finishes generating a response. Useful when you've tabbed away and don't want to keep checking back.

> **Note:** The Stop hook fires whenever Claude finishes generating a response — whether it completed a task or is waiting for your next message. It does not distinguish between the two cases.

## Requirements

- Linux Mint with Cinnamon (also works on GNOME, KDE Plasma, XFCE, MATE)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `python3` (pre-installed on Linux Mint)

## Install

```bash
git clone https://github.com/captjasonhite/claude-code-mint-cinnamon-notify.git
cd claude-code-mint-cinnamon-notify
bash install.sh
```

Then **restart Claude Code**. The hook takes effect on the next launch.

## Verify it's working

After your next Claude response, a desktop notification should appear. If it doesn't, run the check script:

```bash
bash ~/.claude/notify-check.sh
```

This confirms the hook is registered in exactly one settings file and shows the recent log.

## How it works

Claude Code supports [Stop hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — shell commands that run whenever a response completes. The install script:

1. Copies `notify-stop.sh` to `~/.claude/notify-stop.sh`
2. Merges a `Stop` hook entry into `~/.claude/settings.json` (preserving any existing settings)

The script explicitly sets the D-Bus session address because Claude Code's hook subprocess doesn't inherit the desktop session environment — without this, `notify-send` silently fails. It checks for the standard systemd user bus socket first (`/run/user/<uid>/bus`), and if that's missing, falls back to scanning the running desktop environment process for its D-Bus address.

Each hook invocation uses its own process PID as the notification replacement ID, so notifications from concurrent Claude sessions don't stomp on each other.

## Uninstall

Remove the hook entry from `~/.claude/settings.json` and delete `~/.claude/notify-stop.sh`.

## Troubleshooting

**No notification** — `notify-send` may be failing silently. Test manually:
```bash
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
  notify-send "test" "test"
```

**Hook not firing at all** — check that `~/.claude/settings.json` contains the `Stop` hook entry and that `~/.claude/notify-stop.sh` is executable (`chmod +x`).

**Settings got overwritten** — Claude Code can rewrite `settings.json` in some situations. Re-run `bash install.sh` to re-register the hook without affecting your other settings.

**Hook duplicated in `settings.local.json`** — If you asked Claude to set up notifications, it may have added the hook to `~/.claude/settings.local.json` in addition to `settings.json`. The two can conflict and cause silent failures. Fix: open `~/.claude/settings.local.json` and remove the `hooks` block, leaving the hook only in `settings.json`. Then restart Claude Code.

**Diagnosing silently broken notifications** — run `bash ~/.claude/notify-check.sh`. It shows whether the hook is registered correctly and tails the recent log. Each log line is one event: if it appears, the hook ran; the `notify-send exit:` field tells you whether the desktop side succeeded. Exit 0 with no notification visible means the notification daemon is the problem, not the hook.
