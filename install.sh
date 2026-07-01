#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SCRIPT_DEST="$CLAUDE_DIR/notify-stop.sh"
CHECK_DEST="$CLAUDE_DIR/notify-check.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# If the deployed script was hand-edited (a hotfix that never made it back into
# the repo), back it up instead of silently clobbering it.
for pair in "$SCRIPT_DIR/notify-stop.sh:$SCRIPT_DEST" "$SCRIPT_DIR/notify-check.sh:$CHECK_DEST"; do
    src="${pair%%:*}"
    dest="${pair##*:}"
    if [[ -f "$dest" ]] && ! diff -q "$src" "$dest" >/dev/null 2>&1; then
        backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
        cp "$dest" "$backup"
        echo "NOTE: $dest differed from repo copy — backed up to $backup"
    fi
done

cp "$SCRIPT_DIR/notify-stop.sh" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

cp "$SCRIPT_DIR/notify-check.sh" "$CHECK_DEST"
chmod +x "$CHECK_DEST"

if [[ -f "$SETTINGS" ]]; then
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
fi

python3 - "$SETTINGS" "$SCRIPT_DEST" <<'EOF'
import sys, json, os

settings_path = sys.argv[1]
script_path = sys.argv[2]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hook_entry = {
    "matcher": "",
    "hooks": [{"type": "command", "command": script_path}]
}

settings.setdefault("hooks", {}).setdefault("Stop", [])

# Remove duplicates before adding
settings["hooks"]["Stop"] = [
    h for h in settings["hooks"]["Stop"]
    if not any(c.get("command") == script_path for c in h.get("hooks", []))
]
settings["hooks"]["Stop"].append(hook_entry)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"Hook registered in {settings_path}")
EOF

echo ""
echo "Done. Restart Claude Code for the hook to take effect."
echo "To verify: bash $CHECK_DEST"
