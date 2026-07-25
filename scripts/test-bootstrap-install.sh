#!/bin/bash
#
# bootstrapプロファイルの受入テスト。
#
# 正本: 実装計画 quizzical-munching-origami
#
# 検証対象は「install-harness.sh --target <新規プロジェクト> の直後に、
# harness-orchestration Skill を start で起動すると PHASE-0 が実際に
# 進むこと」である。個々のファイルの存在ではなく、鶏と卵が解けているか
# （Bash・Writeが実際にdeferされ、progress.yamlの確定経路が機能するか）を
# end-to-endで見る。
#
# 空のgitリポジトリへ導入し、以下をassertする:
#   - verify-harness-install.sh が exit 0（FAIL 0件）
#   - pre-tool-use.sh に Bash ./scripts/harness-state-write.sh progress を
#     流すと defer
#   - pre-tool-use.sh に Write docs/features/f/handoffs/a.md を流すと defer、
#     docs/status/progress.yaml を流すと deny
#   - stop-gate.sh が exit 0（種のprogress.yamlでデッドロックしない）
#   - subagent-stop.sh が汎用サブエージェントをブロックしない

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATES="$ROOT_DIR/patterns/claude-code-development-harness/templates"
INSTALLER="$TEMPLATES/scripts/install-harness.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/bootstrap-install-test.XXXXXX") || exit 1
OUTPUT_FILE="$WORK_DIR/output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

# ---------------------------------------------------------------------------
# 導入
# ---------------------------------------------------------------------------

DIR="$WORK_DIR/target"
mkdir -p "$DIR"
git -C "$DIR" init -q
git -C "$DIR" -c user.email=test@example.com -c user.name=test \
  commit -q --allow-empty -m init

if ! "$INSTALLER" --target "$DIR" > "$OUTPUT_FILE" 2>&1; then
  fail 'install-harness.sh --target が失敗した'
  sed -n '1,60p' "$OUTPUT_FILE" >&2
fi

HOOK="$DIR/.claude/hooks/pre-tool-use.sh"
STOP_GATE="$DIR/.claude/hooks/stop-gate.sh"
SUBAGENT_STOP="$DIR/.claude/hooks/subagent-stop.sh"
SCRATCH="$WORK_DIR/scratch"
mkdir -p "$SCRATCH"

permission_decision() {
  # $1: event JSON
  out=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$DIR" HARNESS_SCRATCH_DIR="$SCRATCH" "$HOOK" 2>"$WORK_DIR/hook-err") || true
  printf '%s' "$out" | LC_ALL=C awk '
    BEGIN { RS = "\0" }
    {
      idx = index($0, "\"permissionDecision\"")
      if (idx == 0) { print "NO_DECISION"; exit }
      rest = substr($0, idx + length("\"permissionDecision\""))
      if (match(rest, /"[a-z]+"/)) {
        print substr(rest, RSTART + 1, RLENGTH - 2)
      } else { print "UNPARSEABLE" }
    }'
}

# ---------------------------------------------------------------------------
# 1. verify-harness-install.sh が exit 0（FAIL 0件）
# ---------------------------------------------------------------------------

if ! "$DIR/scripts/verify-harness-install.sh" --target "$DIR" > "$WORK_DIR/verify-out" 2>&1; then
  fail 'verify-harness-install.sh がFAILを報告した'
  sed -n '1,60p' "$WORK_DIR/verify-out" >&2
fi

# ---------------------------------------------------------------------------
# 2. Bash: ./scripts/harness-state-write.sh progress が defer
# ---------------------------------------------------------------------------

DECISION=$(permission_decision '{"tool_name":"Bash","tool_input":{"command":"./scripts/harness-state-write.sh progress"}}')
[ "$DECISION" = 'defer' ] || fail "Bash harness-state-write.sh progress がdeferでない（応答: $DECISION）"

# ---------------------------------------------------------------------------
# 3. Write: docs/features/f/handoffs/a.md が defer
# ---------------------------------------------------------------------------

DECISION=$(permission_decision "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$DIR/docs/features/f/handoffs/a.md\"}}")
[ "$DECISION" = 'defer' ] || fail "Write docs/features/f/handoffs/a.md がdeferでない（応答: $DECISION）"

# ---------------------------------------------------------------------------
# 4. Write: docs/status/progress.yaml が deny
# ---------------------------------------------------------------------------

DECISION=$(permission_decision "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$DIR/docs/status/progress.yaml\"}}")
[ "$DECISION" = 'deny' ] || fail "Write docs/status/progress.yaml がdenyでない（応答: $DECISION）。single writer原則が破られている"

# ---------------------------------------------------------------------------
# 5. stop-gate.sh が exit 0（種のprogress.yamlでデッドロックしない）
# ---------------------------------------------------------------------------

if ! CLAUDE_PROJECT_DIR="$DIR" "$STOP_GATE" 2>"$WORK_DIR/stop-gate-err"; then
  fail "stop-gate.sh が種のprogress.yamlでexit 0にならない: $(cat "$WORK_DIR/stop-gate-err")"
fi

# ---------------------------------------------------------------------------
# 6. subagent-stop.sh が汎用サブエージェントをブロックしない
#    （expected-agent-run markerが無い場合）
# ---------------------------------------------------------------------------

rm -f "$DIR/docs/status/.staging/expected-agent-run"
if ! printf '{}' | CLAUDE_PROJECT_DIR="$DIR" "$SUBAGENT_STOP" 2>"$WORK_DIR/subagent-stop-err"; then
  fail "subagent-stop.sh がmarker無しの汎用サブエージェントをブロックした: $(cat "$WORK_DIR/subagent-stop-err")"
fi

if [ "$FAILURES" -ne 0 ]; then
  printf '\n%d件失敗\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok\n'
