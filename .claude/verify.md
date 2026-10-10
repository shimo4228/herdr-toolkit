# verify.sh の選定記録

入口は `.claude/verify.sh`（`--staged` = staged の shell script の shellcheck だけ / 引数なし = 全体）。
選定は `~/.claude/.claude/verify.md`（2026-08-31 棚卸し）と同じツールを使う。

## format
tool: none
selected: 2026-10-10
reason: shell の formatter は harness でも採っていない。対象は shell script 数本だけ
re-research triggers: shell script が 10 本を超える / harness が formatter を採る

## lint
tool: shellcheck 0.11.0（`--norc -S style -e SC1091`）
selected: 2026-10-10
reason: 最も厳しい style 閾値。SC1091 は動的 source の偽陽性。対象は *.sh と skills/*/tests/bin/*
re-research triggers: 12 か月経過 / 新版が出る

## type check
tool: none（bash に型は無い）

## security
tool: none（secret scan は commit 時の harness hook `secret-scan-precommit.sh` と sync script の scan が持つ）

## dependency
tool: none（第三者 package を持たない。実行時に herdr / jq / claude を使う）

## test
tool: bats-core 1.13.0（skills/*/tests。偽の herdr / claude を tests/bin に置く）
selected: 2026-10-10
re-research triggers: 12 か月経過

## plugin manifest
tool: `claude plugin validate --strict`（plugin.json と marketplace.json。Claude Code 2.1.289 以上）
selected: 2026-10-10
re-research triggers: Claude Code の validate の仕様が変わる

## version
plugin.json の version と CHANGELOG.md 先頭の `## X.Y.Z` が一致すること（jq）

## 予算: shell script 1 本 400 行
measured 2026-10-10: 最大 agent-send.sh 284 行、spawn.sh 218 行。上げずに刈る — 変更はここに日付と理由を書く

## 発火の確認（2026-10-10）
shellcheck（未クォート変数）・bats（false の test）・version（CHANGELOG を 2.1.9 に）・loc（421 行）・
plugin / marketplace validate（未知の field）を注入し、すべて FAIL を確かめて probe を消した
