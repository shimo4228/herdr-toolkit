kind: external
# herdr-toolkit 2.1（agent-send の新設、spawn-session の再検証、Herdr 運用のボトルネック解消）を設計・release するために、Herdr 0.9.3・Claude Code 2.1.296・plugin 仕様の現状と、同種ツールの先例はどうなっているか

## Scope searched

統合元は researcher notes 4 本（herdr-upstream / cc-sessions / cc-plugin / adversarial）と、lead が手元で確かめた一次事実。再検索はしていない。as-of は特記なき限り 2026-10-10（取得日・実行日）。環境は macOS、herdr client 0.9.3 / 稼働 server 0.9.1、Claude Code 2.1.296。

読みの水準（各 item の `[]`）:
- `[raw]` 本文を読んだ（notes の [raw] / 【全文】/「本文」）
- `[節]` grep と該当節の Read のみ（【該当節】）
- `[relay]` 小モデルの抽出・要約を経由。引用符内は逐語の保証なし（notes の「抽出」/ [relay] / 【要約経由】/「要約器経由」）
- `[snippet]` 検索結果の要約のみ
- `[手元]` lead が 2026-10-10 に macOS で実行した出力（notes と同格の一次 source）
- 【推測】= note 著者の推論 / 【未確認】= source が断片的で裏取り不足

調べた source（web 呼び出し 計 63 回: Herdr 15 / セッション 17 / plugin 15 / 先例 16）:
- Herdr upstream: herdr.dev の llms.txt・agent-guide.md、v0.9.3 tag の docs 6 本（agent-automation / cli-reference / socket-api / agents / session-state / integrations）、GitHub releases（HTML と API。API は先頭 100,000 字で切れ v0.9.0 以前を取れず）、issue #4764、issue 検索 3 本（可視 16/1,154、13/41、16/86 件）。全て `[relay]`。upstream repo の main に CHANGELOG.md は無い（404）が、brew パッケージ内には upstream の release notes を含む CHANGELOG.md がある。
- Claude Code セッション: code.claude.com の remote-control・cross-session-messaging・cli-reference・whats-new（index と 2026-w34）`[raw]`、claude-projects・desktop・tools-reference `[節]`、agent-view・hooks（0–200,000 字。末尾 62,610 字は未読）・support.claude.com の Dispatch `[relay]`。先例角度が interactive-mode `[raw]`、anthropics/claude-code #85603 と記事 1 本 `[relay]`。WebSearch 3 回は `[snippet]`。
- plugin 仕様: code.claude.com の plugins-reference・plugin-marketplaces・plugins/{loading, host-marketplace, marketplace-reference, cli-reference, components}・plugin-evals（509–594 行の field 表は未読）`[raw]`。skills（先頭 100,000 字）、Claude Code CHANGELOG（先頭 100,000 字 = 2.1.287 まで）、claude-plugins-official の tree（213,639 字中 0–200,000 字）と 2 file は `[relay]`。repo の実ファイル（plugin.json・marketplace.json・spawn-session/SKILL.md・CHANGELOG.md・sync-from-local.sh）。
- 先例と反証: claude-squad の `session/tmux/tmux.go`、agent-deck v1.11.0 release、Claude Code hooks reference、Herdr #4764 と releases、Codex config-advanced（learn.chatgpt.com へ redirect 後）を `[relay]`。`~/.claude/projects` 配下の transcript は key 名のみ Grep（本文は読んでいない）。WebSearch 4 回は `[snippet]`。
- lead の手元実測 `[手元]`: `herdr status --json` / `herdr server --help` / `herdr --help` / `herdr --skill` / `herdr agent list`、brew パッケージ内の CHANGELOG.md、`gh api`・`gh issue view 4537`、`claude agents --json` / `claude --help` / `claude plugin validate`、git 履歴。

見つからなかった / 未実施:
- Herdr: v0.7.5〜v0.8.x の release notes は upstream から取れず（`[手元]` の CHANGELOG 抜粋が一部を補う）。roadmap 文書、`{"result":{}}` の空応答を指す issue、Claude の workspace trust dialog を指す issue は見つからず。docs の未読: plugins / agent-skill / configuration / install / troubleshooting / add-herdr-support / concepts。issue 本文は #4764 と #4537 のみ読んだ。
- Claude Code: device card の folder 一覧の中身、socket に書く message 行の schema、`--remote-control <name>` が local 名にもなるかの公式記述は無かった。changelog の 2.1.288〜2.1.296 は個別に走査していない（参照 doc 自体が 2.1.295 までを反映）。
- plugin: Publish a plugin・troubleshooting・claude.com org-sync ページ、第三者 plugin の bats 利用は未調査。`claude plugin eval` は実機未実行。
- 先例: agent-deck の send 実装本体、他の tmux orchestrator、Herdr の preview build 本文は未読。

失効条件: Herdr v0.9.4 以降の stable、#4764 / #4537 / PR #4756 の状態変化、Claude Code 2.1.297 以降または次の weekly digest、Claude Code の UI 文言変更（Herdr の screen manifest の追随待ち）のどれかで再確認する。

## Found

### A. Herdr upstream（v0.7.5〜v0.9.3。stable 最新は v0.9.3、2026-09-29 公開）

要点:
- `agent prompt --wait` は送信と待機を 1 request に束ねる。doc 自身が「timeout と `agent_prompt_stalled` は入力が送られなかった証拠にならない。再送前に read せよ」と書き、"It does not track individual turns" と明記する。working 中に送ると `--wait` は進行中 turn の完了で返りうる。着弾と完了の保証は文書上無い。
- Claude・Codex の状態は screen manifest 検出で（Claude の integration v10 が報告するのは session identity のみ）、誤判定の open issue が両方向にある: 偽 idle（背景 subagent・背景 MCP: #5004, #3090, #4376。Codex の picker: #4647）、偽 working（残留 spinner が約 95 分: #4819, #4626）。
- 着弾の open 報告が v0.9.0 の "reliably sends the prompt and Enter" 後も残る（#4537 Linux・`--no-focus` の未 attach idle pane、#4990、#4529）。macOS・0.9.3 での再現は未確認。名前宛 prompt は agent 終了直後に新 occupant へ届きうる（#4764、macOS、maintainer 未返信）。pane ID 宛が回避になると読める【推測】。
- `[手元]` `herdr status --json` は compatible / endpoint_compatible / restart_needed / server_binary_stale と各 version、`server.capabilities.live_handoff` を返す。稼働 server は 0.9.1 で binary より古い（stale true）が compatible。0.9.3 の `herdr server --help` に `live-handoff` は無く、brew 導入では doc 上 `herdr update` が無効 — 稼働 server の更新は stop→再起動になると読める【推測】。
- `[手元]` 同梱 skill は `herdr --skill` で出力され、手元の vendor copy と一致する（origin 行を除く）。brew パッケージに skill file は無い（Hunk は brew に skills/ を持ち symlink で追随）。

URL の別名: `DOC` = https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs （`DOC/agent-automation.mdx` など）/ `REL` = https://github.com/herdrdev/herdr/releases / `RELAPI` = https://api.github.com/repos/herdrdev/herdr/releases?per_page=40 / `ISS-n` = https://github.com/herdrdev/herdr/issues/n / `SRCH` = https://api.github.com/search/issues?q=repo:herdrdev/herdr+…（3 クエリ）。

**A1. `agent prompt` の意味論** — `DOC/{agent-automation,cli-reference,socket-api}.mdx` `[relay]`、公式 doc（v0.9.3 tag）。note の照合では 0.9.3 の `agent prompt --help` 本文と一致
- 送信: text と遅延 Enter を 1 つの順序づけられた submission とし、terminal の bracketed-paste mode に従う。working 中でも送れる。`--wait` 無しの成功は書き込みの ack だけで、turn が始まった保証ではない。
- `--wait`: 既に blocked なら `agent_blocked`（入力を送らず wait も始めない）。non-working から受理されたら 5 秒以内に working か blocked の観測が要り、無ければ `agent_prompt_stalled`。caller の `--timeout` が先に切れたら `timeout`（submission 時間を含む）。既定の match は idle / done / blocked、`--until` は繰り返し可（`agent prompt` では `--wait` が必須）。
- 警告（抽出）: "A timeout or `agent_prompt_stalled` does not prove that no input was sent." / "Read the agent before retrying to avoid submitting the same prompt twice."
- socket `agent.prompt` は任意の `wait`（`until`, `timeout_ms`）を取り、submit と wait を 1 request で行う（"avoiding a race between separate calls"）。socket doc の error code 一覧に `agent_prompt_stalled` / `agent_not_ready` / `timeout` は無い（CLI doc にはある。理由不明）。CLI の exit 1 = timeout か server error（JSON を stderr）、2 = usage error。
- upstream の recipe（抽出）: `pane split --current --direction right --no-focus` → `agent start reviewer --kind codex --pane … -- -m …` → `agent prompt reviewer "…" --wait --timeout 120000` → `agent read reviewer --source recent-unwrapped --lines 120`。
- 違い: 著者のハーネス 4 か所は「送る → Enter → 待つ → 読む」を自前で組んでいる（lead の brief）。upstream は submit+wait の原子化と stall 検出を持つが、着弾と完了の保証は文書上持たない。
- 移せる部分: submit+wait の 1 request、error code による分岐（`agent_blocked` は入力 0 で再試行が安全。`agent_prompt_stalled` と `timeout` は不明なので read してから）、`agent read --source recent-unwrapped --lines N`。

**A2. 完了判定と status 語彙** — `DOC/{agent-automation,cli-reference,socket-api}.mdx` `[relay]`、公式 doc
- "It does not track individual turns." / "If the agent is already working, completion of that active turn may satisfy the wait."
- `completion_seq`: "Agent responses may include `completion_seq`, identifying the current idle transition as completed work"。startup readiness・idle 会話の restore・会話の切替は完了に数えない。載る response と導入版は【未確認】。socket doc に turn 完了 event は無く、最寄りは status 値。
- 語彙: `idle` と `done` はどちらも入力可、`done` は idle だが未 seen、`blocked` は承認/質問 UI を認識、`unknown` は agent はいるが lifecycle を確信を持って分類できない。seen は明示的な `pane focus` / `agent focus` で付き、read では付かない。v0.9.1 で `agent focus` が attached client を動かす。
- 【推測】人間が pane を見ている間は完了が done を経ず idle になりうるので、`--until done` 単独は完了検出に使えず、既定 match が 3 値なのはそのためと読める。未検証。
- 移せる部分: 送信前に status が idle/done か確認する pre-check（`agent get`）、完了判定で idle と done を同値に扱う、`completion_seq` が使えるなら送信前後の比較【要検証】。自動化からの `agent focus` は接続中 client の focus を動かす副作用がある。

