# Cursor Source

Data source:

- Application support directory (override with `CURSOR_DATA_DIR`):
  - macOS: `~/Library/Application Support/Cursor`
  - Linux: `~/.config/Cursor`
  - Windows: `%APPDATA%\Cursor`
- Auth token from `User/globalStorage/state.vscdb` → `cursorAuth/accessToken`
  (override with `CURSOR_ACCESS_TOKEN`)
- Daily usage from Cursor's dashboard RPC
  `aiserver.v1.DashboardService/GetAggregatedUsageEvents` on `api2.cursor.sh`

Each RPC row is a day × model aggregate with `inputTokens`, `outputTokens`,
`cacheWriteTokens`, `cacheReadTokens`, and optional `totalCents`. `--offline`
skips the network fetch and reports no Cursor rows.

Plan detection uses `cursorAuth/stripeMembershipType` (`pro`, `pro+`, `ultra`)
or `--cursor-plan`. Cursor is a summary source only; `harness cursor` is not
supported.

Public CLI flow:

```sh
agent-burn summary
agent-burn summary --value --cursor-plan ultra
agent-burn summary --chart --html
```
