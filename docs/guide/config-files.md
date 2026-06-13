# Configuration Files

Use `--config <path>` to load a specific JSON file:

```bash
agent-burn summary --config ./agent-burn.json --value
agent-burn harness claude --config ./agent-burn.json --json
```

The generated schema is published with the package at `apps/agent-burn/config-schema.json` and copied to `docs/public/config-schema.json` for the docs build.

## Suggested Local File

```json
{
  "defaults": {
    "timezone": "Europe/Zurich",
    "compact": false,
    "offline": false
  }
}
```
