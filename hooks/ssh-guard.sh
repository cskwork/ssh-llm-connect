#!/usr/bin/env bash
# ssh-llm-connect: Claude Code PreToolUse hook (Bash matcher)
# Enforces SSH channel: blocks direct ssh/scp/sftp + connect.sh bypass flags.
#
# Behavior:
#   1) Reject direct ssh/scp/sftp/sshpass (allow ssh-keyscan/keygen/add/copy-id)
#      → forces use of ./ssh/connect.sh
#   2) Reject ./ssh/connect.sh --shell / --allow-write
#   3) Pass through everything else (connect.sh internal guard validates remote cmds)
#
# Exit codes (Claude Code spec):
#   0 = allow
#   2 = block (stderr is shown to the LLM and user)

set -euo pipefail

input="$(cat)"

cmd="$(printf '%s' "$input" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("tool_input", {}).get("command", ""))
')" || exit 0

[[ -z "$cmd" ]] && exit 0

# 1) connect.sh bypass flags
if printf '%s' "$cmd" | grep -qE 'connect\.sh[[:space:]]+--(shell|allow-write)\b'; then
  cat >&2 <<EOF
[SSH GUARD] connect.sh --shell / --allow-write blocked
            requested: $cmd
            alternative: ./ssh/connect.sh <host> "<readonly command>"
            For interactive sessions / write ops, use your own terminal.
EOF
  exit 2
fi

# 2) Direct ssh/scp/sftp/sshpass — allow only via connect.sh; allow utility tools
if printf '%s' "$cmd" | grep -qE '(^|[[:space:];|&`(])(ssh|scp|sftp|sshpass)([[:space:]]|$)' \
   && ! printf '%s' "$cmd" | grep -qE '\bssh-(keyscan|keygen|add|copy-id)\b'; then
  if printf '%s' "$cmd" | grep -qE '(\./)?ssh/connect\.sh\b'; then
    exit 0
  fi
  cat >&2 <<EOF
[SSH GUARD] direct ssh/scp/sftp/sshpass blocked
            requested: $cmd
            alternative: ./ssh/connect.sh <host-alias> "<readonly command>"
            Hosts are registered under ssh/hosts/*.env
EOF
  exit 2
fi

exit 0
