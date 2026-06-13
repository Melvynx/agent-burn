# Configuration

Agent Burn can load JSON configuration files for defaults that you do not want to pass every time.

CLI arguments win over config file values.

```bash
agent-burn summary --config ./agent-burn.json --value
```

## Example

```json
{
  "$schema": "https://raw.githubusercontent.com/Melvynx/agent-burn/main/apps/agent-burn/config-schema.json",
  "defaults": {
    "timezone": "UTC",
    "mode": "auto",
    "offline": true
  }
}
```

Use [CLI Options](/guide/cli-options) for the supported public command surface.
