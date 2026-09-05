# Agent Burn

Agent Burn is a native macOS app and local CLI for understanding coding-agent usage, limits, and subscription value.

The public surface is intentionally small and centered on subscription-value reporting. The CLI keeps fast local log readers and cost aggregation logic, then exposes only two commands:

- `agent-burn summary` for an all-up local usage and cost overview, including an easy day-by-day breakdown.
- `agent-burn harness <claude|codex>` for focused weekly subscription-limit detail, including spend split by input, output, and cache usage.

The npm package also installs `burn` as a short alias.

Site: [agent-burn.melvynx.dev](https://agent-burn.melvynx.dev)

## Install

**Mac app:** [Get Agent Burn](https://agent-burn.melvynx.dev/download), unzip it,
and move it to Applications when the public release is available. The first download
is awaiting Apple notarization. macOS 14+, Apple Silicon and Intel. The app includes
the CLI and supports signed Sparkle updates.

**CLI:**

```bash
npx agent-burn@latest summary --value
pnpm dlx agent-burn@latest harness claude --value
bunx agent-burn@latest harness codex --value
```

## Commands

### macOS app

The native macOS app provides a menu-bar popover with General, Codex, Claude, and Cursor
tabs, plus a full tabbed dashboard for usage across every detected harness. General
supports daily, WTD, MTD, YTD, rolling week/month ranges, and All time. Harness tabs include
available spend, models, daily charts, token breakdowns, and subscription details. It requires
macOS 14 or later. Build from the repository root with Xcode command-line tools,
the repository's Rust toolchain, and `just` available:

```bash
just macos::run
```

The build bundles the Rust CLI in `apps/macos/dist/Agent Burn.app`. This is a
locally signed development app. Public downloads are signed and notarized. Settings can select a
different native CLI executable, cached pricing, and the refresh interval.
The app follows the system appearance and uses native macOS toolbar tabs and tables.
A flame and quota percentage appear in the system menu bar.
**Settings → Appearance → Menu bar only** hides the Dock and Command-Tab entry
until disabled, and is remembered across launches. Codex sources include
`~/.codex` plus the launching profile; Settings can change the comma-separated
source folders. Complete aggregate reports are cached locally in
`~/Library/Application Support/Agent Burn/report-cache.json`.
Daily spend and token totals are retained without expiration in
`~/Library/Application Support/Agent Burn/metrics-history.json`, with an atomic
write and a previous-version `.bak` recovery file. The dashboard uses this archive
for date filters and charts, even after source logs disappear. Each day retains
the highest observed totals; partial deletions within a day can conceal subsequent
usage until it exceeds that total. This is a local archive, not an off-device backup.
Model and token-category tables describe available source data, not archived detail.
Cursor defaults to its current billing cycle. Explicit `--since` / `--until`
summary queries can retrieve older daily metrics where Cursor still supplies them.
With live `--value --json` reports, `cursorAccount` separates included allowance,
promotional credits, expiration dates, billing cycle and reported on-demand amounts.
Missing amounts remain unknown.
Quota readings are saved locally under
`~/Library/Application Support/Agent Burn/quota-history.json`. The forecast uses
average consumption during the current cycle; historical lines build as the app
refreshes. Missing provider limits remain unavailable. Summary amounts represent
API-equivalent usage, not subscription charges.

The [macOS source and release guide](https://github.com/Melvynx/agent-burn/tree/codex/macos-product-release/apps/macos)
documents builds, signing, notarization, and the open release process.

### CLI

```bash
# Default overview. Running without a command is the same as summary.
agent-burn
agent-burn summary

# Quick date windows.
agent-burn summary today
agent-burn summary yesterday
agent-burn summary week --value
agent-burn summary --range month --value

# Focused subscription harnesses.
agent-burn harness claude --value
agent-burn harness codex --value

# Machine-readable output.
agent-burn summary --json
agent-burn harness claude --json --offline
```

## Subscription Value

`--value` compares local API-equivalent usage against known or supplied monthly subscription prices. Harness output also shows a trailing-30-day spend mix so you can see which token classes drive the bill.

```bash
agent-burn summary --value
agent-burn summary --value --claude-plan max-20x --codex-plan pro
agent-burn harness claude --value --claude-plan 200
agent-burn harness codex --value --codex-plan plus
```

Supported plan overrides:

- Claude: `pro`, `max-5x`, `max-20x`, or a raw monthly price.
- Codex: `plus`, `pro`, or a raw monthly price.
- Cursor: `pro`, `pro+`, `ultra`, or a raw monthly price.

## Shared Options

Common options work on both commands:

```bash
--since <YYYYMMDD>       Start date
--until <YYYYMMDD>       End date
--json                   JSON output
--jq <filter>            Apply a jq filter to JSON output
--mode <auto|calculate|display>
--breakdown              Include model breakdowns
--offline                Use embedded pricing and skip live requests
--no-cost                Hide cost fields
--timezone <tz>          Date grouping timezone
--compact                Force compact table layout
--config <path>          Load a config file
```

## Data Sources

Agent Burn reads local logs and never uploads your data. The subscription harness is currently built around Claude Code and Codex because those are the sources with useful subscription-limit signals. The summary view still aggregates detected local usage from the inherited readers so your total agent spend remains visible.

Primary source locations:

| Source | Default location |
| --- | --- |
| Claude Code | `~/.claude`, `~/.config/claude/projects` |
| Codex | `${CODEX_HOME:-~/.codex}` |
| Cursor | Cursor `state.vscdb` plus the signed-in dashboard usage API |

## Development

The Rust CLI lives in the Rust workspace; the npm launcher and package metadata live in `apps/agent-burn`.

Useful direct commands when the Nix dev shell is unavailable:

```bash
cargo test --manifest-path rust/Cargo.toml --workspace
cargo build --manifest-path rust/Cargo.toml --release --bin agent-burn
node --test apps/agent-burn/src/cli.test.ts
```

## Release

After `npm login`, publish a new npm release for the current platform and the
main wrapper package with one command:

```bash
pnpm release:npm -- --bump patch --commit --push
```

Use `--dry-run` to validate the release without publishing.

## License

MIT