**A3. Claude・Codex の状態の出どころ** — `DOC/{agents,integrations}.mdx`、https://herdr.dev/agent-guide.md `[relay]`、公式 doc（3 ページが一致）
- Claude Code・Codex とも、integration が状態を報告しない限り screen 検出（pane 下端の live buffer を分類）。状態を報告する integration は Pi, OMP, Kimi, OpenCode, Kilo, MastraCode で、Claude と Codex は入らない。
- Claude integration（`herdr integration install claude`）: `~/.claude`（または `CLAUDE_CONFIG_DIR`）に `hooks/herdr-agent-state.sh` を書き `settings.json` に hook entry を足す。v10 は documented な `SessionStart` source（startup, resume, clear, compact, fork）だけに反応し、報告するのは session identity（native restore 用）のみ — working / blocked / done / idle は報告しない。v10 の中身は matcher の限定で、状態報告の追加ではない。native restore には v6 以上。`herdr integration status [--outdated-only]` で古い integration を確認できる。
- Codex: hook は session identity のみ。"Codex falls back to `unknown` because its title and composer can look the same during an active turn"。PR #4756（merged 2026-09-29、`SRCH` の 1 行要旨）は Codex の prompt-submit・stop・interrupt hook で pane-local session の working/idle を報告する。入る版は【未確認】で、v0.9.3 の `integrations.mdx` は Codex を screen 検出と書く。hook 経由の状態報告へ向かう動きの証拠。
- blocked は live bottom-buffer が既知の approval / question / permission UI に一致したときだけ。検出規則は manifest（`herdr server agent-manifests [--json]` / `update-agent-manifests` / `reload-agent-manifests`）。【推測】規則は herdr の version と別に更新されうる（server version との関係は未確認）。
- 診断: `herdr agent explain <target> [--json|--verbose]` は検出と同じ snapshot を分類し、`--file PATH --agent LABEL` で保存 fixture を local 分析する。doc に "Live explain requires restarting or handing off to an updated server first." とあり、稼働 server 0.9.1 での挙動は【未確認】。
- 違い / 移せる部分: 著者は「Claude は hook で状態が取れる」と見ている可能性があるが、doc 上は screen 検出。判定根拠が screen であることを script の前提に書く、`agent explain --json` を失敗時の診断出力に使う。

**A4. 状態の誤判定（open issue、2026-10-10 時点で可視の分）** — `ISS-n`、`SRCH`（タイトル・状態・日付・1 行要旨のみ。本文未読）`[relay]`。根拠はユーザー報告で未再現。ただし `bug` / `p2` / `triaged` は maintainer の screening を示す
- Claude: #5004 open（2026-10-06）背景 subagent 中に idle（footer 文言の変更が原因との要旨）/ #3090 open（2026-08-21、更新 09-14）背景化した長い MCP tool call 中に idle / #4376 open（2026-09-19、更新 10-04）背景 activity 行が ✳ glyph のとき idle、他の glyph では working / #4819 open（2026-10-01）完了済み turn の上に残った過去の spinner 行が idle prompt を上書きし working が約 95 分 / #4626 open（2026-09-25）`live_turn_working` が indent された（echo された）spinner 行に一致し idle pane が working のまま / #3467 open（2026-08-31）古い busy OSC title が permission dialog の blocked 規則より優先され dialog 表示中に working / #1217 closed not planned（monitor 待ちの Claude が complete 表示）。
- Codex: #4793 closed not planned・duplicate（2026-09-30）長い最終報告後 unknown のまま、完了通知と `agent wait` が発火せず / #4647 open・`bug`（macOS、2026-09-26）picker（`/model`、rate-limit prompt）が idle と報告され `agent prompt` がそれに答えてしまう。
- 他: #4131（Cline）`agent wait` が出力 20 行超の途中で idle を返す / #4690 open `tab close` 後に `agent wait` が timeout まで返らない / #2668, #4664, #4454 は Pi・OMP・OpenCode の取り違え。
- 違い / 移せる部分: 一部は Linux・Windows 報告。#4647 と #4764 は macOS（著者と同じ platform）。誤判定は偽 idle と偽 working の両方向にあり、「status が idle」を完了の唯一の証拠にしない設計の材料になる（独立した完了根拠は B・D 節）。

**A5. 着弾（prompt landing）の既知問題** — `REL`・`SRCH`（1 行要旨）`[relay]`、`ISS-4764`（本文とコメント 2 件）`[relay]`、`ISS-4537`（本文）`[手元]`
- release 側: v0.9.0（2026-09-07）"`agent prompt` now reliably sends the prompt and Enter before reporting successful submission."（`[手元]` の CHANGELOG と一致。#3506, #3685）/ "Expired queued submissions are rejected before typing starts."（`[relay]`）。前段の v0.8.0 は送信後に短く待ってから Enter を押す（#1878、`[手元]`）。
- 報告側（0.9.1 以降も open）: **#4537** `[手元]` open・bug・linux・p2・triaged、herdr 0.9.1。`--no-focus` で作った未 attach の idle pane に `agent prompt` / `pane send-text`+`send-keys` / `pane run` のどれも届かない。報告者は Claude Code の UserPromptSubmit hook で配送を確かめ（hook が発火しない）、成功を返さず失敗してほしいと要望。upstream の recipe が `pane split --no-focus` で始まる点に注意。macOS・0.9.3 で再現するかは【未確認】。/ #4990 open・Linux（2026-10-06）devin CLI へ multi-line prompt が paste されるが Enter で submit されず `agent_prompted` が偽陽性（成功応答の type 名が `agent_prompted`）/ #4529 open・Windows（2026-09-23）起動直後の Claude Code への最初の `agent prompt` がしばしば submit されず、Enter をもう 1 回送ると通ることが多い / #4988 open PR・macOS（2026-10-06）shell 起動中に送った長い入力が Enter を含め黙って欠落するので巨大な canonical 入力を事前 reject【推測】foreground が raw mode になる前に長い prompt を送ると欠落しうる。
- closed: #2422（not planned）`--wait` が遅延 Enter の submit 前に解決 / #4713（PR、not merged）200 ms 後に settled な追加 Enter を送る案 / #4718（not planned）submit key を変更した pi で newline になり stall / #4712（duplicate）人間の入力と注入 prompt の混在 / #4823（not planned）self-reported agent への delivery hook。
- `{"result":{}}` の空応答: doc に記述が無く、旧形が 0.9.x で直ったかを裏づける source は見つからなかった。最寄りの maintainer 主張が v0.9.0 の "reliably sends…"。
- **名前宛 prompt の race（#4764、open、2026-09-29、macOS）**: agent の exit 後も herdr は旧 name と session をしばらく pane に紐づけ、その間の名前宛 prompt は受理される（`agent_not_found` まで約 10 秒、1 回の計測。誤配は観測していない）。提案は `--expect-session <agent_session.value>` / `--expect-agent claude`（server 側で検査し不一致は `agent_occupant_changed`）、または exit 時に name と session を即クリア。コメント 2 件: `--if-state idle,done` / `--if-state-change-seq N`（`precondition_failed`）の提案と、検出 lag 0.26〜0.30 秒の間に stray prompt が permission dialog を承認しうる事例、`expectedSessionId` の提案。`AgentPromptParams` は現状 `target`, `text`, 任意の `wait` のみ。maintainer の返信・accept・schedule は無い（ラベル triaged, maintainer-needed, p2, macos, agent-detection, api）。対比: socket doc は `agent.wait` が occupant を pin すると書くが `agent.prompt` に同等の記述は無い。
- 違い / 移せる部分: 着弾確認の read は upstream が吸収した形跡が無く、upstream の推奨（"Read the agent before retrying"）と同じ向き。macOS + Claude/Codex の v0.9.0 以降の open 報告は可視範囲に無いが、可視は検索 86 件中 16 件のみ。宛先を name でなく pane ID にする（doc は target を "unique live agent name or the pane ID" と定義）、再送前の read、長い prompt の送信前に foreground が agent の TUI かの確認。
- 解けた問い: #4537 の再現条件（Linux・0.9.1・`--no-focus` の未 attach idle pane）は本文で確定。残るのは macOS・0.9.3 での再現。

**A6. events / socket API** — `DOC/{socket-api,cli-reference}.mdx`、`REL` `[relay]`
- `events.subscribe`（NDJSON、Unix socket。Windows は named pipe）で push 待ち: `pane.agent_status_changed`（`agent_status` 付き）、`pane.output_matched`、`pane.created`、`pane.exited`、`pane.agent_detected` ほか。turn 完了専用の event・コマンドは無い。socket path の解決順は `--session` → `HERDR_SOCKET_PATH` → `HERDR_SESSION` → 既定 `~/.config/herdr/herdr.sock`。
- 購読は受理時点から始まり replay しない（v0.9.0）。遅れた reader は `events_lost` error で閉じられる（v0.9.2）ので、再購読して `session.snapshot` で reconcile する。events は invalidation signal で replay する payload ではない。購読は live handoff 中に切れうる（A8）。
- UI 側の通知は `herdr notification show`。外部へ turn 完了を push する経路の候補は plugin の "event hooks" だが plugins.mdx は未読【未確認】。
- 違い / 移せる部分: 著者の 4 か所は polling で終わりを見ている可能性が高い（brief に明記なし）。`events.subscribe` + 再購読 + reconcile、`herdr agent wait`（`--until` 反復、timeout 無しなら無期限）。

**A7. 起動時 blocked と `agent start`** — `DOC/{agent-automation,cli-reference,agents}.mdx` `[relay]`、`[手元]` の CHANGELOG
- `agent start <name> --kind KIND --pane ID [--timeout MS] [-- <agent-args...>]` は既存の idle shell pane で起動する。name は `[a-z][a-z0-9_-]{0,31}`、live agent 間で一意。成功は "only after Herdr detects the expected agent in the same terminal"、起動中に blocked なら `agent_not_ready` で即返る。既定 timeout 30 秒（明示値は 3000 超 300000 以下）。
- target は "unique live agent name or the pane ID hosting the agent"（terminal ID と bare kind は不可）。blocked 中の `agent prompt` は `agent_blocked`（入力 0）。`agent send-keys` は論理 key（`esc`, `up`, `enter`, `ctrl+c`）で、書く前に全 key を検証する。
- v0.8.2 `[手元]`: "`agent start` now waits for new pane shells and first-run agent prompts to become ready" / "Claude Code confirmation prompts using `Enter to confirm · Esc to cancel` now report `blocked`"。v0.9.1 / v0.9.2 で Claude の MCP 質問・Bash 承認 prompt は回答待ちの間 blocked（`REL`。両版に同文があり抽出の重複の可能性）。#4732 open（2026-09-28）は self-reported agent への `agent prompt` が `agent_not_ready` になる件。
- Claude の workspace trust dialog が blocked と判定されるかは doc にも可視 issue にも無い【未確認】（確かめる手段: dialog 表示中に `herdr agent explain <pane> --json`）。
- 違い / 移せる部分: spawn-session が `agent start` を使うかを note 著者は未確認。手で `claude` を shell に打つ流儀なら、起動完了検出と `agent_not_ready` は使われていない。起動の完了判定を `agent start` に任せる、`agent_not_ready` を trust dialog 等への分岐に使う（blocked 判定の有無は要検証）。

