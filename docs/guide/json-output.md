# JSON Output

Use `--json` on either public command:

```bash
agent-burn summary --json
agent-burn summary --value --json
agent-burn harness claude --json
agent-burn harness codex --json
```

Use `--jq` to filter JSON directly:

```bash
agent-burn summary --json --jq '.totals'
agent-burn harness claude --json --jq '.window'
```

The JSON shape is intended for dashboards and scripts. Prefer command names `summary` and `harness`; old report names such as `daily`, `monthly`, `session`, `blocks`, and `statusline` are not part of Agent Burn.
