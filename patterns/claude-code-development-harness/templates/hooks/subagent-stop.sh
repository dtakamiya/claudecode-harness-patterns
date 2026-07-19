#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書 Version 1.10
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# 正本: 設計書 §3.5（Completion check）, §10.1（Agent-run成果物）, §14
#
# --- 責務 ---
#
# 設計書 §3.5 Completion check行:
#   「必須成果物、レビュー対象SHA、テスト証跡、agent-run結果の存在確認」
#
# 設計書 §14.2は「RunnerはAgentの自然言語による完了宣言を信用せず、
# 終了コード、成果物、Git diff、レビュー対象SHA、agent-run、
# 未解決blocking findingを検査する」と定める。本Hookはその
# Fullモード版の入口である。
#
# --- 限界（重要）---
#
# 本Hookが確認できるのは**存在と形式**であって、内容の妥当性ではない。
# agent-runに記載されたテスト結果が真実かどうかは判定していない。
# 設計書 §14.2の完全な検査はExternal Runnerの
# quality-gate.sh / verify-agent-result.sh が担う。
# 本Hookを通ったことを「工程が完了した」根拠にしない。
#
# 終了コード2でAgentの終了をブロックし、不足を差し戻す。

set -eu

HOOK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(CDPATH='' cd -- "$HOOK_DIR/../.." && pwd)}

PROGRESS_FILE="$PROJECT_DIR/docs/status/progress.yaml"
AGENT_RUNS_DIR="$PROJECT_DIR/docs/status/agent-runs"

# progress.yamlが無い段階（PHASE-0の初期化前）は検査対象外とする。
[ -f "$PROGRESS_FILE" ] || exit 0

CURRENT_TASK=$(
  LC_ALL=C awk '
    /^current_task:[ \t]*/ {
      sub(/^current_task:[ \t]*/, "")
      gsub(/[ \t\r]+$/, "")
      print
      exit
    }' "$PROGRESS_FILE"
)

# current_taskが未確定なら、どのagent-runを期待すべきか決まらない。
[ -n "$CURRENT_TASK" ] || exit 0

TASK_RUN_DIR="$AGENT_RUNS_DIR/$CURRENT_TASK"

# ---------------------------------------------------------------------------
# 1. agent-run成果物の存在確認（設計書 §10.1）
# ---------------------------------------------------------------------------

if [ ! -d "$TASK_RUN_DIR" ]; then
  printf 'SubagentStop: agent-runディレクトリがありません: docs/status/agent-runs/%s/\n' "$CURRENT_TASK" >&2
  printf '設計書 §10.1: Generator / Evaluator / Auditorは実行結果をagent-runへ追記します。\n' >&2
  printf '自然言語の完了宣言は完了根拠になりません（設計書 §14.2）。\n' >&2
  exit 2
fi

LATEST_RUN=$(ls -t "$TASK_RUN_DIR"/*.yaml 2>/dev/null | head -1 || true)

if [ -z "$LATEST_RUN" ]; then
  printf 'SubagentStop: agent-run成果物がありません: docs/status/agent-runs/%s/*.yaml\n' "$CURRENT_TASK" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 2. 必須fieldの存在確認
#
# 内容の真偽は判定しない。欠落だけを機械的に検出する。
# ---------------------------------------------------------------------------

MISSING=''
for required_field in agent task result; do
  if ! grep -Eq "^[ ]*${required_field}:" "$LATEST_RUN"; then
    MISSING="$MISSING $required_field"
  fi
done

if [ -n "$MISSING" ]; then
  printf 'SubagentStop: agent-runに必須fieldがありません:%s\n' "$MISSING" >&2
  printf '対象: %s\n' "${LATEST_RUN#"$PROJECT_DIR"/}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 3. taskの整合（設計書 §3.6.1: <task>はcurrent_taskと一致すること）
# ---------------------------------------------------------------------------

RUN_TASK=$(
  LC_ALL=C awk '
    /^[ ]*task:[ \t]*/ {
      sub(/^[ ]*task:[ \t]*/, "")
      gsub(/[ \t\r]+$/, "")
      print
      exit
    }' "$LATEST_RUN"
)

if [ -n "$RUN_TASK" ] && [ "$RUN_TASK" != "$CURRENT_TASK" ]; then
  printf 'SubagentStop: agent-runのtaskがcurrent_taskと一致しません (run=%s, current=%s)\n' \
    "$RUN_TASK" "$CURRENT_TASK" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 4. 未解決blocking findingの確認（設計書 §14.2）
# ---------------------------------------------------------------------------

if grep -Eq '^[ ]*blocking_findings:[ \t]*$' "$LATEST_RUN"; then
  # blocking_findings: の直後に - で始まる項目があれば未解決とみなす
  HAS_BLOCKING=$(
    LC_ALL=C awk '
      /^[ ]*blocking_findings:[ \t]*$/ { in_block = 1; next }
      in_block && /^[ ]*-[ ]/ { print "yes"; exit }
      in_block && /^[ ]*[A-Za-z_]+:/ { exit }
    ' "$LATEST_RUN"
  )
  if [ "$HAS_BLOCKING" = 'yes' ]; then
    printf 'SubagentStop: 未解決のblocking findingが残っています: %s\n' \
      "${LATEST_RUN#"$PROJECT_DIR"/}" >&2
    printf '設計書 §14.2: blocking findingが残る状態で次工程へ遷移しません。\n' >&2
    exit 2
  fi
fi

exit 0