**A8. `herdr status` / 更新 / live handoff** — `DOC/{session-state,cli-reference}.mdx`、`REL`、`SRCH`（13/41 件）`[relay]`、`[手元]`
- `[手元]` `herdr status --json` が返す field: `server.compatible`, `server.endpoint_compatible`, `server.restart_needed`, `server.server_binary_stale`, `server.version`, `client.version`, `server.capabilities.live_handoff`。手元の値は compatible true / endpoint_compatible true / restart_needed false / server_binary_stale true / server 0.9.1 / client 0.9.3（`live_handoff` の値は未記録）。
- upstream doc に field の定義は無い（`herdr status`, `status server`, `status client` の存在のみ）。issue の断片: #4806 open（2026-09-30）"they disagree while a server predates its binary, which `herdr status` reports as `server_binary_stale`."（何が disagree するかは本文未読）/ #4205 open（2026-09-15）`restart_needed` が false なのに remote attach が server restart を勧める。【推測】`server_binary_stale: true` は「稼働 server が disk 上の binary より古い」意味で、手元の値と整合する。
- `[手元]` 0.9.3 の `herdr server --help` のサブコマンドは stop / reload-config / agent-manifests / update-agent-manifests / reload-agent-manifests だけで、`server live-handoff` は無い。`herdr --help` に `herdr update [--handoff]` と `--handoff`（"Opt into live handoff for update or remote attach"）がある。doc も handoff は `herdr update --handoff` と `herdr --remote … --handoff` のみとし、"No server-side handoff or restart subcommand is described."（抽出）。#3048（closed 2026-08-21）は、top-level `--handoff` が help に載るのに unknown option、binary を更新済みだと live-handoff の手段が無い、というタイトル。
- 互換（v0.9.0 以降）: "Plain `herdr update` installs the new client and keeps endpoint-generation-1 servers running." / pre-generation-1 の server だけ 1 回の upgrade（stop）が要る。v0.8.0 で受けた「brew upgrade 直後に `compatible: no` で CLI 全滅」はこの導入前の挙動に当たる【推測】。v0.7.5 で、client と server の protocol が違うとき CLI は machine-readable な `protocol_mismatch` error を返す（`[手元]`）。
- brew の制約: `herdr update --handoff` は Herdr 自身の updater の install にだけ効く。Homebrew・mise・Nix は package manager で更新し、`herdr update` は無効で live handoff できない（`DOC/session-state.mdx`）。handoff 無しの restart は process を止めるが layout は戻り、agent の会話は native session restore がある場合のみ戻る（Claude integration v6 以上、Codex v5 以上。手元の Claude は v10）。
- handoff が保つのは pane PTY・process、agent identity と durable metadata、plugin / session state。"In-flight CLI or API requests, waits, subscription streams, client sockets, and pane-to-pane messages may be interrupted" なので client は reconnect して retry する。experimental で opt-in。
- 稼働 server 0.9.1 が持たない 0.9.2 の修正【推測】: API socket が transient error 後も接続を受ける（CLI と live handoff が失敗しなくなる）/ hook 報告の status が live handoff を越える / 起動・restore・Pi `/new` で偽の done 通知を出さない / 復元 agent を 100 ms 間隔で 1 つずつ起動 / `herdr update` が旧版で動いている server を列挙し restart の exact command を出す。64 pane 上限は v0.9.1 で解除（送り側 server がその update を含む場合）。
- 移せる部分: restart 後の復帰は native restore に依存する、handoff 中の wait は切れる前提で script を書く。
- 解けた問い: `server live-handoff` は 0.9.3 に無い。`herdr status --json` の field 名と手元の値は確定。残るのは各 field の upstream 上の定義。

**A9. release 履歴** — `REL`・`RELAPI`（v0.9.0〜v0.9.3、先頭 100,000 字）`[relay]`、brew 内 CHANGELOG.md `[手元]`、公開日は `gh api` `[手元]`

| 版 | stable 公開日 | agent 運用に関わる変更 |
|---|---|---|
| v0.7.5 | 2026-07-21 | `[手元]` `agent_prompt_stalled`（5 秒、状態変化の観測なし）/ live-agent CLI facade（start・prompt・send-keys・wait）/ `protocol_mismatch` |
| v0.8.0 | 2026-08-03 | `[手元]` prompt 送信後に短く待ってから Enter（#1878） |
| v0.8.2 | 2026-08-19 | `[手元]` 承認/質問待ちの agent への `agent prompt` は `agent_blocked` / `agent start` が shell と初回 prompt の ready を待つ / Claude の `Enter to confirm · Esc to cancel` を blocked |
| v0.9.0 | 2026-09-07 | `[手元]` 成功を返す前に prompt と Enter を送る（#3506, #3685）、terminal 終了時は pending submission を clean に失敗、Claude は背景 MCP task 中も working・背景 shell だけの idle prompt は working のままにならない（#1630, #3090, #3414）。`[relay]` `--wait` は non-working への送信で working か blocked の観測を要求 / 新規 lifecycle 購読は live から / client update は互換 server を止めない / gen 1 未満の server は 1 回の upgrade |
| v0.9.1 | 2026-09-16 | `[relay]` live handoff が 64 pane 超を転送 / narrower hook matching（Claude integration の再 install が要る）/ Claude の MCP 質問・Bash 承認 prompt は回答待ちの間 blocked / terminal title が無くても Claude の visible turn と背景 agent activity を認識 / `agent focus` が attached client を移動 / plugin は稼働 server の互換 binary を使う |
| v0.9.2 | 2026-09-29 | `[relay]` A8 の 0.9.2 修正 / `events_lost` / error 応答が request ID を保つ / self-reported agent は pane が idle shell に戻ると消える / `pane.graphics.*` が `unknown_method`（breaking。先例角度が読んだ） |
| v0.9.3 | 2026-09-29 | `[relay]` v0.9.2 の hotfix（terminal shortcut と Alt-key）。該当 bullet 無し |

- 解けた問い: `agent_prompt_stalled` の導入は v0.7.5、live-agent CLI facade（`agent start` を含む）も v0.7.5。v0.9.0 の release note は `--wait` が non-working への送信で working か blocked の観測を要求すると書く — v0.7.5 の「状態変化の観測なし」との差（観測する状態の限定）は本文で突き合わせていない。
- 導入版が不明のまま: `--until`、`agent explain` の live、`completion_seq`、`server live-handoff`（著者の記録は v0.8.2。`[手元]` の CHANGELOG 抜粋には無い）。`herdr wait` の廃止と `--skill`（v0.8.0）も upstream では未確認。`DOC/cli-reference.mdx` に `herdr wait` は無く `agent wait` と `pane wait-output` だけがある点は著者の記録と整合する。

**A10. 同梱 skill と vendor copy** — `[手元]`
- 同梱 skill は `herdr --skill` で出力される。brew の herdr パッケージ（`/opt/homebrew/opt/herdr`）に skill file は無い（bin・補完・CHANGELOG.md・README のみ）。Hunk は brew パッケージに skills/ を持ち、`~/.claude/skills/hunk-review` はそこへの symlink。
- 手元の vendor copy `~/.claude/skills/herdr/SKILL.md`（origin 行を除く）は `herdr --skill`（0.9.3）の出力と差分なし。著者の vendor skill は 2026-07-18 に通常ファイルとして追加され、git 履歴に symlink への型変更は無い。
- 解けた問い: vendor copy が 0.9.3 出力と同一かは差分なしで確定。spawn-session の内容との重複は未確認のまま。

**A11. roadmap と公開議論** — `ISS-n`、`SRCH` `[relay]`
- roadmap 文書は見つからず（#4764 に milestone / project / roadmap ラベル無し）。公開の要望は、turn・状態・occupant の事前条件つき prompt（#4764 のコメント、未返信）、成功を偽らない prompt（#4537）、self-reported agent へ prompt を送る経路（#4823 not planned、#4732 open）。turn 単位の `--wait` を直接求める issue は可視範囲に無い（3 クエリで可視 45 件）。
- maintainer の見解として読めるのは doc の "It does not track individual turns." と、#4713・#2422 が not planned / not merged で閉じたこと。完了検出を hook 側へ寄せる動き: PR #4756（Codex）、OpenCode V2 の lifecycle reporting（v0.9.1）。

### B. Claude Code のセッションとメッセージ（Claude Code 2.1.296）

要点:
- `[手元]` `claude agents --json`（2.1.296）は対話 session にも `status`（idle / busy / waiting）・`sessionId`・`pid`・`name`・`cwd` を返す（約 0.2 秒/回）。Herdr の `agent_session.value` は Claude の sessionId および transcript のファイル名と一致（1 件）。Claude pane の完了判定を screen 解析でなく公式 CLI に寄せられる候補で、Codex は対象外。status の精度は未測。
- 作業中の Enter は Claude Code が queue し、同じ turn に吸収する（公式 interactive-mode）。turn 終端で queue が黙って落ちる open bug がある（anthropics/claude-code #85603、macOS tmux、2.1.220/226）。transcript に `queue-operation`（enqueue / dequeue / remove）が記録され、無言ドロップの切り分けに使える可能性がある（意味は未文書）。
- Stop hook は `background_tasks` / `session_crons` を渡し、「本当の終わり」と「背景作業待ちの Stop」を区別できる。ただし user interrupt では発火せず、API error は StopFailure、UserPromptSubmit は prompt 以外（背景 subagent の報告など）でも発火し、Stop の重複発火の報告がある。
- Cross-session messaging（SendMessage / ListAgents）は `herdr agent prompt` の代替にならない: Claude↔Claude のみ、LLM が呼ぶ tool で shell から呼べない、受信側が bypass 系 mode で送信側が非 bypass だと承認待ち→5 分で破棄、着弾確認の仕様が無く silent 不達の bug 報告が複数（未検証）。`notify_when_idle`（v2.1.236+）も main conversation の Claude が購読する。
- 2026-08-17〜21（v2.1.234〜239）に Remote Control の device card（スマホから directory を選んで session を起こす）が公式に入った。「公式手段が無い」前提（2026-08-01 確認）は失効の可能性が高い。RC 参照ページは追随しておらず、folder 一覧の中身は未実測。device card 経由の session は server プロセスの子で、Herdr pane の外になる。

**B1. `claude agents --json` と session の対応付け** — `[手元]`（2026-10-10、Claude Code 2.1.296）、agent-view `[relay]`
- `claude agents --json` は対話 session（kind: interactive）にも `status`（idle / busy / waiting）と `sessionId`・`pid`・`name`・`cwd` を返した（手元 32 件の interactive: idle 30、busy 2）。background session は `state`（例 blocked）。1 回約 0.2 秒（初回 0.6 秒）。`claude agents --help`: "--json Print active sessions (interactive and background) as a JSON array and exit"。
- `herdr agent list` の Claude agent は `agent_session: {"agent":"claude","kind":"id","source":"herdr:claude","value":"<uuid>"}` を持ち、value は Claude Code の sessionId と一致し、`~/.claude/projects/<project>/<value>.jsonl`（transcript）のファイル名になる（1 件で確認）。agent の JSON は `state_change_seq` と `revision` も持つ。
- doc 側（agent-view `[relay]`）: `--all` で完了済みも、`--cwd <path>` で絞れる。docs は "polling `claude agents --json --all` from scripts" を勧め、`~/.claude/jobs/` 配下は安定 interface でないと警告する。interactive にも `status` が付くかは要約から読み切れなかった。
- 解けた問い: interactive session に `status` が付くか（付く）、Herdr の `agent_session.value` を Claude の session ID と結べるか（1 件で一致）。
- 移せる部分: Claude pane の done 判定を `status` の polling に寄せられる候補（Codex は対象外）。hook の `session_id` との一致は未照合。status の精度と遅延は未測（手元は分布と呼び出し時間のみ）。

