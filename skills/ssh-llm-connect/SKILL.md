---
name: ssh-llm-connect
description: ssh-llm-connect — safe SSH for agents to read remote logs. Use when: "ssh to prod", "read logs", "서버 봐야 함".
---


# ssh-llm-connect

Safe SSH for LLM coding agents.

## When to use
- Agent needs to read logs / ps / metrics / config on a remote host
- Agent must NOT be able to mutate the remote (production guardrails)
- User has run ./install.sh inside the project, so .claude/hooks/ssh-guard.sh
  and ssh/connect.sh exist

## What this skill does
Always invoke via `./ssh/connect.sh <host-slug> "<command>"`. Never `ssh`/`scp`/
`sftp` directly — the PreToolUse hook will reject and surface why.

If the command is refused by the read-only guard (Layer 3), do NOT add --allow-write
or --shell. Those are bypass flags reserved for humans and the hook will reject
them anyway. Instead, tell the user what was refused and ask them to run it
manually if it really must mutate.

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
  SSH_LOCAL_FORWARD=8080:127.0.0.1:8080    # optional

## Install (per project — run once per repo that needs SSH)
```bash
# from this repo
./install.sh /path/to/your/project
```
Copies `connect.sh` → `<project>/ssh/connect.sh`, host templates → `<project>/ssh/hosts/`,
the hook → `<project>/.claude/hooks/ssh-guard.sh`, appends `ssh/hosts/*.env` to `.gitignore`,
and prints a settings.json snippet for you to paste (it does not edit agent config itself).

## Failure modes
- Hook absent → bash command goes through unguarded. Refuse to ssh and ask the
  user to run ./install.sh first.
- Host slug typo → connect.sh errors with "no such .env". List ssh/hosts/*.env
  to the user.
- Read-only refusal → surface the rule that fired; do NOT retry with --allow-write.
