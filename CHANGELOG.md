# Changelog

## 2.1.1 — 2026-10-10

### Fixed

- `spawn-session --prompt-file` resends the first prompt once when it vanished
  without a trace: on Herdr 0.9.3 (macOS) a prompt to a freshly started,
  never-focused pane was lost in 1 of 6 runs, the same pattern as herdr #4537.
  agent-send's new `--retry-unseen` resends only while the Claude Code session
  has no transcript yet, so it has not processed any message and a resend
  cannot double-submit.

## 2.1.0 — 2026-10-10

### Added

- `skills/agent-send` — send a prompt to an agent in a Herdr pane (Claude Code,
  Codex, others) and get one result line and an exit code. A prompt counts as
  landed when the turn is seen to start (`--until working`), not when the turn
  ends; after a stall it checks `state_change_seq`, Claude Code's own status
  (`claude agents --json`) and the session transcript, and never resends.
  `wait` waits for settled status plus an optional `--done-if` command, and is
  meant to run in the background. `preflight` stops on a client/server
  mismatch or a server older than 0.9.0, and warns on a stale server or a
  copied `herdr` skill that differs from `herdr --skill`.
- `spawn-session`: `--effort`, `--permission-mode` (not `bypassPermissions`)
  and `--prompt-file` (sends the first prompt through agent-send). A start
  blocked by the workspace trust dialog is named, with the agent name and pane.
- bats tests for both skills, with fake `herdr` and `claude` binaries.

### Changed

- `spawn-session` no longer carries its own landing check and polling loop;
  it points at agent-send. Its purpose is restated: since August 2026 the
  Claude app lists a machine running `claude remote-control` as a device card
  that can start a session in a chosen directory, so this skill is for sessions
  you want in a Herdr pane, started from a session or a script and driven by
  agent-send.
- Built against Herdr 0.9.3 and Claude Code 2.1.296.

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
