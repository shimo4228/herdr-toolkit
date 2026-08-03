# Changelog

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
