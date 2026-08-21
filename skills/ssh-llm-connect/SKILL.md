---
name: ssh-llm-connect
description: 'ssh-llm-connect — safe SSH for agents to read remote logs. Use when: "ssh to prod", "read the server logs", "서버 봐야 함", or when a remote host must stay read-only.'
---

# ssh-llm-connect

## When to use
- Agent needs to read logs / ps / metrics / config on a remote host
- Remote must stay read-only (production guardrails)

## Before the first remote command
Confirm the guard is installed and registered:
```bash
ls ssh/connect.sh .claude/hooks/ssh-guard.sh && grep -l ssh-guard.sh .claude/settings*.json
```
If either check fails, treat the Bash channel as unguarded — say so and have the user
run `install.sh` (below) before any SSH.

## Running commands
Every remote command goes through `./ssh/connect.sh <host-slug> "<command>"`, which
enforces the read-only guard (Layer 3). The PreToolUse hook rejects `ssh`/`scp`/`sftp`
called directly and surfaces why.

When the guard refuses a command, relay the rule that fired and ask the user to run it
from their own terminal. `--allow-write` and `--shell` are human-only bypass flags — the
hook rejects them from the agent.

An unknown slug makes connect.sh print `Error: <path> not found` and list the registered
host slugs; pick from that list.

## Defense layers
| Layer | Enforced by                  | Blocks |
| ----- | ---------------------------- | --------------------------------------------------------- |
| 1     | PreToolUse hook (harness)    | direct ssh/scp/sftp, bypass flags |
| 2     | permissions.deny in settings | bypass flags (belt + suspenders) |
| 3     | connect.sh read-only guard   | rm/sudo/redirect/systemctl write/curl POST/pkg install/-c |
| 4     | server-side (user provides)  | everything else |

## Read-only command rules (Layer 3, summary)
Refused: sudo, su, rm, mv, cp, dd, mkfs, chmod, chown, kill, reboot, passwd,
useradd, mount, iptables, crontab, tee, wget, scp, rsync, eval, exec, source,
`>`, `>>`, `sed -i`, systemctl write subcommands, git push|commit|reset|clean|
checkout|switch|rebase|merge, package managers install|upgrade|update|remove,
curl -X POST|PUT|PATCH|DELETE | -o | -O | --data, language interpreters with -c.

Allowed (by being not refused): cat, ls, grep, awk, sed (no -i), head, tail, wc,
sort, uniq, cut, tr, find, which, env, echo, date, uptime, free, df, du, ps,
top, netstat, ss, ip, hostname, uname, id, whoami, journalctl (read), systemctl
status, git log|status|diff|show, docker ps|logs, kubectl get|describe|logs.

## Host config
ssh/hosts/<slug>.env:
  SSH_HOST=10.0.0.10
  SSH_PORT=22
  SSH_USER=deploy
  SSH_KEY_PATH=~/.ssh/id_ed25519           # or SSH_PASSWORD=... (needs sshpass)
  SSH_PROXY_JUMP=jumpbox                   # optional
  SSH_LOCAL_FORWARD=8080:127.0.0.1:8080    # optional (also SSH_REMOTE_FORWARD, SSH_EXTRA_OPTS)

## Install (per project — run once per repo that needs SSH)
```bash
git clone https://github.com/cskwork/ssh-llm-connect.git
./ssh-llm-connect/install.sh /path/to/your/project
```
Copies `connect.sh` → `<project>/ssh/connect.sh`, `_template.env` → `<project>/ssh/hosts/`,
the hook → `<project>/.claude/hooks/ssh-guard.sh`, gitignores `/ssh/hosts/*.env`, and prints a
settings.json snippet for you to paste (it does not edit agent config itself).
