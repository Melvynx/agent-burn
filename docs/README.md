# Documentation Site

This directory contains the VitePress documentation website for Agent Burn.

## Structure

- `guide/` - user guides for the `summary` and `harness` commands.
- `public/` - static assets and generated config schema.
- `.vitepress/` - VitePress configuration.

The docs build copies `apps/agent-burn/config-schema.json` to `docs/public/config-schema.json` before running VitePress.

## Commands

```sh
just docs::dev
just docs::build
just docs::preview
just docs::typecheck
```