**B2. queue と入力の取り扱い** — https://code.claude.com/docs/en/interactive-mode "Queue messages while Claude works" `[raw]`（公式 doc）、anthropics/claude-code #85603 `[relay]`、ローカル transcript（実機観測、key 名のみ）
- 公式（逐語）: "Type a message and press `Enter` while Claude is working. Claude Code queues the message instead of interrupting the turn, and lists the queued entries in the conversation until it sends them." tool call 中に queue すれば "as soon as those tool calls finish, within the same turn" に渡り、turn 終了時に queue が残っていれば追加の key 無しで入力順に送られる。commands と shell commands は turn 終了まで保留。`Ctrl+Enter` は待たずに送る（v2.1.275+。端末が extended keys を報告しないと `Enter` として届き queue するだけ）。`Esc` は draft を送らず turn を中断し、queue は即送られる。背景 Bash 中も新しい prompt は受理される。
- 含意（推論）: working 中の送信は同 turn に吸収され、新しい turn は始まらない。`--wait --until working` は「すでに working」で即成立して着弾の証拠にならず、1 prompt = 1 Stop も成り立たない。UserPromptSubmit が queue 由来のメッセージで発火するかは doc に記述が無い。
- **#85603**（open、2026-08-10、`area:tui`、2.1.220 / 2.1.226、macOS の tmux pane。120k 字中先頭 100k 字、コメント 1–17）: turn 実行中に打って Enter で submit した入力が、turn が正常終了した後に model へ届かず黙って消える（断続的、pane によっては恒常的）。変種は「消える」と「queue 先頭として描画されたまま消費されない」。Esc で中断してから打つと feed される。報告者は programmatic injection は確実に feed され手打ちの submit が落ちると述べ、tmux 層では両経路は同一で keystroke の間隔と submit の cadence だけが違う、というコメントがある。maintainer の返信は見えた範囲に無い（コメントは全て報告者本人）。記事（aident.ai、2026-08-10 `[relay]`）が #85603 と #20431 を紹介し、回避は Esc→待つ→再送→user turn になったか確認で、著者自身が "confirmed fix ではない" と明記。
- 面・版で割れる報告 `[snippet]`: #49373（2026-04、2026-04-20 resolved）queue が turn 終端でなく次の LLM pause（tool 呼び出しの間）に放出される（desktop/web の報告として要約。CLI に当たるか未確認）/ #50246 / #11106（2.0.34、resolved）。公式の「同 turn に吸収」は #49373 と一致し、仕様の可能性が高い（推論）。
- transcript の観測（key 名の Grep のみ）: `~/.claude/projects/<project>/<session>.jsonl` に `"type":"queue-operation"` の行があり、`operation` は `enqueue` / `dequeue` / `remove` が出ている。公式 doc に記載なし（内部形式で版で変わりうる）。名前から queue への投入・取り出し・取り消しと読めるが意味は未確認。2026-09-23 の 3 回の無言ドロップ（Herdr 0.9.1 期）が「Claude Code が queue を落とした」（enqueue あり dequeue なし）のか「text が TUI に届かなかった」（enqueue すら無い）のかを、ローカルで切り分けられる可能性がある。
- 移せる部分: 「submitted」の証拠は composer が空になったことでなく、transcript に user turn として現れたこと。working 中に送る経路そのものを避けるのは queue 経路の bug を踏まない手段になる（推論）。

