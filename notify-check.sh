#!/usr/bin/env bash
# Checks that the Stop hook is registered in exactly one Claude settings file.

HOOK="notify-stop.sh"
SETTINGS_FILES=(
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
)

found=()
for f in "${SETTINGS_FILES[@]}"; do
    [[ -f "$f" ]] && grep -q "$HOOK" "$f" && found+=("$f")
done

echo "=== notify-stop hook check ==="

if [[ ${#found[@]} -eq 0 ]]; then
    echo "FAIL: hook not registered in any settings file"
    echo "      Add a Stop hook pointing to $HOME/.claude/$HOOK"
    exit 1
elif [[ ${#found[@]} -gt 1 ]]; then
    echo "WARN: hook registered in multiple files (will conflict):"
    for f in "${found[@]}"; do echo "      $f"; done
    echo "      Keep it only in settings.json; remove from settings.local.json"
    exit 1
else
    echo "OK:   hook registered in exactly one file: ${found[0]}"
fi

echo ""
echo "=== recent log (last 10 events) ==="
if [[ -f /tmp/claude-notify.log ]]; then
    tail -n 10 /tmp/claude-notify.log
else
    echo "No log yet — hook has not fired since last reboot."
fi
