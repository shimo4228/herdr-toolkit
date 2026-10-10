kind: internal
# 著者の Herdr 運用（2026-07-05〜10-09）で、仕様の誤用・不足によるボトルネックはどこにあり、何回起きているか

## 再現

手順: lead が `~/.claude/projects/**/*.jsonl`（4.3 GB。herdr 呼び出しを含む 172 本、212 session）を read-only の python で走査した（方法は「確認」）。対象は 2026-07-05〜10-09 の herdr 関連 Bash 呼び出し 1,704 回。サブコマンド別の件数は「言及を含む」ため、応答を持つ呼び出しの数とは一致しない。以下の件数は lead の集計。「計算」と書いたものだけ、本 report が lead の数字から割った値。

観測した結果（件数の多い順）:

| ID | 現象 | 回数 | 月別 07/08/09/10 |
|---|---|---|---|
| A | `agent prompt --wait --timeout N` が `timeout`（"timed out waiting for agent status"）を返す | 123 | 8 / 51 / 54 / 10 |
| B | 完了待ちの polling。sleep 付き foreground の herdr 呼び出し 176（静的 sleep 計 1,543 秒以上。ループは 1 回と数えた）、while/until ループ 42、run_in_background 42、Bash tool の 2 分 timeout 8。1 session で herdr 呼び出し最大 66（read 40・prompt 18・send-keys 11 など。大半が画面確認） | 上記の各件数 | — |
| C | `agent_prompt_stalled` | 26 | 6 / 14 / 5 / 1 |
| D | 入力欄に残った prompt の Enter 押し直し（`send-keys <agent> enter`） | 23 | 10 / 11 / 1 / 1 |
| E | `agent_not_found`（get / read / prompt / send-keys / wait / send）。渡された名前は表示名か汎用名（reviewer・writer） | 14 | 月別なし |
| F | 起動の失敗。spawn.sh の警告 6（起動成功 206 に対し。コード無し 5・`agent_not_ready` 1）、`agent:start` の `timeout` 4、`agent:start` の `agent_not_ready`（blocked during startup）2。警告と JSON 応答の重なりは未確認 | 上記の各件数 | — |
| G | herdr の出力の parse 失敗。python json の traceback 15、jq エラー 3 | 18 | — |
| H | 少数のエラー: `workspace_not_found`（workspace:close）6（すべて 08 月）、`pane_not_found` 5、`agent_launch_pending` 1、`invalid_agent_argument` 1、`agent_not_idle`（alternate-screen）1 | 14 | — |
| I | Codex の起動引数 `--ignore-user-config --ignore-rules` を対話モードの codex が `unexpected argument` で拒否 | 2 | 2026-08-26、09-20 |
| J | protocol 不整合。0.8.0 の brew upgrade 直後に CLI だけ protocol 17→19 になり `compatible: no`、pane / agent CLI が全滅（TUI は無傷）。著者の memory（2026-09-12 更新）による | 1 | 0.8.0（初出 08-15）の直後 |

補足の観測（lead の集計）:

- A の 123 件はすべて `--wait` + `--timeout` で `--until` なし。timeout 値（115 件分）: 60000×37、180000×30、20000×15、120000×13、30000×8、25000×5、45000×4、15000×2、90000×1。timeout の直後（同 session の次の 3 呼び出し以内）の agent 状態: working 43 / idle・done 16 / 判定不能 56（計 115）。
- 成功形の空レスポンス `{"result":{}}`: 記録された prompt 応答に 0 件（成功応答 47 件はすべて agent object を含む）。
- 対照: launchd の tick（`~/.claude/scripts/triage-tick.sh`）は `--wait --until working --timeout 60000` + 1 回再送。`~/.claude/logs/triage-tick.log`（2026-08-19〜10-07、105 行）で、1 発で着弾 27、再送で着弾 1、2 回失敗 0、新規 spawn 12。
- 著者自身の発話で Herdr の不具合を訴えたものは 6 件で、いずれも不満ではない。lead の読み: 摩擦は agent session 側の確認作業として払われていた。
- 版の初出: 0.7.4（07-17）、0.7.5（07-22）、0.8.0（08-15）、0.8.2（08-19）、0.9.0（09-12）、0.9.1（09-20）、0.9.3（10-04）。2026-10-10 の `herdr status`: client 0.9.3 / server 0.9.1、`endpoint_compatible: yes`、`restart_needed: no`、`server_binary_stale: yes`。

