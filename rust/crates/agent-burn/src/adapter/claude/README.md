# Claude Code Source

Default data directories:

- `~/.config/claude/projects/`
- `~/.claude/projects/`

`CLAUDE_CONFIG_DIR` can specify one path or comma-separated multiple paths. Data from valid directories is combined.

File shape:

```text
projects/{project}/{sessionId}/{file}.jsonl
projects/{project}/{sessionId}.jsonl
```

`projects/` is scanned recursively, so both nested session directories and legacy flat JSONL files can be loaded.

Sidechain entries:

- Claude Code may write `isSidechain: true` entries for isolated sidechain
  conversations such as `/btw` `aside_question` logs under `subagents/`. See
  the Claude Code
  [side questions documentation](https://code.claude.com/docs/en/interactive-mode#side-questions-with-btw).
- These files can replay parent conversation messages with the same message ID
  but a different request ID, including the parent cache-read usage.
- agent-burn keeps the parent entry and drops the replayed sidechain copy when at
  least one duplicate carries `isSidechain: true`. Distinct sidechain responses
  with their own message IDs are still counted.
- This behavior fixes the overcounting reported in
  [#913](https://github.com/Melvynx/agent-burn/issues/913).

The term `session` has two meanings in this codebase:

- Session report grouping uses project directories.
- For nested files, session reports derive `sessionId` from the session directory name.
- True Claude Code session ID may also appear in each JSONL entry's `sessionId` field.

Malformed JSONL lines are skipped during parsing.

Live `summary --value --json` can include `claudeAccount`. Agent Burn reads
`https://api.anthropic.com/api/oauth/usage` with the signed-in Claude Code
OAuth token. The parser accepts the modern `limits` array (`session`,
`weekly_all`, `weekly_scoped`) and the older top-level `five_hour` /
`seven_day` windows, plus `extra_usage` or `spend` credits. `--offline`
omits the account object.
