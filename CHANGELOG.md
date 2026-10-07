# Changelog

## 2.0.0 — 2026-10-07

Breaking: the plugin now ships one skill, `spawn-session`.

### Removed

- `skills/herdr-delegate` — its Codex launch flags `--ignore-user-config
  --ignore-rules` are rejected by interactive codex 0.154 (only `codex exec`
  accepts them). General pane and agent operations are covered by Herdr's own
  bundled `herdr` skill; Codex delegation is covered by the official Codex
  plugin (`codex:rescue`).

## 1.0.0 — 2026-08-03

Initial release.

- `skills/herdr-delegate` — delegate implementation work from Claude Code to a
  cross-vendor CLI agent (Codex etc.) running in a Herdr pane: instruction-file
  handoff, screen-based completion monitoring (agent_status is not trusted),
  and a git-ground-truth acceptance discipline built from observed fabricated
  completion reports.
- `skills/spawn-session` — spawn a named, detached Claude Code Remote Control
  session for any project directory from any live session (typically from the
  Claude mobile app), working around the official server mode's single-cwd
  limit. Includes `spawn.sh`.
- `.claude-plugin/` — plugin + self-owned marketplace manifests.
- `scripts/sync-from-local.sh` — fixed-allowlist one-way sync from the
  author's live harness (`~/.claude`); the harness copy stays canonical.
