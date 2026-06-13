# agent-burn Commands

`just` is the single entry point for repo-wide tasks. Run `just --list` to see
every recipe. Use these unless a narrower package command is more appropriate:

```sh
just test
just fmt
just typecheck
just build
just check
just release
```

Useful main CLI commands:

```sh
pnpm --filter agent-burn run start summary
pnpm --filter agent-burn run start summary --json
pnpm --filter agent-burn run start summary --value
pnpm --filter agent-burn run start summary --range month --offline
pnpm --filter agent-burn run start harness claude --json --offline
pnpm --filter agent-burn run start harness codex --value
```
