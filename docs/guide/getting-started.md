# Getting Started

Run the overview:

```bash
npx agent-burn@latest summary
```

Add subscription value:

```bash
npx agent-burn@latest summary --value
```

Focus on one subscription harness:

```bash
npx agent-burn@latest harness claude --value
npx agent-burn@latest harness codex --value
```

Running `agent-burn` without a command is the same as `agent-burn summary`.

## Date Ranges

Use a quick range:

```bash
agent-burn summary today
agent-burn summary week
agent-burn summary --range month
```

Or explicit bounds:

```bash
agent-burn summary --since 20260601 --until 20260613
```

## Plan Overrides

Agent Burn auto-detects some plan details from local data when possible. You can override them:

```bash
agent-burn summary --value --claude-plan max-20x --codex-plan pro
agent-burn harness claude --value --claude-plan 200
agent-burn harness codex --value --codex-plan plus
```
