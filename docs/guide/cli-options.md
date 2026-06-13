# CLI Options

## Commands

```bash
agent-burn summary [range]
agent-burn harness <claude|codex>
```

### Summary

`summary` aggregates detected local usage and optionally calculates subscription value.

```bash
agent-burn summary
agent-burn summary --value
agent-burn summary week --value
agent-burn summary --range month --json
```

Summary-specific options:

| Option | Description |
| --- | --- |
| `--range <today|wtd|mtd|ytd|week|month>` | Apply a quick date range |
| `--value` | Show subscription value |
| `--html` | Reserved for the HTML report follow-up |
| `--claude-plan <plan|price>` | Override Claude plan |
| `--codex-plan <plan|price>` | Override Codex plan |

### Harness

`harness` focuses on one subscription window.

```bash
agent-burn harness claude --value
agent-burn harness codex --value
agent-burn harness claude --json --offline
```

Harness-specific options:

| Option | Description |
| --- | --- |
| `--value` | Show API-equivalent value against the monthly plan |
| `--claude-plan <pro|max-5x|max-20x|price>` | Override Claude plan |
| `--codex-plan <plus|pro|price>` | Override Codex plan |

## Shared Options

| Option | Description |
| --- | --- |
| `--since <YYYYMMDD>` | Include usage on or after the date |
| `--until <YYYYMMDD>` | Include usage on or before the date |
| `--json` | Print JSON |
| `--jq <filter>` | Apply a jq filter to JSON |
| `--mode <auto|calculate|display>` | Cost mode |
| `--breakdown` | Include model breakdowns |
| `--offline` | Use embedded pricing and skip live requests |
| `--no-offline` | Force online pricing requests when supported |
| `--color` | Force color |
| `--no-color` | Disable color |
| `--timezone <tz>` | Group dates in a timezone |
| `--config <path>` | Load a config file |
| `--compact` | Force compact table layout |
| `--single-thread` | Disable parallel loading |
| `--no-cost` | Hide cost fields |
