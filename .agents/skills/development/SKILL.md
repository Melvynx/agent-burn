---
name: development
description: Guides agent-burn monorepo development. Use when editing packages, docs, shared configuration, bundled CLI packaging, dependencies, exports, or validation commands.
---

# agent-burn Development

## Repository Shape

This is a monorepo. Check the nearest package-specific `AGENTS.md` before editing a package:

- `apps/agent-burn/AGENTS.md` - published Agent Burn CLI package
- `docs/AGENTS.md` - VitePress documentation site

The production CLI implementation is Rust-first under `rust/crates/agent-burn`.
The `apps/agent-burn` package now mainly provides npm metadata, a TypeScript bin
launcher, generated schema artifacts, benchmarks, and release packaging.

The canonical user-facing command is `agent-burn` with only two public commands:

```sh
agent-burn summary
agent-burn harness claude
agent-burn harness codex
```

Standalone agent wrapper packages and legacy report commands have been removed. Prefer `agent-burn summary` and `agent-burn harness <claude|codex>` in docs, tests, examples, and new behavior. Do not reintroduce wrapper commands such as `agent-burn-codex`, `agent-burn-opencode`, `agent-burn-amp`, or `agent-burn-pi`, and do not reintroduce `daily`, `weekly`, `monthly`, `session`, `blocks`, or `statusline` as public commands.

Agent implementations live in the Rust CLI unless the work is specifically about
the remaining TypeScript package surface. Treat package runtime libraries as
bundled assets: add dependencies to each package's `devDependencies` unless the
user explicitly asks otherwise.

## Common Commands

Use root commands unless a narrower package command is more appropriate. Read `references/commands.md` for root and main CLI command examples.

`LOG_LEVEL` controls logging verbosity from `0` silent through `5` trace.

## Environment and Tooling

Read `references/environment-and-validation.md` for direnv, tool management,
generated skill target rules, and post-change checks.

## Code Style

- For Rust CLI work, use the `rust` skill before editing `rust/crates/**`,
  native packaging behavior, or Rust pricing embedding. Use
  `profile` for Rust performance work.
- Keep Rust modules small and responsibility-focused. Prefer `pub(crate)` over
  broader visibility, avoid unnecessary `String` cloning in hot paths, and put
  unit tests beside the module they exercise.
- For TypeScript package/tooling code, use the `typescript` skill before
  editing. Keep `satisfies` and `as const satisfies` guidance there instead of
  mixing TypeScript details into Rust workflow rules.
- Only export constants, functions, and types used by other modules.
- Keep internal-only files and helpers private where possible.
- Dependency additions go in `devDependencies` for bundled/private packages.

## Post-Change Workflow

Read `references/environment-and-validation.md` for formatting, typecheck, and
test commands.

## Performance and CLI Output

Use `profile` for native CLI performance optimization, Rust profiling,
hyperfine A/B comparisons, branch-vs-main profiling, TypeScript launchers,
benchmarks, and packaging scripts.

Use the `cmux-debug` skill when validating terminal rendering, responsive tables, long-running CLI output, or output that depends on real terminal geometry.

## Commit and PR Names

Use the `commit` skill for commit structure, Conventional Commits, scope selection, and detailed commit message requirements.

Use the `create-pr` skill after opening a PR or pushing follow-up commits so AI and human review comments are requested, inspected, answered, and incorporated through small revertible commits.