**B3. hooks（完了・着弾の信号）** — https://code.claude.com/docs/en/hooks `[relay]`（0–200,000 字。2 つの note が各々読み、末尾 62,610 字は未読）、issue ミラー `[snippet]`
- 33 event。idle / session-state 専用の event は一覧に無い（要約者の所見）。
- Stop: "Runs when the main Claude Code agent has finished responding. Does not run if the stoppage occurred due to a user interrupt. API errors fire StopFailure instead." 入力は共通 field（`session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `effort`, `hook_event_name`）に `stop_hook_active`, `last_assistant_message`, `background_tasks`, `session_crons` が加わる。"The `background_tasks` and `session_crons` arrays let hooks distinguish 'session is done' from 'session is paused waiting for background work to wake it back up'." `background_tasks` の type は shell / subagent / monitor / workflow / teammate / cloud session / MCP task。`last_assistant_message` は transcript より優先（"the transcript file isn't guaranteed to include the final message at Stop time on all versions"。`transcript_path` は非同期書込みで lag しうる）。stop hook が turn を 8 回連続で継続させると次の block を無視する（`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`）。
- UserPromptSubmit: "also fires on turns Claude Code starts on its own"（scheduled task / `/loop`、背景 subagent の報告、他 session の message）。入力は `prompt` と `session_title`。着弾の判定には `prompt` 文面か `prompt_id` の照合が要る。
- Notification の `idle_prompt` は応答後約 60 秒、入力が無く背景 agent が動いていないときだけ。`agent_completed` / `agent_needs_input` は agent view が開いているときだけ。hook type は command（`async: true`）、http（`"onFailure": "block"` は v2.1.295+）、mcp_tool、prompt、agent。Remote Control でも同じ hook event が発火し、`$CLAUDE_CODE_BRIDGE_SESSION_ID` は RC 接続中に設定される（v2.1.199+）。
- doc に書かれていないこと（読んだ範囲）: `run_in_background` の shell が `background_tasks` に載るか / 終了した task が配列から消えるか / 背景完了後に新 turn が始まり Stop が再発火するか / queue 由来メッセージや cross-session message で UserPromptSubmit と Stop が発火するか。
- 既知 bug `[snippet]`（GitHub issue ミラー、修正版未確認）: #24421（2.1.37、2026-03-23 resolved）背景 subagent の完了で Stop が subagent ごとに出た / #54360（2026-04-28 open → 2026-05-30 resolved）注入メッセージが Stop 試行の間に入ると Stop hook が 1 turn 内で複数回走り `stop_hook_active` が false のまま / #70151（2026-06-22、2.1.178→2.1.186 の regression と主張、open）subagent 無しで主 session が Stop と SubagentStop の両方を発火。
- 移せる部分: 完了 = Stop かつ `background_tasks` と `session_crons` が空、という判定が公式入力で組める。interrupt（Stop が出ない）には marker 側の timeout や別手段（画面・`claude agents --json`）が要り、API error は StopFailure、marker は冪等に書く前提になる。

**B4. Cross-session messaging（ListAgents / SendMessage）** — https://code.claude.com/docs/en/cross-session-messaging `[raw]`、tools-reference の 2 行 `[節]`、既知 bug は claudeissues.com（GitHub issue ミラー）`[snippet]`
- 要件と対象: macOS / Linux は v2.1.224+、native Windows は v2.1.234+、有効化操作は不要。同一 machine は Remote Control 不要で Anthropic サーバを通らない（per-session socket）。`/list-agents`（別名 `/peers`）。terminal の CLI session も対象（inbox socket を bind した session のみ）。`claude -p` も bind するが bare mode は bind しない。Claude Code 以外（Codex 等）への言及は無い。名前は `/rename` か `--name`、同名は片方が variant に rename される。`@name` mention は v2.1.232+。
- 配送: 受信 Claude は active turn 中は tool call の間に読み、idle なら新 turn を始める。受信側は送信者ごとの rate-limit・短時間の同一文の破棄・最大 50 件の queue、送信側は約 100 万文字超と burst を拒否。Plain text only。判定は Delivered / Held / Refused。
- 受信側 permission mode（`crossSessionInbound` 未設定時）: 受信側が prompting なら、送信側が自分を bypass と申告したときだけ hold。受信側が bypass なら、送信側も bypass のとき以外は hold。hold は interactive terminal で承認 dialog を出し、`dialogExpiry`（既定 5 分）を過ぎると破棄。無人運用は `--settings` の `crossSessionInbound: accept`。→ spawn された session が bypassPermissions で送信側が bypass でなければ、送った内容は承認待ちで止まり 5 分で消える。受信 Claude は承認も設定変更もできず、message 内の `/compact` などは plain text として届く。
- `notify_when_idle`（v2.1.236+）: Claude が `SendMessage` tool の入力で購読し、その session が次に idle または exit したとき 1 回通知が返る。12 時間で購読は破棄。main conversation の Claude だけが、同一 machine の session にだけ購読できる。→ 公式の完了信号は Claude→Claude 限定で、shell script から直接は呼べない。
- socket と script: hooks と Bash に `CLAUDE_CODE_MESSAGING_SOCKET` と `CLAUDE_CODE_MESSAGING_TOKEN` が export される。auth 行（`{"type":"auth","token":"<token>"}`）は doc にあるが、その後の message 行の JSON schema は無い。外部 process からの投函も同じ inbound controls を通り、own-child と確認できないと permission class を主張しない message として扱われ、bypass 中の session は hold する。
- 既知 bug `[snippet]`（題名のみ、状態未確認）: 受信側の in-flight 背景 Bash を kill（#91139）/ 送信が届かず target が空 turn で固まる（#86279）/ silent drop（#86573）/ queue と描画はされるが届かない（#86629）/ transcript に書かれるが model の context から除外（#87323、v2.1.227）/ 承認後に marker 無しで届く（#85678）/ Desktop 面の tool が "Message sent" を返すが届かない（#86881。CLI の `SendMessage` とは別）。検索要約の一般論（二次、未検証）は「"Message sent" は着弾の証明にならない」。公式 doc は着弾確認を約束していない。手元 2.1.296 で残るかは実測しないと分からない。
- 違い / 評価: `herdr agent prompt` の置換としては、(a) Claude↔Claude のみ、(b) LLM が呼ぶ tool で shell から呼べない（socket への外部投函は可能そうだが schema が doc に無い）、(c) 上記の bypass 非対称で hold→5 分破棄、(d) slash command は実行されない、(e) 着弾確認の仕様が無く bug 報告が複数、の 5 点で足りない。Desktop 面の "Work across sessions" は別機構（"Claude doesn't see … sessions you started from the terminal CLI"）。

**B5. Remote Control・device card・Projects・Dispatch** — remote-control `[raw]`、whats-new/2026-w34 `[raw]`、claude-projects・desktop `[節]`、Dispatch help（https://support.claude.com/en/articles/13947068）`[relay]`
- RC server mode: `claude remote-control` は 1 つの cwd を起点にする。`--spawn`: `same-dir`（既定。"all sessions share the current working directory"）/ `worktree` / `session`（1 session 専用で追加接続を拒否）。`--capacity` 既定 32。参照ページに cwd を切り替える flag・UI は無い。再接続（`-c/--continue`・`--session-id`、v2.1.200+）は停止後約 4 時間以内。
- **device card**（https://code.claude.com/docs/en/whats-new/2026-w34 、2026-08-17〜21、v2.1.234→v2.1.239）: "Any machine running `claude remote-control` now shows up as a device card at the top of the Code tab in the Claude app. Remote Control is also out of research preview." / "Tap it to pick a directory and start a session there." 二次 `[snippet]`: 2026-08-21 告知、folder list が出る、未 trust の folder は承認が要る、`/remote-control`（interactive）でなく bare の `claude remote-control`（server mode）が要る。公式 mobile ページは未読。device card 経由の session は server プロセスの子（"Runs in server mode (no local interactive session)"）で、Herdr pane で観察・操作できない。
- 「a session started from a project」の project は claude.ai の Projects（beta、Pro/Max、Team/Enterprise は不可、段階 rollout）でありディレクトリではない。Projects の "Work locally" は folder を事前登録（Desktop の list か folder ごとの server）し、thread は auto mode、PC が awake で RC 有効の間のみ動き、Require trusted devices が on だと動かず、"You can't add a session you started yourself on your machine to a project."。
- Dispatch: desktop doc は Pro/Max で使えると書き、help は limited beta・新規ユーザー不可・"There's no way to start a new thread or manage multiple threads" と書く。Desktop app 専用で folder 指定の記述が無い。
- 設定と制約: user settings の `remoteControlAtStartup: true` で `--remote-control` 無しでも全 interactive session が RC に出る（project/local settings の true は無視）。認証が不適格なとき `claude remote-control` は error 終了、`claude --remote-control` は interactive session を起動して直後に失敗通知を出す（起動しただけでは接続成功を意味しない）。要件は Pro/Max/Team/Enterprise、API key 不可、Bedrock/Vertex/Foundry・`ANTHROPIC_BASE_URL` 変更・gateway 不可。server mode は未 trust directory で "Trust <directory>? [y/N]" を聞き、stdin/stdout が terminal でないと "Workspace not trusted" で終了する。同一 conversation を 2 つ目の terminal で resume すると "Remote Control not started here"（1 interactive process = 1 remote session）。push 通知は Claude が送るかを決める人間向けの信号で、turn 終了の機械的な信号ではない。
- 違い / 移せる部分: 「iPhone から別プロジェクトを起こす」だけが目的なら、Mac 側で `claude remote-control` を常駐させる公式経路が存在する。RC 参照ページと digest は噛み合わない（Contradictions 5）。

**B6. Agent view と `claude --bg`** — agent-view `[relay]`（前半）+ version 表 `[raw]`、cli-reference `[raw]`
- research preview（v2.1.139 導入）、local 限定。`claude --bg "<prompt>"` は agent view を開いた directory で detached 起動する（`-p` と併用不可、起動前に workspace trust を確認）。別 directory へは cd してから起動、または `claude agents` で `@<repo>` mention。background の `claude agents --json` entry は `id`、`state`（working / blocked / done / failed / stopped）、`pid`、`status`、`waitingFor`、`sessionId`、`name`。操作は `claude attach <id|name>`（name は v2.1.290+）・`logs`・`stop`・`respawn`・`rm`・`daemon`。実行中の bg session へは `claude --resume <name> "prompt"` で次の turn として渡る（v2.1.285+）。未 attach の finished / waiting session は約 1 時間で停止し、会話は disk に残って attach か reply で resume する。
- 通知は v2.1.198+ で `preferredNotifChannel` と `Notification` hook（`agent_needs_input` / `agent_completed`）。hooks ページは `agent_completed` が agent view を terminal で開いている間だけと書く。bg session が Remote Control に出るかは doc 未記載。pane を持たない。「cwd 指定で起動 → 名前で再接続 → 状態を JSON で polling」は公式 CLI が一式で提供する。

**B7. CLI flag** — cli-reference `[raw]`、`[手元]` の `claude --help`（2.1.296）
- `claude "query"` は初回 prompt 付きで interactive 起動。`--name` / `-n` は local の display name（`/resume` と terminal title、`claude --resume <name>`）で、同名の live session があれば variant になる。`--remote-control` / `--rc [name]`。RC の title は `--name` / `--remote-control` / `/remote-control` で渡した名前が優先され、`/rename` が次。`--settings` は path か inline JSON で、session 単位に `crossSessionInbound` や hooks を注入できる。`--bg`、`--cloud`、`--desktop`（v2.1.285+）。
- `[手元]` `claude --help`: `--effort <level>`（low, medium, high, xhigh, max）、`--permission-mode <mode>`（acceptEdits, auto, bypassPermissions, manual, dontAsk, plan）、`--remote-control [name]`、`-n, --name <name>`。cli-reference の表との差は Contradictions 8。cli-reference は "`claude --help` does not list every flag" と書く。
- `--remote-control [name]` は optional-value のため、positional prompt と並べたときに prompt が name に食われるかは未実測。

### C. plugin 仕様（Claude Code 2.1.296 時点の公式 docs）

要点:
- `[手元]` `claude plugin validate`（repo root の marketplace.json と plugin.json の両方、`--strict --json`）は現行 v2.0.0 で errors 0・warnings 0。両 manifest の同時検査に要る v2.1.289 以降を手元 2.1.296 は満たす。
- SKILL.md 本文の `${CLAUDE_SKILL_DIR}` は直置き（`~/.claude/skills/`）でも plugin でも「SKILL.md のある dir」に置換され、現行の「path を推測させる」一文を置き換えられる。`${CLAUDE_PLUGIN_ROOT}` は plugin skill 限定で、Bash tool の env には無い（script 内は自位置を `BASH_SOURCE` / `$0` で解決する）。
- `bin/` は plugin 有効な session の Bash tool の PATH に載る。launchd・素の terminal・他の hook には載らず、外部呼び出し用の stable path を spec は与えない（cache は version ごとの dir、旧 dir は 14 日後に消える）。公式 marketplace で `bin/` を使う例は読んだ範囲で 0（`scripts/` が主流）。
- version は plugin.json の `version` だけに書く現行形が公式推奨で、bump しない限り利用者に届かない。third-party marketplace の auto-update は既定 off（手動 update の手順が要る）。
- `claude plugin eval` は skill の発火・応答の検査用で、Herdr の I/O は sandbox の外 — script の挙動は bats、発火と指示追従は eval という補完関係になる。公式 plugin に bats の先例は読んだ範囲で無い。

**C1. `claude plugin validate`** — https://code.claude.com/docs/en/plugins/cli-reference#plugin-validate 、plugins-reference#validate-the-manifest 、plugins/marketplace-reference#validation-messages `[raw]`（公式 doc）、`[手元]`
- `[手元]` `claude plugin validate .claude-plugin/plugin.json --strict --json` と、repo root（marketplace.json）への同コマンドは、現行 herdr-toolkit v2.0.0 で errors 0・warnings 0。
- 仕様: `claude plugin validate <path> [--strict] [--json]`。exit 0（passed、warning 含む）/ 1（failed、または `--strict` で warning）/ 2（validator 自体の失敗）。`--json` は v2.1.259+。marketplace.json と plugin.json が同居する dir は両方を検査する（"This requires Claude Code v2.1.289 or later."。2.1.289 の changelog にも "Fixed `claude plugin validate` skipping the plugin when the folder also holds a marketplace manifest" `[relay]`）。skills / agents / commands の中身を検査し、plugin root の `CLAUDE.md` に警告、plugin root の `SKILL.md` は読まず、skills / agents / commands 内の symlink は辿らない。未知の top-level field は警告で、`--strict` で失敗になる。2.1.295 で README に install 行が無い plugin への advice が追加された `[relay]`。bin / scripts の実行 bit や script の中身は検査対象として明記されていない。
- 解けた問い: 著者環境の Claude Code は 2.1.296 で要件（2.1.289+）を満たす。現行 SKILL.md の frontmatter に `origin: shimo4228` と `user-invocable: true` がある（cc-plugin が repo の実ファイルで確認）ので、未知の frontmatter key `origin` は `--strict` でも warning にならない（推論）。

**C2. 変数の置換先と `${CLAUDE_SKILL_DIR}`** — plugins-reference#environment-variables 、plugins/components#path-variables-and-persistent-data `[raw]`、skills `[relay]`（先頭 94%）
- `${CLAUDE_PLUGIN_ROOT}` = インストール済み version の絶対 path、`${CLAUDE_PLUGIN_DATA}` = `~/.claude/plugins/data/<id>/`（update をまたいで残る。`<id>` は `herdr-toolkit@herdr-toolkit` → `herdr-toolkit-herdr-toolkit`）、`${CLAUDE_PROJECT_DIR}`。置換される場所: hook の `command` / `args`、monitor の `command`、MCP stdio、LSP、skill・command・agent の Markdown 本文全体。env に export される先: hook（ROOT / DATA / PROJECT_DIR / OPTION_*）、MCP stdio（ROOT / DATA）、LSP。monitor には export されない。
- "The variables aren't present in the environment of commands Claude runs through the Bash tool, in the main session or in a subagent." 本文に書いた `${...}` は読み込み時に絶対 path へ置換されて Claude に見える。
- `${CLAUDE_SKILL_DIR}`: "The directory containing the skill's `SKILL.md` file. For plugin skills, this is the skill's subdirectory within the plugin, not the plugin root." 置換される場所は skill の本文と frontmatter `allowed-tools` の Bash rule。`${CLAUDE_PLUGIN_ROOT}` は "Substituted only in plugin skills." 公式例は `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)` と本文 `Run ${CLAUDE_SKILL_DIR}/scripts/render.sh <csv-file>`（"lets a skill run a bundled script without a permission prompt"）。
- 違い: 現行 SKILL.md の手順 2 は「`spawn.sh` は本 SKILL.md と同じディレクトリにある（直置きなら…、plugin 導入なら…）」と Claude に path を推測させ、`bash <dir>/spawn.sh …` と呼ぶ。公式例は script を直接 exec する形で、`bash ` 接頭辞付きの command に Bash rule が一致するかは doc に無い。plugin skill の `${CLAUDE_SKILL_DIR}` は `skills/spawn-session/` で plugin root ではないため、script を plugin root の `bin/` や `scripts/` に置くと、直置きモード（`${CLAUDE_PLUGIN_ROOT}` 非置換）の SKILL.md から届かない。skill dir に置けば両モードで届く。
- 移せる部分: `${CLAUDE_SKILL_DIR}/spawn.sh` で両モードの推測が要らなくなる。Bash で走る script 内では自位置を `BASH_SOURCE` / `$0` で解決する（公式 test も file 相対、C5）。

**C3. `bin/` と外部（launchd 等）からの呼び出し** — plugins/components#executables 、plugins-reference#standard-layout 、plugins/host-marketplace 、plugins/loading#find-plugins-on-disk 、#in-place-and-copied-plugins 、#cleanup-of-previous-versions 、plugins/cli-reference#plugin-list `[raw]`
- 仕様（逐語）: "Files in `bin/` at the plugin root are on the `PATH` of the Bash tool's shell while the plugin is enabled, so Claude can run them as bare commands." `chmod +x` が要る。PATH は user 自身の entries の後ろで、system command を shadow できない。claude.ai と Cowork は top-level `bin/` を持つ plugin を install せず、org sync は `Plugin contains a top-level bin/ directory` で拒否する（host-marketplace は実行物を `scripts/` に置き `${CLAUDE_PLUGIN_ROOT}/scripts/<name>` で hook / MCP から参照と案内）。導入は v2.1.91（2026-03-30 の週）— WebSearch の要約が issue #42872 の changelog 引用に依拠 `[snippet]`。
- cache は `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`。"Because `${CLAUDE_PLUGIN_ROOT}` points at a version directory, a plugin's root path changes with every version." 旧 version dir は update / uninstall 後 14 日で消える（`.orphaned_at`）。例外: marketplace を local path で追加（`claude plugin marketplace add ~/path` = `directory` source）すると relative-path plugin は in place で読まれ、version を上げなくてよい（`CLAUDE_PLUGIN_ROOT` は source dir）。`claude plugin list --json` の各要素に `id` / `version` / `scope` / `enabled` / `installPath` が入り、in-place の plugin には `readFromFolder`（v2.1.289+）が付く。docs に「現行 version を指す固定 symlink」「install path を出す専用 command」は無く、launchd 用の推奨手順も無い。
- 違い: 現行 SKILL.md Notes の `~/bin/cc-spawn` → `spawn.sh` の symlink を cache 内へ張ると、update から 14 日後に dangling になる。
- 移せる部分（推論。docs が外部呼び出しの手順として示したものではなく、実機未検証）: (a) 固定の clone path（著者の canonical `~/.claude/skills/spawn-session/` または repo path）を直接呼ぶ。(b) launchd script 側で `claude plugin list --json | jq` により `readFromFolder // installPath` を引く（`claude` の PATH と起動コストが条件）。(c) SessionStart hook が `${CLAUDE_PLUGIN_DATA}` 配下へ copy / symlink を更新し、launchd はそちらを呼ぶ（hook の追加は boundary.md で「人間に渡す」対象）。`bin/agent-send`（拡張子なし・実行 bit 付き）は Claude セッション内から bare 名で呼べる。`bin/` を symlink にして `skills/spawn-session/agent-send.sh` を指す形は、host-marketplace に "Within the plugin's own directory: the symlink is preserved as a relative symlink in the cache" とあるが実機未検証。
- 反証: v2.1.290 の "Fixed the Bash tool occasionally losing shell aliases, functions and plugin PATH entries for a whole session"（changelog `[relay]`）— bare 名で呼ぶ設計は PATH 欠落に弱く、絶対 path（`${CLAUDE_SKILL_DIR}/…`）は影響を受けない。issue #95653（題名のみ `[snippet]`）は plugin `bin/` entries が存在確認なしで PATH に追加され Windows の 8191 字制限を超えるという件で、macOS に直接は関係しない。

