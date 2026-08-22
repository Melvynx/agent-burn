# AGENTS.md - Website

Read `README.md` first for the site structure and commands. This file adds agent
workflow rules for changes under `docs/`.

## Package Notes

- Landing lives in `src/routes/index.tsx` with scoped CSS in `src/styles/landing.css`.
- Docs chrome is Fumadocs on TanStack Start. MDX lives in `content/docs/`.
- Static assets live in `public/`. The build copies `apps/agent-burn/config-schema.json` to `public/config-schema.json`.
- The public site is `https://agent-burn.melvynx.dev` on Vercel.

Use the root `development` guidance for shared repository validation.

## Content Rules

- Prefer the public commands in new or edited docs: `agent-burn summary`, `agent-burn harness claude`, and `agent-burn harness codex`.
- Old report commands such as `daily`, `weekly`, `monthly`, `session`, `blocks`, and `statusline` are not part of the public Agent Burn surface. Do not promote or reintroduce them in docs.
- Do not reintroduce wrapper bins such as `agent-burn-amp`, `agent-burn-codex`, `agent-burn-opencode`, or `agent-burn-pi`.
- Place screenshots immediately after the page H1 when a guide has a primary screenshot.
- Use relative image paths such as `/screenshot.png` for files in `docs/public/`.
- Always include descriptive alt text for screenshots and images.
- Cross-link related guides and JSON output documentation where useful.

## Validation

```sh
just docs::dev
just docs::build
just docs::typecheck
```