計算: 月ごとの herdr 呼び出し数に対する比。分母は herdr 関連 Bash 呼び出し全体で、prompt 呼び出しではない。10 月は母数が 97 で、1 件が約 1 ポイントに当たる。

| 月 | herdr 呼び出し | A timeout | C stalled | D Enter 押し直し |
|---|---|---|---|---|
| 07 | 402 | 8（2.0%） | 6（1.5%） | 10（2.5%） |
| 08 | 715 | 51（7.1%） | 14（2.0%） | 11（1.5%） |
| 09 | 490 | 54（11.0%） | 5（1.0%） | 1（0.2%） |
| 10 | 97 | 10（10.3%） | 1（1.0%） | 1（1.0%） |
| 計 | 1,704 | 123（7.2%） | 26（1.5%） | 23（1.3%） |

C と D の件数は 09 月以降に減り、A は 09〜10 月も 10% 台にとどまる。

## 原因

path は `~/.claude/skills/` 基準で書く（`spawn-session/` は公開 copy の `skills/spawn-session/` と該当行が同じ）。`triage-tick.sh` は `~/.claude/scripts/`、`agents.md` は `~/.claude/rules/common/`。`herdr/SKILL.md` は Herdr 同梱の skill（origin herdrdev/herdr。この copy の版は未記載）。種別は 3 つ: 誤用 = こちらの手順が仕様の意味と合わない / 不足 = 手順か実装に穴がある / 外部 = Herdr か Claude Code の挙動で、こちらの行に原因が無い。

| ID | 種別 | 原因の行 |
|---|---|---|
| A | 誤用 + 不足 | `spawn-session/SKILL.md:59-67`（65）、`task-triage/SKILL.md:210-213`、`agents.md:10-12` |
| B | 不足 | `spawn-session/SKILL.md:95-108`、`herdr/SKILL.md:148` |
| C | 外部（検出は正常）+ 復旧手順の欠落 | 原因の行なし。欠落は `spawn-session/SKILL.md:75` |
| D | 外部 | 原因の行なし。手順は `spawn-session/SKILL.md:76-81` |
| E | 不足（名前が 2 つ） | `spawn.sh:144-146` |
| F | 不足（既知の制約） | `spawn.sh:152-156, 165-172`、`spawn-session/SKILL.md:145` |
| G, H | 不明 | — |
| I | 誤用（解消済み） | `CHANGELOG.md:9-13` |
| J | 不足（検知なし） | `spawn.sh:64` |

### A. 着弾の確認に、turn の完了待ち（settled の待ち）を使っている

