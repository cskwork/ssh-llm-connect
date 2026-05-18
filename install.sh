#!/usr/bin/env bash
# ssh-llm-connect installer
#
# Usage:
#   ./install.sh                       # install into current working directory
#   ./install.sh /path/to/project      # install into given project
#   ./install.sh --print-settings      # print Claude Code settings.json snippet only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRINT_ONLY=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-settings) PRINT_ONLY=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done

TARGET="${TARGET:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"

print_settings_snippet() {
  local hook_path="$1"
  cat <<JSON
{
  "permissions": {
    "deny": [
      "Bash(./ssh/connect.sh --shell*)",
      "Bash(./ssh/connect.sh --allow-write*)",
      "Bash(ssh/connect.sh --shell*)",
      "Bash(ssh/connect.sh --allow-write*)",
      "Bash(bash ./ssh/connect.sh --shell*)",
      "Bash(bash ./ssh/connect.sh --allow-write*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$hook_path" }
        ]
      }
    ]
  }
}
JSON
}

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  print_settings_snippet "$TARGET/.claude/hooks/ssh-guard.sh"
  exit 0
fi

echo "== ssh-llm-connect installer =="
echo "Target project: $TARGET"
echo

# 1) connect.sh + hosts/
mkdir -p "$TARGET/ssh/hosts"
cp -v "$SCRIPT_DIR/bin/connect.sh"           "$TARGET/ssh/connect.sh"
cp -nv "$SCRIPT_DIR/hosts/_template.env"     "$TARGET/ssh/hosts/_template.env"
chmod +x "$TARGET/ssh/connect.sh"

# 2) PreToolUse hook
mkdir -p "$TARGET/.claude/hooks"
cp -v "$SCRIPT_DIR/hooks/ssh-guard.sh"       "$TARGET/.claude/hooks/ssh-guard.sh"
chmod +x "$TARGET/.claude/hooks/ssh-guard.sh"

# 3) .gitignore (append-safe)
GI="$TARGET/.gitignore"
touch "$GI"
for pat in '/ssh/hosts/*.env' '!/ssh/hosts/_template.env'; do
  grep -qxF "$pat" "$GI" || echo "$pat" >> "$GI"
done
echo "  + .gitignore updated"

echo
echo "== Done. =="
echo
echo "Next steps:"
echo "  1) Register a host:"
echo "       cp $TARGET/ssh/hosts/_template.env $TARGET/ssh/hosts/<alias>.env"
echo "       # then edit it"
echo
echo "  2) Add the following to $TARGET/.claude/settings.json"
echo "     (merge with existing content if present):"
echo
print_settings_snippet "$TARGET/.claude/hooks/ssh-guard.sh" | sed 's/^/     /'
echo
echo "  3) Test:"
echo "       $TARGET/ssh/connect.sh <alias> \"hostname && date\""
echo
echo "  4) Restart Claude Code / new session for the hook to load."
