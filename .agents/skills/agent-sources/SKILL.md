---
name: agent-sources
description: Guides agent-burn agent source formats. Use when checking agent log locations, raw record structure, token mappings, model names, precomputed costs, or source-specific CLI behavior.
---

# agent-burn Agent Sources

Use this skill when inspecting source data formats, log paths, token
normalization, precomputed cost semantics, or source-specific command behavior
for any supported agent.

## Shared Report Concepts

Reports aggregate raw usage into the `summary` view or a focused subscription `harness` view and output either tables or JSON.

The canonical command surface is the focused `agent-burn` CLI:

```sh
agent-burn summary
agent-burn harness claude
agent-burn harness codex
```

Standalone agent wrapper packages and legacy report commands have been removed. Use `agent-burn summary` and `agent-burn harness <claude|codex>` in docs, tests, and examples. Do not reintroduce wrapper commands such as `agent-burn-codex`, `agent-burn-opencode`, `agent-burn-amp`, or `agent-burn-pi`, and do not reintroduce `daily`, `weekly`, `monthly`, `session`, `blocks`, or `statusline` as public commands.

Cost modes:

- `auto` - prefer pre-calculated `costUSD` when available, otherwise calculate from tokens.
- `calculate` - calculate from token counts and ignore pre-calculated costs.
- `display` - use pre-calculated costs and show `0` when missing.

Pricing generally comes from LiteLLM's `model_prices_and_context_window.json`. The `--offline` flag forces embedded pricing snapshots where supported.

## Agent Details

Read only the relevant adapter README before changing parser behavior, token
mappings, data directory detection, fallback models, or agent-specific CLI
flags:

- Claude Code: `rust/crates/agent-burn/src/adapter/claude/README.md`
- Codex: `rust/crates/agent-burn/src/adapter/codex/README.md`
- OpenCode: `rust/crates/agent-burn/src/adapter/opencode/README.md`
- Amp: `rust/crates/agent-burn/src/adapter/amp/README.md`
- pi-agent: `rust/crates/agent-burn/src/adapter/pi/README.md`

## Implementation Notes

Agent adapter architecture lives in
`rust/crates/agent-burn/src/adapter/AGENTS.md`. Read that local architecture file
when changing adapter module layout, shared implementation boundaries, migration
strategy, tests, docs, terminal output, or benchmark expectations.

Keep command names and flag semantics aligned across agents unless the source
data forces a difference.
