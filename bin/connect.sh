#!/usr/bin/env bash
# ssh-llm-connect: multi-host SSH helper with readonly guard for LLM agents
# https://github.com/cskwork/ssh-llm-connect
#
# Usage:
#   connect.sh <host>                          # show usage
#   connect.sh <host> "<readonly command>"     # default: readonly-guarded
#   connect.sh --shell <host>                  # interactive shell (bypass, human only)
#   connect.sh --allow-write <host> "<cmd>"    # one-shot write allowed (human only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# hosts/ sits next to bin/ (repo layout) or as sibling of script (flat install)
if [[ -d "$SCRIPT_DIR/../hosts" ]]; then
  HOSTS_DIR="$(cd "$SCRIPT_DIR/../hosts" && pwd)"
elif [[ -d "$SCRIPT_DIR/hosts" ]]; then
  HOSTS_DIR="$SCRIPT_DIR/hosts"
else
  echo "Error: hosts directory not found (looked at $SCRIPT_DIR/../hosts, $SCRIPT_DIR/hosts)" >&2
  exit 1
fi

MODE=readonly
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)       MODE=shell;       shift ;;
    --allow-write) MODE=write;       shift ;;
    -h|--help)     MODE=help;        shift ;;
    *) break ;;
  esac
done

list_hosts() {
  echo "Available hosts:" >&2
  shopt -s nullglob
  local found=0
  for f in "$HOSTS_DIR"/*.env; do
    local name; name="$(basename "$f" .env)"
    [[ "$name" == _* ]] && continue
    echo "  - $name" >&2; found=1
  done
  [[ $found -eq 0 ]] && echo "  (none — copy $HOSTS_DIR/_template.env to <alias>.env)" >&2
}

if [[ "$MODE" == "help" || $# -lt 1 ]]; then
  cat >&2 <<EOF
Usage: connect.sh [--shell|--allow-write] <host> [remote command...]

Modes:
  (default)       readonly guard enforced — blocks rm/mv/sudo/redirects/etc.
  --shell         interactive shell (guard bypassed) — for human use
  --allow-write   one-shot write allowed (guard bypassed) — for human use

Hosts: configure under $HOSTS_DIR/
  cp $HOSTS_DIR/_template.env $HOSTS_DIR/<alias>.env

Examples:
  connect.sh prod-app "tail -100 /var/log/app.log"
  connect.sh --shell prod-app
EOF
  list_hosts
  [[ "$MODE" == "help" ]] && exit 0
  exit 1
fi

NAME="$1"; shift
ENV_FILE="$HOSTS_DIR/${NAME}.env"
[[ -f "$ENV_FILE" ]] || { echo "Error: $ENV_FILE not found" >&2; list_hosts; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SSH_HOST:?SSH_HOST required ($ENV_FILE)}"
: "${SSH_USER:?SSH_USER required ($ENV_FILE)}"

# ── readonly guard ─────────────────────
check_readonly() {
  local cmd="$*"

  if printf '%s' "$cmd" | grep -qE '(^|[^>2])>[^>|&]' ; then
    echo "BLOCK: '>' output redirect disallowed in readonly mode" >&2; return 1
  fi
  if printf '%s' "$cmd" | grep -qE '>>' ; then
    echo "BLOCK: '>>' append redirect disallowed in readonly mode" >&2; return 1
  fi

  local danger='(^|[[:space:];|&`(])(sudo|su|rm|mv|cp|dd|mkfs|fdisk|parted|chmod|chown|chgrp|truncate|ln|mkdir|rmdir|touch|kill|killall|pkill|reboot|shutdown|halt|poweroff|init|passwd|useradd|userdel|usermod|groupadd|groupdel|groupmod|mount|umount|iptables|firewall-cmd|service|crontab|tee|wall|write|nc|ncat|socat|wget|scp|rsync|eval|exec|source)([[:space:]]|$)'
  if printf '%s' "$cmd" | grep -qE "$danger" ; then
    echo "BLOCK: dangerous command in readonly mode" >&2
    echo "       cmd: $cmd" >&2
    return 1
  fi

  if printf '%s' "$cmd" | grep -qE 'curl[[:space:]].*(-X[[:space:]]+(POST|PUT|PATCH|DELETE)|--request[[:space:]]+(POST|PUT|PATCH|DELETE)|--data|--data-raw|--data-binary|--upload-file|-T[[:space:]]|-o[[:space:]]|-O[[:space:]])' ; then
    echo "BLOCK: curl write method (POST/PUT/PATCH/DELETE or -o/-O)" >&2; return 1
  fi

  if printf '%s' "$cmd" | grep -qE 'sed[[:space:]]+([^|;]*[[:space:]])?(-[a-zA-Z]*i|--in-place)' ; then
    echo "BLOCK: sed -i is a write operation" >&2; return 1
  fi

  if printf '%s' "$cmd" | grep -qE 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|edit|set-property|kill|daemon-reload)' ; then
    echo "BLOCK: systemctl write action" >&2; return 1
  fi

  if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+(push|commit|reset|clean|checkout|switch|rebase|merge|cherry-pick|stash|am|apply|tag[[:space:]]+[^-l]|branch[[:space:]]+-D)' ; then
    echo "BLOCK: git write action" >&2; return 1
  fi

  if printf '%s' "$cmd" | grep -qE '\b(apt|apt-get|dnf|yum|rpm|pip|pip3|npm|yarn|pnpm|brew|snap|gem|cargo)[[:space:]]+(install|upgrade|update|remove|uninstall|build|publish)' ; then
    echo "BLOCK: package manager write action" >&2; return 1
  fi

  if printf '%s' "$cmd" | grep -qE '(^|[[:space:];|&])(bash|sh|zsh|python3?|perl|ruby|node)[[:space:]]+-c[[:space:]]' ; then
    echo "BLOCK: interpreter -c arbitrary execution" >&2; return 1
  fi

  return 0
}

ARGS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
[[ -n "${SSH_PORT:-}" ]]          && ARGS+=(-p "$SSH_PORT")
[[ -n "${SSH_KEY_PATH:-}" ]]      && ARGS+=(-i "$SSH_KEY_PATH")
[[ -n "${SSH_PROXY_JUMP:-}" ]]    && ARGS+=(-J "$SSH_PROXY_JUMP")
[[ -n "${SSH_LOCAL_FORWARD:-}" ]] && ARGS+=(-L "$SSH_LOCAL_FORWARD")
[[ -n "${SSH_REMOTE_FORWARD:-}" ]]&& ARGS+=(-R "$SSH_REMOTE_FORWARD")
# shellcheck disable=SC2206
[[ -n "${SSH_EXTRA_OPTS:-}" ]]    && ARGS+=(${SSH_EXTRA_OPTS})

TARGET="${SSH_USER}@${SSH_HOST}"

case "$MODE" in
  shell)
    [[ $# -gt 0 ]] && { echo "Error: --shell does not accept remote command" >&2; exit 1; }
    echo "[WARN] --shell: readonly guard bypassed (interactive)" >&2
    ;;
  write)
    [[ $# -gt 0 ]] || { echo "Error: --allow-write requires a remote command" >&2; exit 1; }
    echo "[WARN] --allow-write: readonly guard bypassed" >&2
    echo "       cmd: $*" >&2
    ;;
  readonly)
    [[ $# -gt 0 ]] || { echo "Error: readonly mode requires a remote command. Use --shell for interactive." >&2; exit 1; }
    check_readonly "$@" || exit 2
    ;;
esac

if [[ -n "${SSH_PASSWORD:-}" ]]; then
  command -v sshpass >/dev/null || { echo "sshpass not installed (e.g. brew install hudochenkov/sshpass/sshpass)" >&2; exit 1; }
  exec sshpass -p "$SSH_PASSWORD" ssh "${ARGS[@]}" "$TARGET" "$@"
else
  exec ssh "${ARGS[@]}" "$TARGET" "$@"
fi
