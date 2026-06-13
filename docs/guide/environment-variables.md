# Environment Variables

Agent Burn inherits the local data-directory detection from the upstream readers.

Common variables:

| Variable | Purpose |
| --- | --- |
| `CLAUDE_CONFIG_DIR` | Override Claude Code config/log root |
| `CODEX_HOME` | Override Codex home directory |
| `LOG_LEVEL=0` | Silence progress output in automation |

Example:

```bash
CODEX_HOME=/tmp/codex agent-burn harness codex --json
CLAUDE_CONFIG_DIR=/tmp/claude agent-burn harness claude --offline
```
