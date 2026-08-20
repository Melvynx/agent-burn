# Cursor

Cursor is included in the all-agent `summary` view, including `--chart` and `--html`. It is not a `harness` target.

```bash
agent-burn summary --value --cursor-plan ultra
agent-burn summary --chart --html
agent-burn summary --json --offline
```

`--offline` skips Cursor's dashboard RPC and reports no Cursor rows. Agent Burn does not read chat bodies from `state.vscdb`.

## Data source

Agent Burn reads the signed-in Cursor session from the local state database, then loads day-by-model usage from Cursor's dashboard API.

Default state database:

| Platform | Path |
| --- | --- |
| macOS | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Linux | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Windows | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` |

Overrides:

- `CURSOR_DATA_DIR` — Cursor application-support directory, `globalStorage` directory, or a `state.vscdb` file
- `CURSOR_ACCESS_TOKEN` — session token, for tests or unusual installs

Usage rows come from `GetAggregatedUsageEvents` on `api2.cursor.sh`. Each row is a day × model aggregate (input, output, cache write, cache read, optional native cents). Without `--since`, Cursor uses the current billing cycle when the API reports it, otherwise the last 31 days.

## Plan overrides

Detected from `cursorAuth/stripeMembershipType` when present:

```bash
agent-burn summary --value --cursor-plan pro
agent-burn summary --value --cursor-plan pro+
agent-burn summary --value --cursor-plan ultra
agent-burn summary --value --cursor-plan 200
```