**C4. 公式 marketplace の shell script 同梱** — https://github.com/anthropics/claude-plugins-official の tree（GitHub API）`[relay]`（0–200,000 字を確認、末尾 13.6K 字は未読）。根拠は採用実績
- ralph-loop（hooks/stop-hook.sh・scripts/setup-ralph-loop.sh）、security-guidance、claude-security、plugin-dev（`skills/*/scripts/*.sh`）、math-olympiad、code-modernization（`scripts/telemetry.sh`）が shell script を同梱する。読んだ範囲に `bin/` は 0 件、`.bats` も 0 件。components ページ: "The name `scripts/` is a convention, not something Claude Code looks for"。
- ralph-loop の command は `allowed-tools` が setup script 1 本に限定した Bash rule で、本文が `CLAUDE_PLUGIN_ROOT` 経由で呼ぶ形（`[relay]`・要約のみ・低信頼）。公式は hook から呼ぶ用途が中心で、「skill 本文 + 外部 script の両方から同じ script を呼ぶ」実例は読んだ範囲に無い。

**C5. 公式 plugin 内の test** — `plugins/code-modernization/scripts/tests/test_telemetry.py`（ほか `scripts/tests/test_*.py` 計 7 本、`tests/*.test.ts`）`[relay]`（要約。逐語でない）。根拠は採用実績
- 約 600 行・約 66 test の unittest。plugin 位置は `dirname(dirname(HERE))` と file 相対で決め、`CLAUDE_PLUGIN_ROOT` は使わない。shell script は `subprocess.run(["/bin/sh", …, mode], input=json, cwd=<tmp>, env=<fresh dict>, timeout=60)` で起動して exit 0 を assert。env の PATH は「偽 bin dir + /usr/bin:/bin」、`CLAUDE_PLUGIN_DATA` は一時 dir、`HOME` は隔離していない。「Shipped」群は、`hooks.json` を regex `\$\{CLAUDE_PLUGIN_ROOT\}/(scripts/\w+\.sh)` で解析して参照先 script の存在を assert、manifest に `version` があること、CHANGELOG 先頭の版 = manifest の版、README の key 一覧の一致。test は plugin 内 `scripts/tests/` に同居し配布物に含まれる。
- 移せる部分（bats に書き換え可）: fake bin を PATH 先頭に置いて外部 CLI（`herdr`）を stub、参照先 script の存在検査、plugin.json の version と CHANGELOG 先頭の一致検査。`plugin-dev` の `test-hook.sh` は名前から hook の試験用 utility で test suite ではない（内容は未読）。

**C6. version と利用者への配布** — plugins/loading#how-claude-code-computes-the-version 、#when-auto-update-runs 、host-marketplace#release-a-new-version 、#keep-users-up-to-date 、plugins-reference#version 、plugins/cli-reference#plugin-update 、#plugin-tag `[raw]`
- 優先順位は plugin.json の `version` > marketplace entry の `version` > source 型の既定（github / url / git-subdir は commit SHA 先頭 12 字、git-hosted marketplace 内の relative path は installed directory の commit SHA、git でない local dir は `unknown`）。"a manifest that pins "version": "1.0.0" keeps every user on the cached copy until its author changes the string, however many commits they push." 両方に書くと plugin.json が黙って優先され、validate が `Entry declares version "<a>" but <path>/plugin.json says "<b>"` と警告する。entry の version は `claude plugin list --json --available` が未 install の plugin を出すときの表示にしか効かない。
- 現行は plugin.json に `2.0.0`、entry に version なし（公式推奨どおり）。version を両方から消すと main への全 commit が update 対象になる。
- auto-update の既定は Anthropic 公式 marketplace と claude.ai 追加分が on、"off for every other marketplace"（利用者が `/plugin` > Marketplaces > Enable auto-update、または管理者が managed settings の `extraKnownMarketplaces` に `autoUpdate: true`）。自動更新は interactive session の最初の message の後、最大 10 分のランダム遅延を置いて走り、走行中の session は旧 version のまま `Plugin updated: <name> · Run /reload-plugins to apply` を出す。手動は `/plugin marketplace update <name>` または `claude plugin update <plugin>@<name>`、反映は次の session か `/reload-plugins`。`claude plugin install name@marketplace` は install 前に当該 marketplace を refresh する。`already at the latest version` なら計算された version が同じ（bump 忘れ）。2.1.289 に "Fixed `plugin list`, `plugin eval` and `plugin update` showing a stale copy of a plugin"（`[relay]`）。
- `claude plugin tag [path] [--push] [--dry-run] [-f] [-m <msg>] [--remote <name>]` は `<name>--v<version>` の annotated tag を作り、前に plugin.json と marketplace entry の version 一致を検査する（失敗: version 無し・tag 既存・working tree dirty）。docs が示す tag の意味は、依存 plugin の version range 解決が `<plugin>--v<version>` を引くこと。依存されない leaf plugin では必須でない。root が marketplace 兼 plugin のとき entry を見つけるかは未検証。

**C7. `claude plugin eval`** — https://code.claude.com/docs/en/plugin-evals 、plugins/cli-reference#plugin-eval `[raw]`（509–594 行の field 表は未読）。公式 doc。実機未実行
- 要件は v2.1.269+、git 2.31+。通常の Claude Code と同じ認証・model provider（サブスクで走る。実行ごと・judge ごとに実モデル呼び出しで plan の使用量に数える）。最小構成は `claude plugin eval init --bare first-case`（`evals/first-case/prompt.md` と `graders/criteria.md`）。grader 型は regex / tool_used / tool_order / file_exists / llm / baseline（"There are no custom-code graders."）。既定 3 run × (plugin あり + なし)、`--threshold` 既定 1.0、`--max-cost-usd`、`--no-publish`。
- 隔離: 各 run は一時 HOME / cwd / Claude Code config の `claude -p` 子プロセスで、user settings・hook・CLAUDE.md・MCP・他 plugin・memory・skill は不在。`Bash` などは `--allow-tools` で付与しない限り tool pool から外れ、付与しても OS sandbox 下で home と Claude 設定は読めない。gating の troubleshooting は "early access" と "unavailable"（server-side off）の 2 項。
- 違い / 移せる部分: 検査できるのは skill が選ばれるか・応答に特定の語や指示が出るか。Herdr socket、実 `herdr` binary、`~/.claude` は届かないので、agent-send の着弾・完了判定は eval の対象外。skill の発火 case（`tool_used: Skill`）を 1〜2 件置く程度なら最小構成で足りる。

