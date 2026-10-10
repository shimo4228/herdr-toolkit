#!/usr/bin/env bash
# verify.sh — herdr-toolkit の機械ゲート（pre-commit hook と手元の完全検査の単一入口）。
#   引数なし  = repo 全体の完全検査（shellcheck・bats・plugin validate・版の一致・LOC 予算）
#   --staged  = commit 境界の高速検査（staged の shell script だけ shellcheck）
# exit: 0 PASS / 1 FAIL / 2 検査できない（ツール不在。眠っているゲートは stdout に名指しする）
# ツールの選定理由と再調査の条件は .claude/verify.md。
set -uo pipefail

if [[ -n "${VERIFY_REPO_ROOT:-}" ]]; then
  ROOT="$VERIFY_REPO_ROOT"
else
  ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 2
fi
cd "$ROOT" || exit 2

STAGED=0
[[ "${1:-}" == "--staged" ]] && STAGED=1

fail=0 asleep=0
check() {   # check <label> <command...>
  local label=$1 out; shift
  if ! out=$("$@" 2>&1); then
    printf '[%s] FAIL\n%s\n' "$label" "$out"
    fail=1
  fi
}
sleeping() { printf '[verify] %s 不在 — %s をスキップ\n' "$1" "$2"; asleep=1; }

# shell script の一覧: *.sh と、拡張子の無い実行ファイル（skills/*/tests/bin/*）
shell_files() {
  if ((STAGED)); then
    git diff --cached --name-only --diff-filter=ACMR
  else
    git ls-files
  fi | while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.sh | skills/*/tests/bin/*) printf '%s\n' "$f" ;;
    esac
  done
}

# --- shellcheck（最も厳しい style 閾値。SC1091 は動的 source の偽陽性）---------
files=()
while IFS= read -r f; do files+=("$f"); done < <(shell_files)
if ((${#files[@]})); then
  if command -v shellcheck >/dev/null 2>&1; then
    check shellcheck shellcheck --norc -S style -e SC1091 "${files[@]}"
  else
    sleeping shellcheck "shell lint"
  fi
fi

if ((!STAGED)); then
  # --- bats（skills/*/tests。偽の herdr / claude で分岐を固定する）--------------
  if command -v bats >/dev/null 2>&1; then
    dirs=()
    for d in skills/*/tests; do [[ -d "$d" ]] && dirs+=("$d"); done
    ((${#dirs[@]})) && check bats bats "${dirs[@]}"
  else
    sleeping bats "skill のテスト"
  fi

  # --- plugin と marketplace の manifest（Claude Code 2.1.289 以上で両方検査）-----
  if command -v claude >/dev/null 2>&1; then
    check plugin-validate claude plugin validate .claude-plugin/plugin.json --strict
    check marketplace-validate claude plugin validate . --strict
  else
    sleeping claude "plugin validate"
  fi

  # --- plugin.json の version と CHANGELOG 先頭の版の一致 ------------------------
  if command -v jq >/dev/null 2>&1; then
    v=$(jq -r '.version' .claude-plugin/plugin.json)
    c=$(sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' CHANGELOG.md | head -1)
    [[ "$v" == "$c" ]] || { printf '[version] FAIL: plugin.json %s / CHANGELOG 先頭 %s\n' "$v" "$c"; fail=1; }
  else
    sleeping jq "版の一致"
  fi

  # --- LOC 予算: shell script 1 本 400 行（上げずに刈る — 変更は verify.md に日付と理由）---
  MAX_SH_LOC=400
  for f in "${files[@]}"; do
    n=$(wc -l < "$f")
    ((n > MAX_SH_LOC)) && { printf '[loc] FAIL: %s は %d 行（上限 %d）\n' "$f" "$n" "$MAX_SH_LOC"; fail=1; }
  done
fi

((fail)) && exit 1
((asleep)) && exit 2
exit 0