1. 手順書が指す primitive。`spawn-session/SKILL.md:59` の見出しは「着弾を確認する」で、65 行が `herdr agent prompt "<agent 名>" "$(cat task.txt)" --wait --timeout 180000` を示す。`task-triage/SKILL.md:210-213` は `/effort` と packet の送信に `--wait --timeout 60000` を使い、「the first prompt often returns `timeout` while landing fine」（210-211）と書く。常駐 rule `agents.md:10-12` は「`--wait` の settled は着弾確認までに使い、完了の信号にしない」。3 か所とも、着弾の確認に `--wait` の settled を使う前提で書かれている。着弾専用の `--until working` は `triage-tick.sh:153` にしか無い（Grep: `~/.claude/{skills,scripts,rules,agents,hooks}` の md / sh / py で、`--until` は `herdr/SKILL.md` と `triage-tick.sh` だけ）。
2. `--wait` の意味（一次資料）。`herdr/SKILL.md:146-148`: non-working の状態から送った prompt は、送信後 5 秒のあいだ working / blocked の activity を待ち、観測できなければ `agent_prompt_stalled`。その後は idle / done / blocked の settled を待ち、caller の timeout が先に切れれば `timeout`。caller の timeout は submission 時間を含む。「この wait は lifecycle state を追い、個別の turn は追わない。すでに working なら active turn の完了で満たされうる」。lead が引いた 0.9.3 の `agent prompt --help` も同じ趣旨。
3. 帰結。non-working から送った `--wait` の成功は、activity の観測と settled を意味するので着弾の証拠になる。`timeout` は着弾の有無を決めない。(i) 着弾し、turn が caller の timeout より長い。(ii) working 中に送って落ちた — `spawn-session/SKILL.md:86-88`（2026-09-23、3 回）は `timed out waiting for agent status` が返り、画面に本文が無かったと記す。working 中の送信には 5 秒 gate が掛からない（`herdr/SKILL.md:148` の "from a non-working state"）ので、(ii) も同じ `timeout` を返し、working 中に送った `--wait` の成功は着弾の証拠にもならない。呼び出し側は `agent get` と `agent read --source visible` に進む（`spawn-session/SKILL.md:66, 72`）。
4. 数との整合（傍証。因果の証明ではない）。timeout 値 60000（37）と 180000（30）の計 67 件（115 件の 58%、計算）は、`task-triage/SKILL.md:210-213` と `spawn-session/SKILL.md:65` の値に一致する。時期は、task-triage の元になった初回 cycle（`task-triage/references/first-cycle-2026-08-17.md`、2026-08-17）以降に A が 8 → 51 へ増えたことと重なる。直後の状態が分かった 59 件のうち 43 件（73%、計算）は working で、(i) と整合する。16 件（idle・done）と判定不能 56 件は (i)(ii) を分けられない。
5. 対照。`triage-tick.sh:153` は `--until working`（60 s）で、28 回の prompt のうち 2 回失敗は 0。ただし tick は status が working なら送らずに見送り（141-144）、送る前に `agent wait`（152、30 s）し、失敗なら 3 秒置いて 1 回再送する（154-160）。`--until working` 単独の効果とは分けられない。再送が要った 1 回（2026-10-04）は、spawn 直後でなく既存 session（status done）への prompt で、失敗の log は「found」の 5 秒後。`herdr/SKILL.md:148` の 5 秒 gate と整合するが、submit が出力を `/dev/null` に捨てる（153）ため error code は残らない。
6. 混在。A の 123 件には、(1) 着弾の確認に完了待ちを使う手順と、(2) 完了待ちの目的で短い N を置く運用が混ざる。内訳は集計に無い。`mono-figure/SKILL.md:82`（`--wait --timeout 600000`）は (2) で、用途と合う: 画像生成 1 回の完了待ちで、83 行が出力ファイルの存在を確かめてから開く。600000 は 115 件の値の分布に現れない。

### B. 完了を知らせる primitive が agent session に無く、状態を見に行く

- `--wait` は lifecycle の待ちで、turn の完了ではない（`herdr/SKILL.md:148`）。`done` は REPL が idle という意味で、仕事の完了ではない（`task-triage/SKILL.md:213-214`、`task-triage/references/first-cycle-2026-08-17.md:60-62`）。`done` は build が自分の background shell を待つあいだにも返る（`spawn-session/SKILL.md:95-97`）。settled が早く返る側の誤差も rule に記録がある: Codex が working 中に `idle` を返すフラッピング（`agents.md:11-12`。件数は集計に無い）。本 repo の 1.0.0 も「agent_status is not trusted」と記す（`CHANGELOG.md:19-23`）。
- そのため手順書自体が 30 秒 sleep の polling loop を載せる（`spawn-session/SKILL.md:99-108`。2026-09-23 に 6 回張って真の停止でだけ発火）。
- `--wait` は blocking で、呼び出し側（Bash tool）には 2 分の上限がある（lead の集計: 2 分 timeout 8 回）。`spawn-session/SKILL.md:65` の 180000 ms（3 分）と `mono-figure/SKILL.md:82` の 600000 ms（10 分）はその上限より長い。両ファイルとも、Bash 側の timeout を延ばす・background で走らせる指示は無い（Grep: `run_in_background` / `background` / `Bash.*timeout` / `2 分` / `120000` は `spawn-session/SKILL.md:96` の別件だけ）。8 回がこれらの待ちだったかは集計に無い。

### C・D. 送信経路の取りこぼし（原因の行はこの repo に無い）

