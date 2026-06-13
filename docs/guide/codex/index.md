# Codex

Codex is one of the two primary Agent Burn subscription harnesses.

```bash
agent-burn harness codex --value
agent-burn harness codex --json --offline
agent-burn summary --value --codex-plan pro
```

Agent Burn reads Codex data from `${CODEX_HOME:-~/.codex}`. The harness uses the local plan snapshot when available to estimate weekly-limit burn and subscription value.

Plan overrides:

```bash
agent-burn harness codex --value --codex-plan plus
agent-burn harness codex --value --codex-plan pro
agent-burn harness codex --value --codex-plan 200
```
