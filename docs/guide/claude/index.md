# Claude Code

Claude Code is one of the two primary Agent Burn subscription harnesses.

```bash
agent-burn harness claude --value
agent-burn harness claude --json --offline
agent-burn summary --value --claude-plan max-20x
```

Agent Burn reads local Claude Code usage files from the standard Claude directories and can use live limit data when credentials are available. Use `--offline` when you want a purely local run with embedded pricing.

Plan overrides:

```bash
agent-burn harness claude --value --claude-plan pro
agent-burn harness claude --value --claude-plan max-5x
agent-burn harness claude --value --claude-plan max-20x
agent-burn harness claude --value --claude-plan 200
```