- 症状の記述: `spawn-session/SKILL.md:59-62`（起動直後の最初の prompt が落ちる。2026-07-25 の実測で 3 回中 1 回失敗。`agent get` が idle・`interactive_ready: true` でも起きる）、83-84（長さは無関係。変数はタイミングだけ）、76-78（`[Pasted text #1 +N lines]` が入力欄に残り Enter が入らない）、86-93（working 中の送信は落ちる）。
- 送信側の仕様: `herdr/SKILL.md:146` — `agent prompt` は pane の bracketed-paste mode を尊重し、text と Enter を 1 つの ordered submission として書く。paste boundary を Enter の前に入れると書かれているのは Codex on Windows だけで、Claude Code に同種の処置があるかの記述は無い。
- 復旧の記述: stalled は `spawn-session/SKILL.md:75` が「エラーなので気づける」と述べるだけで、再送の手順が無い。Enter の押し直しは 80-81（人間の書きかけなら押さない）。tick は 1 回再送で吸収する（`triage-tick.sh:154-160`）。
- 推移: 上の月別の表。C は 14 → 5 → 1、D は 11 → 1 → 1。herdr 呼び出し総数は 08 → 09 で 715 → 490（−31%、計算）に対し、D は −91%、C は −64%（計算）。時期は 0.9.0（09-12）と重なり、`spawn-session/SKILL.md:86-93` の追記（2026-09-23）とも重なる。版別・手順別の層別はしていない。

### E. 1 つの session に名前が 2 つある

- 表示名（tab の label・Remote Control の一覧名。`<label>/<purpose>` 形式 — `spawn-session/SKILL.md:39-40`）と、`herdr agent *` が受ける agent 名（`[a-z][a-z0-9_-]{0,31}` + live 中一意 — `spawn.sh:143`、`SKILL.md:55`）が別物。`spawn.sh:144-146` が slug + PID で別名を作る。
- 緩和は既にある: `spawn.sh:163` が `agent:` 行に名前を出し、`SKILL.md:52-57` が「表示名をそのまま渡すと `agent_not_found`」と書いて、取り損ねたら `agent list` の `name` から引くよう指示する。それでも 14 件。どの経路で取り違えたかは集計に無い。
- 対照: `triage-tick.sh:95-103, 138-139` は名前を覚えず、`agent list` を cwd と名前の prefix で引き、名前が無ければ pane id を target にする。

### F. 起動時の blocked を spawn.sh が扱わない

- `spawn.sh:152-153` は `agent start ... --timeout 30000`（`herdr/SKILL.md:138` の既定と同じ）。154 が再試行するのは `agent_pane_busy` だけで、他は 165-172 の失敗経路（pane の直近 40 行を出して exit 1）。workspace trust のダイアログは扱わない（`spawn-session/SKILL.md:145`。2026-08-01 確認。`~/.claude.json` を書き換えて回避しない判断も同じ行）。
- 型の確認: launchd log に 2026-09-08 の spawn 失敗が 1 件あり、herdr の応答は `agent_not_ready`（"blocked during startup and is not ready for prompts"）、pane の画面は Claude Code の workspace trust 確認（"Is this a project you created or one you trust?"）だった。別 repo の初回 spawn。lead の「起動時 blocked 2 件」と同じ型だが、transcript の 2 件と同一かは未確認。tick は、この種の session（`<agent>-<pid>` 名のまま残ったもの）を次回に引き継ぐ（`triage-tick.sh:90-103`）。
- `herdr/SKILL.md:138` は、blocked の `agent_not_ready` でも名前は `agent read` / `agent send-keys` 用に残ると書く。`spawn.sh:165-172` の失敗経路は AGENT_NAME を出力しない。
- 関連（件数なし）: claude へ転送する引数は `--remote-control` と `--model` だけ。定義は `spawn.sh:58-59`、他の `--*` は 51 で exit 64、使用箇所は 152-153。`--permission-mode` を通す口は無い（`spawn-session/SKILL.md:113-116`）。手順書の迂回は、初回 prompt で EnterPlanMode させる方法（118-121。2026-07-26 に 1 回成功）。

### G・H. 原因を特定できない

G（parse 失敗 18）と H（少数のエラー 14）は、集計に原因を示す手がかりが無い。H のうち `workspace_not_found` 6 件が 08 月に集中する点だけが目立つ。

### I. exec 専用の flag を対話モードに渡した

`CHANGELOG.md:9-13`（2.0.0、2026-10-07）: herdr-delegate の Codex 起動 flag `--ignore-user-config --ignore-rules` は interactive codex 0.154 に拒否される（`codex exec` だけが受理する）。拒否は 2026-08-26 と 09-20（lead の集計）。skill ごと退役し、この flag は `~/.claude/skills` に残っていない。本 repo では `CHANGELOG.md:9-10` の記述だけ（Grep）。