**C8. SKILL.md frontmatter と repo 側の事情** — skills `[relay]`（先頭 94%）、ローカル repo の実ファイル
- 全 field が optional で "Only `description` is recommended"、"Claude Code ignores a field it doesn't recognize without reporting an error." 認識される field: `name`, `description`, `when_to_use`（合計 1,536 字上限）, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`（既定 true）, `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context`（`fork`）, `agent`, `background`（v2.1.218+）, `hooks`, `paths`, `shell`, `metadata`（自由な YAML map）, `license`, `compatibility`（受理するが何もしない）。Claude Code 外（claude.ai upload・Skills API・`package_skill.py`）は `name` / `description` / `license` / `compatibility` / `metadata` / `allowed-tools` のみ許可で、他の key は hard error。plugin skill の呼び出し名は `/plugin-name:skill-name`（`/herdr-toolkit:spawn-session`）。
- 違い: 現行の `user-invocable: true` は有効（既定値と同じ）。`origin: shimo4228` は Claude Code で黙って無視されるが、claude.ai / API 経路に載せると hard error で、`metadata:` 配下が合法な置き場。SKILL.md 本文の `/spawn-session [project]` は plugin 導入時 `/herdr-toolkit:spawn-session`。
- `scripts/sync-from-local.sh` は `SUBTREES=(skills)` だけを staging から `rm -rf skills` → `cp -R` し、root files と `.claude-plugin/` manifests は触らない（許可リスト `SKILLS=(spawn-session)`、prune は `results.json` / `*.log` / `*.pyc` / `.DS_Store` / `MAINTENANCE.md`）。したがって `skills/spawn-session/` 配下の追加 file は harness 側に正本があれば同期で運ばれ、repo にだけ置いた file は次の sync で消える。plugin root の `bin/` / `scripts/` / `tests/` は同期の対象外で repo 側が正本になる。`has_origin` は先頭 15 行に対する `grep -F "origin: shimo4228"` で、`metadata:` 配下にインデントして置いても一致する見込みだが、ハーネス側 lint の扱いは未確認。
- `source: "./"` の self-owned marketplace は docs の範囲内（"`.` on its own means the root itself"、`./` で始める）。entry 名と plugin.json の `name` は一致し、component 系 field は無く `strict` 既定 true で支障はない。entry に `skills` を足すと既定の `skills/` 走査が止まる。

**C9. monitors component（未深掘り）** — plugins/components#monitors 、plugins-reference#monitors `[raw]`
- `monitors/monitors.json`（または manifest の `experimental.monitors`）に `{name, command, description, when}` を置くと、session 中ずっと動く background の shell command になり stdout が Claude への通知になる。interactive 限定（`-p` では起動しない）、sandbox の外で user 権限、`when: "on-skill-invoke:<skill>"` で skill 初回起動時に開始できる。`command` には path 変数が置換されるが env には export されない。
- SKILL.md の「`done` を polling する bash loop」の代替候補になりうるが、Remote Control で動くか、Herdr の状態と相性が良いかは未確認。experimental で manifest 形が変わりうる。

### D. 先例と反証

要点:
- 同種ツールで着弾確認まで実装していたのは agent-deck のみ（読んだ範囲）: 「入力欄に入った」と「turn が受理された」を分け、証拠なしを `no_evidence` として非ゼロ exit にする。send 経路だけで少なくとも 7 release を重ねており、保守負担の傍証。claude-squad は着弾確認も完了判定も持たない。
- 「working なら待つ」「`--until working` で着弾確認」の前提への反証: working 中の送信は Claude Code が同 turn に吸収するので、`--until working` は即成立して着弾の証拠にならない（推論）。
- 「入力欄に残っていれば Enter を 1 回」は、blocked 検出の遅れ（0.26–0.30 秒）の間に承認ダイアログへ Enter が入る競合を持つ（#4764 のコメント）。script は atomic にできない。
- hook 方式（UserPromptSubmit / Stop の marker）は Claude Code に強い材料だが Codex に届かない（Codex の `notify` は turn 完了のみ）。取りこぼしは interrupt、prompt 以外での UserPromptSubmit 発火、queue 吸収、Stop の重複発火。
- Herdr は 3 週間に stable 4 本、うち `agent prompt` の意味に触れたのは 1 本。Claude Code の版更新で tmux 上の submit 経路が壊れた前例も複数ある。

**D1. claude-squad（`session/tmux/tmux.go`）** — https://raw.githubusercontent.com/smtg-ai/claude-squad/main/session/tmux/tmux.go （main、取得 2026-10-10）`[relay]`（ファイル全体、行番号と逐語は未確認）。採用実績（OSS）。本件の問いには答えを持たない negative finding
- `tmux send-keys` を使わず、`tmux attach-session` に繋いだ PTY へ `ptmx.Write` で生バイトを書く。`TapEnter()` は 0x0D を 1 byte。送信経路に sleep なし、bracketed paste の扱いなし。`HasUpdated()` は `capture-pane -p -e -J` の SHA-256 が前回と違えば updated（`-e` で ANSI を含むので spinner の再描画も updated。初回呼び出しは常に updated）。完了を示す関数は無く、`updated==false` と `hasPrompt` から呼び出し側が推測する。prompt 検出は部分文字列一致で、Claude は "No, and tell Claude what to do differently"、Aider は "(Y)es/(N)o/(D)on't ask again"、Gemini は "Yes, allow once"。trust prompt（"Do you trust the files in this folder?" / "new MCP server"）は 1 回確認して Enter（ループは呼び出し側）。
- 違い / 移せる部分: 本件は Herdr が画面検出を内蔵し `agent get` / `agent wait` を使える。承認ダイアログを画面文言で見分ける先例（文言は Claude Code の版で drift しうる、as-of 不明）。

**D2. agent-deck（asheshgoplani/agent-deck）** — https://github.com/asheshgoplani/agent-deck/releases/tag/v1.11.0 （取得 2026-10-10、release 日付は読めていない）`[relay]`。採用実績（release notes）
- `session send` が、pane に届いたが submit 未確認の場合に非ゼロで終了する。"Previously these cases exited 0, so a script that treated exit 0 as 'delivered' could silently drop work at an agent's composer." outcome: `success` / `submitted` → 0（`--json` の `submitted:true`）、`typed`・`typed_not_submitted`・`line_too_long`・`no_evidence`・`send_failed` → すべて 1（`submitted:false`、`code: delivery_failed`）。再試行の指針は `typed` / `typed_not_submitted` が再送、`line_too_long` は再送不可（行を分けるか file 参照にする）。判定の内部ロジック（pane diff か paste marker か hook か）は release 本文に無い（PR #1831、issue #1793）。
- 二次 `[snippet]`（release 本文は未読、参考扱い）: v1.12.0 複数行は scoped paste marker で着弾確認 / busy な Claude には即入力し Claude 側の queue に入る、判定は delivered / queued / unknown で失敗は positive proof を要する / v1.16.24 Codex は send 前の pane snapshot と比較し、入力欄に残って処理の兆候が無ければ typed（submitted ではない）/ v1.7.10 `--no-wait` 前に composer 待ちの preflight（上限 5 s、500 ms settle）/ v1.9.8 `--timeout` が readiness 待ちを延ばさない bug の修正 / v1.10.9 `--defer-if-busy` / v0.24.0 Enter retry loop の hardening と Codex readiness と wait 内の session 死亡検出 / readiness は hook event に寄せ、期限超過時に pane を見る。
- 違い / 移せる部分: tmux 上の Go 実装で、Herdr の `agent prompt --wait` 相当の API を持たず自前で pane を読む。(a) 着弾を typed / submitted の 2 段に分ける (b) 「証拠なし」を失敗の一種 `no_evidence` として名前を付け、exit 非ゼロにする（exit 0 を信じた自動化が入力欄に残った指示を失った、が起票理由）(c) 保守負担の傍証として send 経路だけで少なくとも 7 release（v0.24.0 → v1.16.24）。

**D3. tmux 上の Claude Code への入力の版依存の既知不具合** — GitHub issue の題名・要約 `[snippet]`。issue 報告（版依存）
- #52812 "v2.1.119 REPL ignores all submit keystrokes when stdin is a tmux pane"（Enter も paste-buffer も改行になるだけ。同じ binary が tmux 外では submit。2026-04-28 resolved）/ #52126 tmux 内で貼り付けの改行が落ちる（`paste-buffer -p` なら保たれる）/ #31739 複数行入力を Esc,Esc で中断すると `send-keys -l` が効かなくなる（paste-buffer 経路は有効、`/clear` で復旧）/ #40168・#23513・#33987 Agent Teams の tmux split-pane で shell 初期化前に send-keys され起動に失敗する（Anthropic 自身の tmux 駆動にも競合）。一般ガイドの流儀: text を送る → 短い sleep → Enter を別呼び出しで送る → 再確認し、Enter は draft が残っているときだけ再送。
- 違い / 移せる部分: Herdr は tmux でなく自前 PTY なので同じ症状とは限らない。Claude Code の版更新で submit 経路が壊れた前例が複数あり、script の着弾確認には版ごとの回帰テストが要る。

**D4. Herdr 上流の動向（要望・release 周期）** — `ISS-4764` `[relay]`（取得 2026-10-10）、`REL` `[relay]`（v0.9.1 の本文は "Read more" で切れ、preview build の本文は読めない）
- #4764（A5）: 原子的な precondition 付き prompt の要望が 3 人から出ているが、10 日で maintainer の応答は無く p2。blocked 検出の遅れ 0.26–0.30 秒の間に送った prompt は呑まれ、Enter が "Yes" を選びうる。叩き台の「入力欄に残っていれば Enter を 1 回」は同じ競合を持つ（推論。#4764 自体は `agent prompt` の話）。script は atomic にできない（`agent get` と Enter の間に状態が変わる）。guard を script に置くなら Enter 直前に「state が idle/done」「画面に dialog 文言が無い」「state_change_seq が不変」を同時に確認し、上流が precondition を入れたら捨てられる薄さにする。
- release 周期: stable は 3 週間（2026-09-07 → 09-29）で 4 本。script に効く変更は v0.9.0 の `agent prompt --wait` の意味変更と新規 lifecycle 購読の live 開始、v0.9.1 の `agent focus` の挙動と `pane split` の既定 target、v0.9.2 の `pane.graphics.*` が `unknown_method`（breaking）と `events_lost`。`agent prompt` / `--wait` の意味に触れるのは v0.9.0 の 1 件。上流は着弾確認の肝を release ごとに自分で吸収している（推論。v0.8.0 #1878 → v0.9.0 #3506）。script は Herdr の版を検査して既知の版でだけ動かす案がある（版が未知なら安全側に失敗）。

**D5. Codex 側** — https://learn.chatgpt.com/docs/config-file/config-advanced （developers.openai.com/codex/config-advanced から 308 redirect）`[relay]`、hooks ページは WebSearch の抜粋 `[snippet]`
- `notify = ["python3", "/path/to/notify.py"]` のイベントは "currently only `agent-turn-complete`"。script は JSON 引数 1 個（`type`, `thread-id`, `turn-id`, `cwd`, `input-messages`, `last-assistant-message`）を受け取る。approval-requested は出ない（`tui.notifications` は TUI 内）。project-level の `.codex/config.toml` は `notify` を無視し、user-level `~/.codex/config.toml` が要る。`codex exec` が `notify` を出すかは書かれていない。
- hooks は `hooks.json` か `config.toml` の `[hooks]` で読み込む（`~/.codex/` と `<repo>/.codex/`。project-local は trust 済みのみ）。`[snippet]`: 公式 scope 節に 10 event（PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, UserPromptSubmit, SubagentStop, Stop, SessionStart, SubagentStart）、非 managed の hook は `/hooks` でレビュー・承認するまで実行されない。
- 違い: turn 開始と承認要求を知らせるのは hook 側のみで、`notify` は turn 完了だけ。Claude Code plugin の hooks は Claude Code にしか届かない（推論）ので、Codex 用は plugin の外（`~/.codex/`）に置くことになり、「1 plugin に集約」の形が割れる。Herdr 側では PR #4756 が Codex の hook 報告へ向かう（A3）。

**D6. 上流同梱 skill の配布先例** — Hunk `[手元]`（A10）。Hunk は brew パッケージ内の skills/ へ symlink して追随する。Herdr は brew に skill を持たず `herdr --skill` の出力のみで、vendor copy は通常ファイル。

**D7. 叩き台の各要素との対応**（採否は lead）
1. 「送る前に state を見て working なら待つ」: working 中の送信は queue に入り同一 turn に吸収される（B2）。落ちるのは仕様でなく bug。working 中に送らないことは queue 経路の bug を避ける。ただし idle 判定が画面ベースの間は #5004 の偽 idle が残る（A4）。
2. 「`--wait --until working --until blocked` で着弾確認」: working 中に送ると即成立して証拠にならない（B2、推論）。`blocked` が返った場合は dialog に呑まれた可能性（D4）。agent-deck は typed と submitted を分け `no_evidence` を失敗にする（D2）。
3. 「timeout 時は `state_change_seq` と画面で確定し、入力欄に残っていれば Enter を 1 回」: 先例は agent-deck の Enter retry loop と一般ガイドの「draft が残っているときだけ Enter 再送」（D2, D3）。危険は blocked 検出の遅れの間の Enter（D4）。claude-squad は画面文言で dialog を見分ける（D1）。
4. 「完了 = settled N 回、または `--done-if`」: Claude Code では Stop の `background_tasks` が空かどうかが公式に取れ（B3）、`[手元]` の `claude agents --json` の `status` もある（B1）。画面ベースにこの情報は無い。Codex は `notify` が turn 完了のみ、hook は別機構（D5）。
5. 「代案: plugin に hook を同梱」: Claude Code には強い材料（B3）。取りこぼしは user interrupt で Stop が出ない、prompt 以外でも UserPromptSubmit が発火、queue 吸収で 1 turn に 2 prompt（B2, B3）、Stop の重複発火（B3）。Codex には届かない（D5）。hook の `session_id` と Herdr の `agent_session` の一致は未照合（B1 は Claude の sessionId との一致のみ確認）。
6. 「script に集約すること自体」: 保守負担の傍証は agent-deck の 7 release 以上（D2）、Claude Code の版依存（D3, B2）、Herdr の意味変更 1/4 stable（D4）。上流吸収の兆候は #4764 の要望 3 件（応答 0）と、v0.8.0 → v0.9.0 の着弾確認の吸収（A5, D4）。

## Contradictions

1. **`agent prompt` は Enter まで確実に送るか**: maintainer 側は v0.9.0 で "reliably sends the prompt and Enter"（`[手元]` の CHANGELOG と `REL` が一致）。報告側は 0.9.1 以降も #4537（Linux）・#4990（Linux・devin）・#4529（Windows）が成功応答なのに未 submit と述べる（ユーザー報告、未再現）。macOS + Claude/Codex の直接根拠はどちらにも無く、強さは同程度。#2422 は v0.9.0 の後に not planned で閉じたが、修正済みか放置かは本文未読で判断できない。第三の候補が Claude Code 側の queue 落ち（#85603。報告者は programmatic injection は無事で手打ちの submit が落ちると述べる）。原因の切り分けは transcript の `queue-operation` で可能な見込み（B2）。
2. **v0.9.0 は背景作業中の誤判定を直したか**: `[手元]` の CHANGELOG は v0.9.0 で Claude が背景 MCP task 中も working を保ち、背景 shell だけの idle prompt は working のままにならないとし、#3090 を挙げる。`SRCH`（`[relay]`）では #3090 が 2026-10-10 時点で open（更新 09-14、v0.9.0 の後）で、背景 subagent の #5004（2026-10-06）も open。部分修正か再発か管理上の未 close かは本文未読で決められず、どちらの根拠も強くない。
3. **`server live-handoff` の有無**: 著者の記録は v0.8.2 導入。`[手元]` の 0.9.3 `server --help` と v0.9.3 doc は一致して handoff を `herdr update --handoff` と `herdr --remote … --handoff` のみとする。実測が強く、記録が古い。ただし status JSON に `server.capabilities.live_handoff` が残り、subcommand がいつ・なぜ無くなったか（別名へ移ったか）は不明。
4. **PR #4756 と v0.9.3 doc**: PR（Codex の hook 経由の working/idle 報告）は 2026-09-29 に merged だが、v0.9.3 の integrations doc は Codex を screen 検出と書く。入る版が v0.9.3 より後か、doc が追随していないかは不明。
5. **RC 参照ページ vs Week 34 digest**: 参照ページ（`[raw]`）は `--spawn same-dir` を "all sessions share the current working directory" とし、cwd を切り替える UI を書かない。digest（`[raw]`）は device card で directory を選んで session を起こせると書く。参照ページが digest に追随していない可能性が高い（推測）。folder 一覧の中身は実測するまで決められない。
6. **Dispatch の利用条件**: desktop doc は Pro/Max で使えるとだけ書き、help article は limited beta・新規ユーザー不可と書く。note は制約が強い help を採った。
7. **interactive session の `status`**: agent-view の要約（`[relay]`）では読み切れず、note は「実測する価値が高い」とした。`[手元]` で付くと確定した（解決済み）。
8. **flag 値の集合**: cli-reference（`[raw]`）は `--effort` に `ultracode`、`--permission-mode` に `default` を挙げ、`[手元]` の `claude --help`（2.1.296）の列挙には無い。doc は help が全 flag を列挙しないと書くので、受理されるかは未実測。
9. **Codex hooks の成熟度**: 公式 scope 節の 10 event（`[snippet]`）に対し、第三者記事は 2026-03 時点で `codex_hooks` feature flag の下の実験機能（v0.114.0）とし、event 数の記述も割れる。一次資料の本文を未読のため現行は決められない。
10. **`bin/` の位置づけ**: 仕様は v2.1.91+ で `bin/` を PATH に載せる（`[raw]`、導入版は `[snippet]`）。一方、公式 marketplace の実例は `scripts/` 系で `bin/` は読んだ範囲で 0 件、v2.1.290 に PATH 欠落の fix がある（`[relay]`）。機能の存在と採用実績の差で、矛盾ではなく緊張。
11. **抽出の重複**: v0.9.0 と v0.9.1 の両方に "Claude Code MCP questions and Bash approval prompts now stay blocked" がある（`REL`、`[relay]`）。重複の可能性。`[手元]` の v0.9.0 抜粋は網羅でなく突き合わせは未了。
12. **強め合う点**: A2（working 中に送ると `--wait` は進行中 turn の完了で返りうる）と B2（Claude Code は作業中の入力を同 turn に吸収する）は別の source から同じ結論に至る — `--wait` の返りは新しい prompt の turn の完了を意味しない。

## Still unknown

notes の Still unknown のうち `[手元]` で解けたもの（`claude agents --json` の interactive `status`、`herdr server --help` の `live-handoff`、`herdr status` の field 名、#4537 の本文、`agent_prompt_stalled` の導入版、`herdr --skill` と vendor copy の一致、`origin` key の validate 結果と Claude Code の版）は Found に移した。残りを、lead が手元で一手に確かめられるものから順に置く。

手元で一手に確かめられるもの:
1. `completion_seq` の載る response と導入版: `curl -fsSL <DOC>/agent-automation.mdx | grep -n -B3 -A3 completion_seq`（`DOC` は A 節の別名）、手元で `herdr agent get <pane> --json`。
2. `--until`・`agent explain` の live・`completion_seq`・`server live-handoff` の導入版: brew 内 CHANGELOG.md の grep、または `gh api repos/herdrdev/herdr/releases --paginate -q '.[] | [.tag_name,.published_at,.body] | @tsv'`。
3. #4537 が macOS・0.9.3 で再現するか（使い捨ての `--no-focus` pane に `agent prompt`）。
4. Claude の workspace trust dialog が blocked と判定されるか（使い捨て pane で dialog を出して `herdr agent explain <pane> --json`）と、稼働 server 0.9.1 で live `agent explain` が動くか。
5. manifest の remote 更新が herdr の版と独立か、stale な server でも取り込まれるか: `herdr server agent-manifests --json`。
6. `herdr status` 各 field の意味（名前と値は確定、定義は upstream に無い）と `server.capabilities.live_handoff` の値: clone して `rg server_binary_stale restart_needed endpoint_compatible`。
7. PR #4756 が入る版と、Claude 側に同種の hook 報告が来る予定か: `gh pr view 4756 --repo herdrdev/herdr`、tag 比較。
8. 可視範囲外の issue（検索 1,154 件中 1,138 件、86 件中 70 件）に macOS + Claude/Codex の未 submit・偽 idle があるか: `gh issue list --repo herdrdev/herdr --state all --search 'agent prompt in:title' --limit 100`。preview channel の最新版: https://herdr.dev/llms-preview.txt 。
9. 2026-09-23 の 3 回の無言ドロップ当時の Claude Code 版と、その transcript の `queue-operation`（enqueue / dequeue の有無）。
10. `claude` が `--effort ultracode` と `--permission-mode default` を受理するか。

実機実験が要るもの:
11. `claude agents --json` の `status` が実際の作業状態と一致する精度と遅延（手元は分布と呼び出し時間のみ）。hook の `session_id` が Herdr の `agent_session.value` と同値か（後者が Claude の sessionId と一致するのは 1 件確認済み）。
12. optional-value flag と positional prompt を並べたときの解釈（`claude --name X --remote-control "<prompt>"` で prompt が RC 名に食われるか）、`--remote-control "<name>"` が local 名（ListAgents の宛先）にもなるか。
13. device card の folder 一覧の中身（任意 directory か既知 project のみか）、`--spawn` 各 mode での有効性、card 経由の session が `/list-agents`・`claude agents` に出るか。`--bg` session が RC に出るか、`remoteControlAtStartup` が bg に効くか。
14. socket に直接書く message 行の JSON schema、同一 machine の `SendMessage` が返す tool result の文言（delivered / held / refused を送信側が区別できるか）、B4 の既知 bug（特に #91139）が 2.1.296 で残るか。
15. 短い turn（数百 ms）で `agent_prompt_stalled` が偽陽性になるか【推測】。
16. plugin 側: cache への copy で実行 bit が保たれるか、`source: "./"` で repo 全体（tests/・docs/・`.git`）が cache に入るか、plugin 内 symlink の cache 内挙動。`bin/` の PATH が `claude -p` と Remote Control session でも効くか、monitors が RC で動くか。launchd からの安定した呼び出し経路（C3 の (a)(b)(c) は実機未検証）。
17. `allowed-tools: Bash(<path> *)` が `bash <path> args` 形に一致するか、`${CLAUDE_SKILL_DIR}` の導入 version と skill dir 自体が symlink のときの値、直置き（`~/.claude/skills/<name>/`）での置換の実測。`claude plugin tag` の導入 version と、root が marketplace 兼 plugin のときの挙動。`claude plugin eval` の実機結果（コスト、gating）。

調査が未了のもの:
18. hooks reference 末尾 62,610 字: Stop / UserPromptSubmit が queue・cross-session message 由来の turn で発火するか、`run_in_background` の shell が `background_tasks` に載るか、SessionEnd・async・http の詳細。`queue-operation` の enqueue / dequeue / remove の意味（未文書）。
19. Codex hooks ページ本文（event 一覧、入力項目、trust 手順）と、`codex exec` が `notify` を出すか。
20. agent-deck の send 実装本体と v1.12.0 以降の release 本文、他の tmux orchestrator の送信実装。
21. Herdr: plugins.mdx の "event hooks" と configuration.mdx の通知設定（外部 script へ `pane.agent_status_changed` を push する経路）、agent-skill.mdx と `herdr --skill` が spawn-session の内容と重なるか、`agent attach [--takeover]` と `events.wait` の意味、socket doc の error code 一覧に `agent_prompt_stalled` / `agent_not_ready` / `timeout` が無い理由、v0.9.1 の切れた本文と preview build 本文。
22. #85603 の残りのコメント（maintainer の応答）。
23. Claude Code CHANGELOG の 2.1.287 より古い範囲（`bin/` 導入 v2.1.91 の裏取り）と 2.1.288〜2.1.296 の個別走査、Week 38 以降の digest（index に無かった）。claude-plugins-official の tree 末尾 13.6K 字と第三者 plugin の bats 利用。
24. Projects が著者のアカウントに出ているか（段階 rollout）。
