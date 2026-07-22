#!/bin/bash
#
# templates/hooks/subagent-stop.sh と stop-gate.sh の回帰テスト。
#
# 正本: 設計書 §3.5（Completion check / State commit）, §10, §14.2
#
# 両Hookとも「不足を検出して終了コード2で差し戻す」ことが責務である。
# 通してはいけない状態を通すと、自然言語の完了宣言がそのまま
# 完了根拠になってしまう（設計書 §14.2）。

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATES="$ROOT_DIR/patterns/claude-code-development-harness/templates/hooks"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/stop-hooks-test.XXXXXX") || exit 1
PROJECT="$WORK_DIR/project"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$PROJECT/.claude/hooks" "$PROJECT/docs/status/agent-runs/TASK-004"
cp "$TEMPLATES/subagent-stop.sh" "$TEMPLATES/stop-gate.sh" "$PROJECT/.claude/hooks/"
chmod +x "$PROJECT/.claude/hooks/"*.sh

SUBAGENT_HOOK="$PROJECT/.claude/hooks/subagent-stop.sh"
STOP_HOOK="$PROJECT/.claude/hooks/stop-gate.sh"
RUN_DIR="$PROJECT/docs/status/agent-runs/TASK-004"
PROGRESS="$PROJECT/docs/status/progress.yaml"

FAILURES=0

# $1: ラベル, $2: hookパス, $3: 期待exit(0 or 2)
assert_exit() {
  set +e
  printf '{}' | CLAUDE_PROJECT_DIR="$PROJECT" "$2" > "$WORK_DIR/out" 2>"$WORK_DIR/err"
  actual=$?
  set -e
  if [ "$actual" -ne "$3" ]; then
    printf 'FAIL: %s (期待exit=%s, 実際=%s)\n' "$1" "$3" "$actual" >&2
    sed -n '1,6p' "$WORK_DIR/err" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

write_progress() {
  cat > "$PROGRESS" <<EOF
schema_version: 1
revision: $1
expected_previous_revision: $2
current_task: TASK-004
blocking_issues: $3
next_action:
  agent: tdd-generator
EOF
}

write_valid_run() {
  cat > "$RUN_DIR/run-001.yaml" <<'EOF'
agent: tdd-generator
task: TASK-004
result: passed
blocking_findings: []
EOF
}

# === subagent-stop.sh ===================================================

# progress.yaml が無い段階（PHASE-0以前）は検査対象外
assert_exit 'progress.yaml未作成なら素通し' "$SUBAGENT_HOOK" 0

write_progress 42 41 '[]'

# agent-run欠如には2つの経路がある。fixtureがディレクトリを先に作ると
# 「ディレクトリ欠如」の分岐を一度も通らず、そこが壊れても気付けない。
# 両方を別々に検証する。
rm -rf "$RUN_DIR"
assert_exit 'agent-runディレクトリごと無い' "$SUBAGENT_HOOK" 2

mkdir -p "$RUN_DIR"
assert_exit 'ディレクトリはあるがyamlが無い' "$SUBAGENT_HOOK" 2

write_valid_run
assert_exit '正しいagent-runがある' "$SUBAGENT_HOOK" 0

# 必須fieldの欠落
printf 'agent: tdd-generator\ntask: TASK-004\n' > "$RUN_DIR/run-001.yaml"
assert_exit 'resultが無い' "$SUBAGENT_HOOK" 2

# taskの不一致（他taskの証跡を出して完了を主張する）
cat > "$RUN_DIR/run-001.yaml" <<'EOF'
agent: tdd-generator
task: TASK-999
result: passed
EOF
assert_exit 'agent-runのtaskがcurrent_taskと不一致' "$SUBAGENT_HOOK" 2

# 未解決blocking finding
cat > "$RUN_DIR/run-001.yaml" <<'EOF'
agent: tdd-generator
task: TASK-004
result: passed
blocking_findings:
  - REV-IMPL-001
EOF
assert_exit '未解決blocking findingが残る' "$SUBAGENT_HOOK" 2

write_valid_run

# === stop-gate.sh =======================================================

write_progress 42 41 '[]'
assert_exit '整合した状態' "$STOP_HOOK" 0

# revisionが前進していない（楽観ロックの破れ）
write_progress 41 41 '[]'
assert_exit 'revisionが前進していない' "$STOP_HOOK" 2

write_progress 40 41 '[]'
assert_exit 'revisionが後退している' "$STOP_HOOK" 2

# 未解決blocking issue
cat > "$PROGRESS" <<'EOF'
schema_version: 1
revision: 42
expected_previous_revision: 41
current_task: TASK-004
blocking_issues:
  - ISSUE-001
next_action:
  agent: tdd-generator
EOF
assert_exit '未解決blocking issue' "$STOP_HOOK" 2

# next_actionが無い = 次セッションが履歴なしで再開できない
cat > "$PROGRESS" <<'EOF'
schema_version: 1
revision: 42
expected_previous_revision: 41
current_task: TASK-004
blocking_issues: []
EOF
assert_exit 'next_actionが無い' "$STOP_HOOK" 2

if [ "$FAILURES" -ne 0 ]; then
  printf '%s\n' "stop hooks regression test failed: $FAILURES 件" >&2
  exit 1
fi

printf '%s\n' 'stop hooks regression test passed.'