### J. server の生存確認が互換性を見ない

- `spawn.sh:64` の生存確認は `workspace list` の成否だけ。失敗なら `nohup herdr server &`（65）→ 0.5 秒 × 10 回待つ（68-71）→ 駄目なら exit 1（72）。`herdr status` の `endpoint_compatible` / `server_binary_stale` は見ない。version の確認はファイル内に無く、"herdr 0.7.5+"（140）はコメントだけ。
- 発生: 著者の memory に 1 件（0.8.0 の upgrade 直後）。0.8.2 以降は `herdr server live-handoff` で pane を殺さずに更新できる。transcript 側の件数は集計に無い。
- 現在（2026-10-10）は互換（`endpoint_compatible: yes`）で症状は出ていないが、server は client より古い（0.9.1 / 0.9.3、`server_binary_stale: yes`）。spawn.sh はこの stale を見ない。

## 確認

1. 集計（lead）。`~/.claude/projects/**/*.jsonl` を read-only の python で走査し、tool_use と tool_result を id で突き合わせ、tool_use id で重複を除いた。herdr の JSON エラー応答は `{"error":{"code":"<code>","message":"<text>"},"id":"cli:<group>:<cmd>"}` の形（launchd log の 1 件で形を確認した）を正規表現で抽出し、(cli id, code) で数えた。timeout 直後の agent 状態は、同 session の次の 3 呼び出し以内の応答から分類した。この調査では jsonl を走査せず、件数を再計算していない。
2. Read で確かめた行（実際の行番号。lead の候補とのずれは次項）:
   - `~/.claude/skills/spawn-session/SKILL.md`: 39-40, 52-57, 59-67, 72, 74-81, 83-84, 86-93, 95-109, 113-121, 145
   - `~/.claude/skills/spawn-session/spawn.sh`: 51, 58-59, 64-73, 140-146, 152-156, 163, 165-172
   - `~/.claude/skills/task-triage/SKILL.md`: 210-214。`references/first-cycle-2026-08-17.md`: 2, 60-62
   - `~/.claude/skills/mono-figure/SKILL.md`: 82-83
   - `~/.claude/scripts/triage-tick.sh`: 90-103, 138-167
   - `~/.claude/skills/herdr/SKILL.md`: 138, 146-156
   - `~/.claude/rules/common/agents.md`: 10-12
   - 本 repo の `CHANGELOG.md`: 9-13, 19-23
3. lead の候補とのずれ:
   - 「spawn-session/SKILL.md の 59〜64 行付近: 表示名と agent 名の違い」→ 実際は 52-57（step 4）。59-62 は「最初の prompt が落ちることがある」。
   - 「spawn.sh の 152 行付近: 転送する引数」→ 転送は 152-153。引数の定義は 58-59、未知 option の拒否は 51。
   - 一致: `spawn-session/SKILL.md:65, 72, 145`、`task-triage/SKILL.md:210-213`、`mono-figure/SKILL.md:82`、`triage-tick.sh:153`、`spawn.sh:64, 144-146`。
4. 公開 copy。本 repo の `skills/spawn-session/` と `~/.claude` 側で、`SKILL.md` の 53, 56, 65, 75, 76, 87, 145 行と `spawn.sh` の 51, 58, 64, 70, 144, 146, 148, 152, 154 行が同じ（Grep で照合。全文の diff は取っていない）。
5. launchd log の再計数（Grep）。"prompt accepted (" 27、"prompt accepted on retry" 1、"prompt attempt 1 failed" 1、"prompt failed twice" 0、"no live triage session for" 13、" spawned " 12、"spawn failed" 1、全 105 行。lead の 27 / 1 / 0 / spawn 12 と一致する。12 は成功した spawn の数で、試行は 13（失敗 1）。
6. 集計の内部整合。月別の合計は一致（A 8+51+54+10=123、C 26、D 23、呼び出し 1,704）。timeout 値の内訳と直後の状態の分類は、どちらも合計 115 で、123 に 8 足りない。
7. 手順書に無いことの確認（Grep）。`--until` は `herdr/SKILL.md` と `triage-tick.sh` だけにある。Bash 側 timeout の指示は `spawn-session/SKILL.md` と `mono-figure/SKILL.md` に無い。
8. `--wait` の意味は `herdr/SKILL.md` の本文と、lead が引いた 0.9.3 の `agent prompt --help` に依る。この調査では `herdr` を実行していない。

