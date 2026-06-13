# Installation

Use a package runner:

```bash
npx agent-burn@latest summary --value
pnpm dlx agent-burn@latest summary --value
bunx agent-burn@latest summary --value
```

The package exposes two binaries:

- `agent-burn`
- `burn`

Example:

```bash
burn harness claude --value
```

## Nix

The flake exposes the renamed package and app:

```bash
nix run github:Melvynx/agent-burn -- summary --value
nix build github:Melvynx/agent-burn#agent-burn
```
