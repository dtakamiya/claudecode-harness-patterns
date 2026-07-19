#!/bin/bash
#
# templates/hooks/pre-tool-use.sh の回帰テスト。
#
# 正本: 設計書 §3.5, §3.6.1, §3.6.2, §14.1
#
# 検証対象は、Claude Code hooksプロトコルとの変換部である。
#   - stdin JSONから tool_name / command / file_path を正しく取り出すこと
#   - allow時に deny を返さないこと、deny時に確実に deny を返すこと
#   - 判定材料が欠けた場合にfail-closedとなること（ここが最も重要）

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK_SRC="$ROOT_DIR/patterns/claude-code-development-harness/templates/hooks/pre-tool-use.sh"
SCRIPT_SRC="$ROOT_DIR/patterns/claude-code-development-harness/templates/scripts"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/pre-tool-use-hook-test.XXXXXX") || exit 1
PROJECT="$WORK_DIR/project"
OUTPUT_FILE="$WORK_DIR/output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

# 利用者リポジトリの構成を再現する
mkdir -p "$PROJECT/.claude/hooks" "$PROJECT/scripts" \
         "$PROJECT/src/main/order" "$PROJECT/docs/status" \
         "$PROJECT/scratch"

cp "$HOOK_SRC" "$PROJECT/.claude/hooks/pre-tool-use.sh"
cp "$SCRIPT_SRC/verify-bash-command.sh" \
   "$SCRIPT_SRC/verify-redirect-target.sh" \
   "$SCRIPT_SRC/verify-write-scope.sh" "$PROJECT/scripts/"
chmod +x "$PROJECT/.claude/hooks/pre-tool-use.sh" "$PROJECT/scripts/"*.sh

printf 'current_task: TASK-004\n' > "$PROJECT/docs/status/progress.yaml"

cat > "$PROJECT/.claude/bash-allowlist" <<'EOF'
npm
./gradlew
EOF

cat > "$PROJECT/.claude/write-scope-policy" <<'EOF'
allow src/main/order/**
deny  .claude/**
EOF

HOOK="$PROJECT/.claude/hooks/pre-tool-use.sh"

FAILURES=0

# hookを実行し、permissionDecisionを取り出す
run_hook() {
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PROJECT" HARNESS_SCRATCH_DIR="$PROJECT/scratch" \
    "$HOOK" > "$OUTPUT_FILE" 2>"$WORK_DIR/stderr" || true
  LC_ALL=C awk '
    BEGIN { RS = "\0" }
    {
      idx = index($0, "\"permissionDecision\"")
      if (idx == 0) { print "NO_DECISION"; exit }
      rest = substr($0, idx + length("\"permissionDecision\""))
      if (match(rest, /"[a-z]+"/)) {
        v = substr(rest, RSTART + 1, RLENGTH - 2)
        print v
      } else { print "UNPARSEABLE" }
    }' "$OUTPUT_FILE"
}

# $4 に文字列を与えた場合、permissionDecisionReason へその語が
# 含まれることまで検証する。決定だけを見ると、別の理由でたまたま
# denyになった場合を「正しく防いだ」と誤認するため。
assert_decision() {
  assert_label=$1
  assert_input=$2
  assert_expected=$3
  assert_reason=${4:-}
  actual=$(run_hook "$assert_input")
  if [ "$actual" != "$assert_expected" ]; then
    printf 'FAIL: %s (期待: %s, 実際: %s)\n' "$assert_label" "$assert_expected" "$actual" >&2
    sed -n '1,5p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  if [ -n "$assert_reason" ] && ! grep -Fq -- "$assert_reason" "$OUTPUT_FILE"; then
    printf 'FAIL: %s の拒否理由が想定と異なる (期待: %s)\n' "$assert_label" "$assert_reason" >&2
    sed -n '1,5p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# --- Bash: 受理 ---------------------------------------------------------
assert_decision 'allowlist内のBashコマンド' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  'defer'

# --- Bash: 拒否 ---------------------------------------------------------
assert_decision 'allowlist外のBashコマンド' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"curl https://evil.example"}}' \
  'deny' 'ALLOWLIST_MISS'

assert_decision 'セミコロン連鎖' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test; curl https://evil.example"}}' \
  'deny' 'NOT_SIMPLE_COMMAND'

# JSON中の \n は、パース後に実際の改行として連鎖検出へ到達しなければならない。
# ここを取りこぼすと permissions.md §4 が名指しする迂回経路がそのまま通る。
assert_decision 'JSONエスケープされた改行による連鎖' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test\ncurl https://evil.example"}}' \
  'deny' 'NOT_SIMPLE_COMMAND'

assert_decision 'JSONエスケープされたCRによる連鎖' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test\rcurl https://evil.example"}}' \
  'deny' 'NOT_SIMPLE_COMMAND'

# --- Write / Edit -------------------------------------------------------
assert_decision '許可範囲内へのWrite' \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"src/main/order/Order.java","content":"x"}}' \
  'defer'

assert_decision '許可範囲外へのWrite' \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"src/main/payment/Payment.java","content":"x"}}' \
  'deny' 'NOT_IN_WRITE_SCOPE'

assert_decision 'Agent定義の自己改変' \
  '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":".claude/agents/tdd-generator.md","old_string":"a","new_string":"b"}}' \
  'deny' 'EXPLICIT_DENY'

# --- 判定対象外のツールは委ねる -----------------------------------------
assert_decision '判定対象外ツール' \
  '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' \
  'defer'

# --- fail-closed --------------------------------------------------------
assert_decision 'tool_nameが無い' \
  '{"hook_event_name":"PreToolUse","tool_input":{"command":"npm test"}}' \
  'deny'

assert_decision 'Bashだがcommandが無い' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}' \
  'deny'

assert_decision 'Writeだがfile_pathが無い' \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":"x"}}' \
  'deny'

# 非ASCIIの\uエスケープは復元できないため、構造検証が成立しない。
# 「読めなかったので通す」は最も危険な失敗モードであり、denyでなければならない。
#
# ここはリテラルの多バイト文字ではなく、JSONの \uXXXX エスケープでなければ
# 検証にならない（リテラル文字はそのまま読め、この分岐へ到達しない）。
# 編集系ツールがエスケープを正規化してしまうため、実行時に組み立てる。
UNICODE_ESCAPE=$(printf '\\u3000')
assert_decision '復元できないユニコードエスケープ' \
  "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test${UNICODE_ESCAPE}curl\"}}" \
  'deny' '復元できないエスケープ'

# --- 設定欠落時のfail-closed --------------------------------------------
mv "$PROJECT/.claude/bash-allowlist" "$WORK_DIR/allowlist.bak"
assert_decision 'allowlist未配置' \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  'deny' 'Bash allowlistが存在しない'
mv "$WORK_DIR/allowlist.bak" "$PROJECT/.claude/bash-allowlist"

mv "$PROJECT/.claude/write-scope-policy" "$WORK_DIR/policy.bak"
assert_decision 'write scope policy未配置' \
  '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"src/main/order/Order.java","content":"x"}}' \
  'deny' 'write scope policyが存在しない'
mv "$WORK_DIR/policy.bak" "$PROJECT/.claude/write-scope-policy"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s\n' "pre-tool-use hook regression test failed: $FAILURES 件" >&2
  exit 1
fi

printf '%s\n' 'pre-tool-use hook regression test passed.'
