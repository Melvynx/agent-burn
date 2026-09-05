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

Live `summary --value --json` also includes an optional `cursorAccount` object.
`GetCurrentPeriodUsage` supplies included allowance and billing-cycle dates;
`GetUsageLimitStatusAndActiveGrants` supplies promotional grants and any reported
on-demand limit. Monetary fields are converted from cents to USD; absent amounts
remain null. Grant IDs and internal source labels are not retained in the output.
These balances are distinct from API-equivalent token costs.

The default usage window is the current billing cycle. Explicit `--since` and
`--until` bounds query earlier days; historical rows without token/cost amounts
cannot produce reconstructed spend. Account balances always describe the current
cycle, even when the usage report selects historical dates.
