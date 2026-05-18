# ssh-llm-connect

Safe SSH for LLM coding agents. Multi-host helper + read-only command guard + harness-enforced hook that prevents the agent from bypassing it.

## Why

LLM coding agents (Claude Code, Cursor, etc.) can issue arbitrary shell commands. Connecting to remote servers via plain `ssh user@host "rm -rf ..."` is a single mistake away from disaster. This repo gives you:

1. A small connection helper (`connect.sh`) that loads per-host `.env` files so the agent never sees credentials inline.
2. A read-only command guard inside the helper that refuses dangerous commands (`rm`, `mv`, `sudo`, `>`, `>>`, `systemctl restart`, `curl -X POST`, package installs, interpreters with `-c`, etc.).
3. A Claude Code **PreToolUse hook** (`ssh-guard.sh`) that the harness runs *before* every Bash call. It blocks the agent from calling `ssh` / `scp` / `sftp` directly or from passing bypass flags to the helper — enforcement that the agent cannot rewrite away.

## What it is NOT

- **Not a sandbox.** It cannot stop a malicious actor with root on the client. It cannot stop server-side compromise.
- **Not a replacement for server-side hardening.** For real isolation, combine with `ForceCommand` in `~/.ssh/authorized_keys`, `rbash`, or a dedicated read-only SSH user.

It is "guardrails against honest mistakes by an AI agent." That alone is worth a lot.

## Install

```bash
git clone https://github.com/<owner>/ssh-llm-connect.git
cd ssh-llm-connect
./install.sh /path/to/your/project
```

The installer:

- copies `bin/connect.sh` → `<project>/ssh/connect.sh`
- copies `hosts/_template.env` → `<project>/ssh/hosts/_template.env`
- copies `hooks/ssh-guard.sh` → `<project>/.claude/hooks/ssh-guard.sh`
- appends `/ssh/hosts/*.env` to `<project>/.gitignore` so credentials never get committed
- prints a snippet for `<project>/.claude/settings.json` (you paste it — the installer does not edit your agent config)

## Add a host

```bash
cp ssh/hosts/_template.env ssh/hosts/prod-app.env
$EDITOR ssh/hosts/prod-app.env
```

Minimum fields:

```env
SSH_HOST=10.0.0.10
SSH_PORT=22
SSH_USER=deploy
SSH_KEY_PATH=~/.ssh/id_ed25519        # OR SSH_PASSWORD=... (sshpass required)
```

Optional: `SSH_PROXY_JUMP`, `SSH_LOCAL_FORWARD`, `SSH_REMOTE_FORWARD`, `SSH_EXTRA_OPTS`.

## Use

```bash
# default — read-only enforced
./ssh/connect.sh prod-app "tail -100 /var/log/app.log"
./ssh/connect.sh prod-app "ps aux | grep java"

# refused
./ssh/connect.sh prod-app "rm /tmp/x"
./ssh/connect.sh prod-app "echo hi > /tmp/x"
./ssh/connect.sh prod-app "systemctl restart app"

# bypass (human only — agents are blocked by the hook)
./ssh/connect.sh --shell prod-app
./ssh/connect.sh --allow-write prod-app "systemctl restart app"
```

## How the hook works

`ssh-guard.sh` is a Claude Code [PreToolUse hook](https://docs.claude.com/en/docs/claude-code/hooks) on the `Bash` matcher. The Claude Code harness runs it before every Bash tool invocation. If the hook exits with code `2`, the Bash call is rejected before it runs and the stderr is shown to the agent.

What the hook rejects:

- Any direct `ssh`, `scp`, `sftp`, or `sshpass` call (except `ssh-keyscan` / `ssh-keygen` / `ssh-add` / `ssh-copy-id` which are local utilities).
- Any `connect.sh --shell` or `connect.sh --allow-write` invocation.

Everything else falls through to the helper's own `check_readonly` function.

## Defense layers

| Layer | Enforced by | Blocks |
|---|---|---|
| 1 — PreToolUse hook | Claude Code harness (cannot be bypassed by agent) | direct ssh/scp/sftp, bypass flags |
| 2 — `permissions.deny` in `settings.json` | Claude Code harness | bypass flags (belt + suspenders with the hook) |
| 3 — `connect.sh` read-only guard | the helper script | rm/sudo/redirect/systemctl write/curl POST/package installers/interpreter `-c` |
| 4 — server-side (you provide) | `sshd_config` / authorized_keys | everything else |

## Read-only command rules (layer 3)

Refused: `sudo su rm mv cp dd mkfs fdisk parted chmod chown chgrp truncate ln mkdir rmdir touch kill killall pkill reboot shutdown halt poweroff init passwd useradd userdel usermod groupadd groupdel groupmod mount umount iptables firewall-cmd service crontab tee wall write nc ncat socat wget scp rsync eval exec source`, `> redirect`, `>> append`, `sed -i`, `systemctl start|stop|restart|reload|enable|disable|mask|unmask|edit|set-property|kill|daemon-reload`, `git push|commit|reset|clean|checkout|switch|rebase|merge|cherry-pick|stash|am|apply`, `apt|apt-get|dnf|yum|rpm|pip|pip3|npm|yarn|pnpm|brew|snap|gem|cargo install|upgrade|update|remove|uninstall|build|publish`, `curl -X POST|PUT|PATCH|DELETE | -o | -O | --data`, `bash|sh|zsh|python|perl|ruby|node -c "..."`.

Allowed (by being not refused): `cat ls grep awk sed (no -i) head tail wc sort uniq cut tr find which env echo printenv date uptime free df du ps top netstat ss ip ifconfig hostname uname id whoami journalctl(read) systemctl status git log|status|diff|show docker ps|logs kubectl get|describe|logs` and more.

## Limitations and threat model

- **Pattern-based.** A determined attacker who controls the client can encode payloads, use base64/eval tricks, or call a different binary. The hook narrows the surface; it does not eliminate it.
- **Client-side only.** Run an `ssh-guard`-aware harness for layers 1–2; everything else is at layer 3 (local script). For server-side enforcement use a restricted shell or `ForceCommand`.
- **Bash channel only.** If the agent's harness allows non-Bash network primitives (Python `paramiko`, etc.), this hook does not see them. Deny those in your agent settings separately.
- **Hooks must be registered manually.** The installer does not write to `settings.json` — that file controls agent permissions and the installer refuses to modify it silently. You paste the snippet yourself.

## License

MIT — see [LICENSE](LICENSE).
