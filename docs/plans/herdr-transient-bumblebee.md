# herdr-toolkit 2.1.0 — agent への送信を確実にする

状態: **判断 4 件を著者が確定（2026-10-10、Respond で全件推奨どおり）**。本体は [herdr-toolkit-2-1.html](herdr-toolkit-2-1.html)（html-plan、lint 済み、private artifact https://claude.ai/artifact/Tr2AtFQncxeFs17F6Ab5Tp）。この md は plan mode 用の要約で、内容が食い違ったら html を正とする。

確定した判断: agent-send は新 skill / Enter は押さず `typed` で返す / 完了は状態の settle と `--done-if`（hook なし）/ 実行者はこのセッション。外部 report は [research/2026-10-10-herdr-toolkit-next.md](research/2026-10-10-herdr-toolkit-next.md)。

## Context

v2.0.0 で herdr-delegate を退役し、plugin は `spawn-session` の 1 本になった。著者のセッション履歴（2026-07-05〜10-09、herdr 呼び出し 1,704 回）を走査した結果、Herdr の仕様が原因の詰まりは次のとおり。

- **着弾の確認**: `agent prompt --wait`（turn の完了待ち）が 279 回中 123 回 `timeout` を返し、画面の確認（383 回）と sleep での polling（176 回）が増えた。`--until working` を使う `triage-tick.sh` は 28 回中失敗 0
- **状態の誤判定**: Herdr は turn を追跡せず、Claude と Codex の状態を画面から検出する。偽 idle と偽 working の open issue がある
- **slash command**: `/effort` を prompt で送った 3 回は、3 回とも stalled だった
- **版ずれ**: client 0.9.3 に対し、server は 0.9.1。`server live-handoff` は 0.9.3 に無い
- **vendor skill**: brew パッケージに `herdr` skill のファイルが無いので、symlink にできない（手でコピーしている）

手元で確かめた事実（2026-10-10）:

- Herdr の `agent_session.value` は Claude の sessionId と同じ値で、transcript のファイル名にもなる
- `claude agents --json` は対話 session にも `status`（idle / busy / waiting）を返す（1 回 0.2 秒）

調査:
- 内部 [research/2026-10-10-herdr-session-bottlenecks.md](research/2026-10-10-herdr-session-bottlenecks.md)
- 外部 notes `~/.cache/claude-research-notes/2026-10-10-herdr-toolkit-next/`（herdr-upstream / cc-plugin / adversarial / cc-sessions の 4 本）
- 外部 report への統合は**未了**

## 推奨する変更（html の claim 1〜5）

### 1. 新 skill `agent-send` の `prompt`
- 宛先は pane ID に固定する。表示名でも引ける
- working の相手には送らない（queue に入ると着弾を証明できない。#85603 の取りこぼしも避ける）
- 手順: `--wait --until working --until blocked` で送る → 返らなければ次の順で確かめる
  1. `state_change_seq` の変化
  2. Claude の状態（status）
  3. transcript に user turn が出たか
- 入力欄に残っていたら `typed` で返し、Enter は押さない（blocked 検出の 0.3 秒遅れで承認を押す恐れ、#4764）
- 証拠がなければ `no_evidence` として失敗にする

### 2. `agent-send wait`
- 状態の取り方
  - Claude は `claude agents --json` の status を使う（画面検出に頼らない）
  - Codex は Herdr の `agent_status` を使う
- 完了の条件: settled が続くこと（Claude 2 回、他 3 回）と、任意の `--done-if`（成果物の条件）
- SKILL.md で `run_in_background` での起動を指示し、待ちを context から外す

### 3. `spawn.sh`
- `--effort` / `--permission-mode` を通す（`bypassPermissions` は拒否）
- `--prompt-file` で、起動と最初の指示を 1 回で渡す
- trust で止まったときは、理由と agent 名を返す
- spawn-session の存在理由を言い直す。Week 34 の device card が任意の directory を起こせるなら、主な用途は「Herdr pane に起こし、agent-send で操る」になる

### 4. preflight
- `herdr status --json` で判定する
  - 互換性が無ければ止める
  - server が 0.9.0 未満なら止める
  - stale は警告だけ出す
- `herdr --skill` と vendor copy の差分も警告する

### 5. ハーネス 4 か所と公開 repo を揃え、2.1.0 を公開する
- ハーネスの呼び出し箇所: `spawn-session/SKILL.md:65`、`task-triage/SKILL.md:209,253`、`triage-tick.sh:153`、`mono-figure/SKILL.md:82`、`rules/common/agents.md:10`（rule は著者の diff）
- テストと gate: bats（偽の `herdr` を PATH の先頭に置く）、herdr-toolkit の `.claude/verify.sh`
- 公開物: README を 0.9.3 の事実で書き直す。sync の allowlist に `agent-send` を足し、CHANGELOG と `plugin.json` を 2.1.0 にする
- **push と公開は著者の確認後**

## 判断（html の doc-ask）

- agent-send の置き場
  - 推奨: 新 skill
- Enter の押し直し
  - 推奨: 押さない
- 完了の信号
  - 推奨: settle と `--done-if`（hook なし）
- 実行者
  - 推奨: このセッション（Opus、build-tier）。Herdr の実機と `~/.claude` が要るので、cloud には出せない

## Phase 0（実装の最初、著者が関わるもの）

1. **server の再起動**：0.9.3 に上げる。他 session の turn が止まるので、時刻は著者が決める。上げたあと、#4537（未 focus pane への初回 prompt）と trust ダイアログの blocked 判定を使い捨て pane で確かめる
2. **device card の実測**：iPhone の device card で選べる folder の範囲を確かめる（著者）
3. **status の対応**：`claude agents --json` の `waiting` が承認待ちを指すか、背景 subagent の実行中も `busy` かを確かめる

## Verification

- bats
  - 送信: stalled のあと seq が変化 / typed / blocked / busy
  - 待ち: 揺れの間は done にしない、`--done-if`
  - preflight: 互換なし、版の下限
  - spawn.sh: 引数の転送、`bypassPermissions` の拒否、`--prompt-file`、trust のメッセージ
- shellcheck と `claude plugin validate --strict`
- plugin.json と CHANGELOG の版の一致
- 実機: 使い捨て pane での spawn → prompt → wait の通し
- Review: `/code-review` medium と `security-reviewer`（permission の経路）

## 着手順

1. この plan と調査 report を `docs(plan): herdr-toolkit-2-1` で単独 commit する（herdr-toolkit repo。`.gitignore` に `*.packed.html` / `*.artifact.html` を足す）
2. Phase 0 のうち、著者を待たないもの（status の対応）から始める。server 再起動と device card は著者に時刻と実測を頼む
3. skill-creator を読み、agent-send を TDD（bats 赤 → 実装）で作る → spawn.sh → ハーネス 4 か所 → README など
4. Review と Verify を通し、sync の dry-run → apply。push と公開は著者に確認してから行う