## Still unknown

1. timeout 直後の判定不能 56 件の実際の着弾。「判定不能」の定義は集計に書かれていない。決め手は、各 timeout の後に `agent read` が送った本文の一意な語を含むか（`spawn-session/SKILL.md:86-88` と同じ判定）、または次の turn の出力が transcript にあるか。あわせて、分類の合計が 115 で 123 に 8 足りない理由も未確認。working 43 件も、着弾した turn の実行中か、working 中に送って落ちた後も別の turn が続いているのかを分けていない。
2. `send-keys enter` 23 件のうち、0.8 以降の版で起きたもの（09〜10 月の 2 件）の原因。決め手は、その 2 件の直前の prompt の送信形（`--wait` の有無、対象 agent の status、本文の行数）と応答形。08 月の 11 件は 0.8.0（初出 08-15）の前後を日付で分けないと、「0.8 以降」の母数が定まらない。
3. protocol 不整合の状態で `spawn.sh:64` の `workspace list` が失敗し、`herdr server` を起動する（65）と何が起きるか（未検証）。可能な結果の列挙であって観測ではない: 既存 server があるため起動が拒否され、10 回待って `spawn.sh:72` で exit 1 / 既存 server の socket を奪う / 何も起きない。live の server では試さず、Herdr の docs か隔離した環境で確かめる。
4. working 中に送った prompt が落ちるのは、Herdr の paste 経路か、Claude Code の入力処理か。分かっていること: Herdr は text と Enter を 1 つの ordered submission で書く（`herdr/SKILL.md:146`）。5 秒 gate は non-working からの送信にだけ掛かる（148）。3 回とも `timeout` が返り、画面に本文が無かった（`spawn-session/SKILL.md:86-88`）。`send-keys escape` は ok を返すが working を解かない（89）。分かっていないこと: Claude Code が working 中の入力を受け付けるか・queue するか、queue されるなら画面のどこに出るか、Herdr が working 中は Enter を書かないのか。決め手は、同じ送信を素の端末で bracketed paste + Enter として再現するか、Herdr 側の送信 log。起動直後の最初の prompt が落ちる型（C）と `[Pasted text]` に Enter が入らない型（D）も、同じ分岐が未決。
5. `{"result":{}}` の成功形の空レスポンス。`spawn-session/SKILL.md:76-78` は起きると書くが、集計では記録された prompt 応答に 0 件。成功応答 47 件は prompt 言及 279 の一部なので、記録に残らなかっただけかもしれない。仮説（未検証）は 2 つ: `--wait` なしの prompt の応答形（`herdr/SKILL.md:146` は「written だけでは turn の開始を証明しない」と書く）/ working 中に送って 5 秒 gate が掛からなかった場合。76-78 の実測が `--wait` 付きだったかは記述が無い。
6. A の 123 件の呼び出し元別（手順書に書かれたコマンドか、session 独自の組み立てか）。値の一致（60000 と 180000 で 67/115）は傍証にとどまる。
7. spawn 直後の最初の prompt の失敗率。`spawn-session/SKILL.md:60` は 3 回中 1 回（2026-07-25）。transcript の起動成功 206 に対する値は未集計。
8. G の parse 失敗 18 件が読もうとした出力の種類。E の 14 件が `spawn.sh` 由来の名前を取り違えたものか、別の起動経路か。Bash tool の 2 分 timeout 8 件が `--wait` や sleep のどれか。
9. polling の費用（token・時間）。1,543 秒は静的 sleep の下限で、動的な sleep とループの中身を含まない。
10. 版別の層別。07〜10 月に 7 版あり、C・D の減少と A の持続が版によるのか、手順書の更新によるのか、利用量によるのかは分けていない。`server_binary_stale: yes`（server 0.9.1・client 0.9.3）の意味と影響も未確認。
11. `--until working` が、model の turn を起こさない local の slash command（`/effort` など）で着弾の判定になるか。working に入らなければ判定できない可能性がある（未検証）。tick が使うのは model の turn を起こす cycle prompt だけ。
