# Install ssh-llm-connect

<details>
<summary><strong>Claude Code</strong></summary>

### Install

```bash
claude plugin marketplace add cskwork/ssh-llm-connect
claude plugin install ssh-llm-connect@ssh-llm-connect
```

Type `/ssh-llm-connect`.

### Verify

```bash
claude plugin list
```

### Update

```bash
claude plugin marketplace update ssh-llm-connect
```

### Uninstall

```bash
claude plugin uninstall ssh-llm-connect
claude plugin marketplace remove ssh-llm-connect
```

</details>

<details>
<summary><strong>Codex</strong></summary>

### Install

```bash
codex plugin marketplace add cskwork/ssh-llm-connect --ref main
codex plugin add ssh-llm-connect@ssh-llm-connect
```

Type `$ssh-llm-connect`.

### Verify

```bash
codex plugin list
```

### Uninstall

```bash
codex plugin remove ssh-llm-connect
codex plugin marketplace remove ssh-llm-connect
```

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

### Install (extension, always-on)

```bash
gemini extensions install https://github.com/cskwork/ssh-llm-connect
```

### Install (command, opt-in)

```bash
mkdir -p ~/.gemini/commands
curl -fsSL https://raw.githubusercontent.com/cskwork/ssh-llm-connect/main/skills/ssh-llm-connect/agents/gemini.toml \
  -o ~/.gemini/commands/ssh-llm-connect.toml
```

Type `/ssh-llm-connect` in a new session.

### Verify

```bash
gemini extensions list
```

### Uninstall

```bash
gemini extensions uninstall ssh-llm-connect
```

</details>

<details>
<summary><strong>Cursor, OpenCode, Amp, and other agent-skills harnesses</strong></summary>

### Install

```bash
npx skills add cskwork/ssh-llm-connect
npx skills add cskwork/ssh-llm-connect -g
```

Type `/ssh-llm-connect` in a new agent chat.

### Verify

```bash
npx skills list
```

### Update

```bash
npx skills update ssh-llm-connect
```

### Uninstall

```bash
npx skills remove ssh-llm-connect
```

</details>

<details>
<summary><strong>Antigravity (agy)</strong></summary>

### Install

```bash
agy plugin install https://github.com/cskwork/ssh-llm-connect
```

### Verify

```bash
agy plugin list
```

### Uninstall

```bash
agy plugin uninstall ssh-llm-connect
```

</details>
