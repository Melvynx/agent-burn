# Agent Burn website

TanStack Start site for the landing page and documentation.

- Landing lives at `/`.
- Docs live at `/docs` with Lumail-style chrome.
- MDX content lives in `content/docs/`.
- Static assets live in `public/`.

The build copies `apps/agent-burn/config-schema.json` to `public/config-schema.json`.

## Commands

```sh
just docs::dev
just docs::build
just docs::preview   # production Nitro build, same chrome as publish
just docs::typecheck
```

The public site is `https://agent-burn.melvynx.dev`.
