# AGENTS.md - agent-burn Package

This is the published `agent-burn` npm package. The CLI implementation lives in Rust under `../../rust/crates/agent-burn`; this package provides the npm metadata, package runner launcher, and schema artifact.

## Skills

- Use `development` for commands, bundled CLI dependency policy, style, exports, and validation.
- Use `testing` for Rust cargo tests, Node tests, snapshots, fixtures, Claude models, and LiteLLM pricing tests.
- Use `agent-sources` for Claude Code data directories, JSONL structure, session naming, cost modes, and report behavior.
- Use `typescript` before reading or editing TypeScript or JavaScript package code.

## Package Notes

- Published bin launcher: `src/cli.js`
- Rust CLI implementation: `../../rust/crates/agent-burn`
- Fixture scripts: `scripts/generate-large-fixture.nu`

The package is distributed as the canonical native CLI. Keep the public surface centered on `agent-burn summary`, `agent-burn harness claude`, `agent-burn harness codex`, and stable `--json` output instead of library-style TypeScript exports.
