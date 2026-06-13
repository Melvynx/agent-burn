# Introduction

Agent Burn is a focused CLI for subscription-value analysis.

The public CLI has two commands:

```bash
agent-burn summary
agent-burn harness claude
agent-burn harness codex
```

`summary` gives you the all-up local usage view. `harness` narrows the analysis to the weekly subscription limit for Claude Code or Codex.

## Why It Exists

Coding-agent subscriptions hide their real value behind rate limits and local usage spread across tools. Agent Burn turns local logs into a practical answer:

- How much API-equivalent value did I consume?
- Am I using enough of my subscription to justify the plan?
- How quickly am I burning through the weekly quota window?
- Which models and days drive most of the cost?

## Privacy

Agent Burn reads local files and prints local reports. It does not upload prompts, outputs, or usage data.

## Next

Start with [Getting Started](/guide/getting-started), then review [CLI Options](/guide/cli-options).
