# Agent Burn

Agent Burn is a local CLI for answering one question: is your coding-agent subscription paying for itself?

The public surface is intentionally small and centered on subscription-value reporting. The CLI keeps fast local log readers and cost aggregation logic, then exposes only two commands:

- `agent-burn summary` for an all-up local usage and cost overview.
- `agent-burn harness <claude|codex>` for focused weekly subscription-limit detail.

The npm package also installs `burn` as a short alias.

## Install

```bash
npx agent-burn@latest summary --value
pnpm dlx agent-burn@latest harness claude --value
bunx agent-burn@latest harness codex --value
```

## Commands

```bash
# Default overview. Running without a command is the same as summary.
agent-burn
agent-burn summary

# Quick date windows.
agent-burn summary today
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

`--value` compares local API-equivalent usage against known or supplied monthly subscription prices.

```bash
agent-burn summary --value
agent-burn summary --value --claude-plan max-20x --codex-plan pro
agent-burn harness claude --value --claude-plan 200
agent-burn harness codex --value --codex-plan plus
```

Supported plan overrides:

- Claude: `pro`, `max-5x`, `max-20x`, or a raw monthly price.
- Codex: `plus`, `pro`, or a raw monthly price.

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

## Development

The Rust CLI lives in the Rust workspace; the npm launcher and package metadata live in `apps/agent-burn`.

Useful direct commands when the Nix dev shell is unavailable:

```bash
cargo test --manifest-path rust/Cargo.toml --workspace
cargo build --manifest-path rust/Cargo.toml --release --bin agent-burn
node --test apps/agent-burn/src/cli.test.ts
```

## License

MIT
