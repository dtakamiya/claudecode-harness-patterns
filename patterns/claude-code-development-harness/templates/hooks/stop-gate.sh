#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書 Version 1.10
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# 正本: 設計書 §3.5（State commit）, §10（状態管理）, §14
#
# --- 責務 ---
#
# 設計書 §3.5 State commit行:
#   「Orchestratorによる`progress.yaml`更新、revision整合、
#     未解決ブロッカー、全ゲート状態の確認」
#
# --- 何を検査し、何を検査しないか ---
#
# 本Hookは「セッションを終える前に、状態が壊れたまま放置されていないか」
# だけを見る。工程の完了判定（exit gate）はここではない。
# exit gateはOrchestratorがagent-runとGateRunを検証して判定する（設計書 §3.4.1 実行規則7）。
#
# Stop hookで工程完了を判定しようとすると、「応答を終えるたびに
# 工程が進む」ことになり、設計書 §10のsingle writer原則を壊す。

set -eu

HOOK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(CDPATH='' cd -- "$HOOK_DIR/../.." && pwd)}

PROGRESS_FILE="$PROJECT_DIR/docs/status/progress.yaml"

[ -f "$PROGRESS_FILE" ] || exit 0

WARNINGS=''

add_warning() {
  WARNINGS="$WARNINGS
  - $1"
}

# ---------------------------------------------------------------------------
# 1. revision整合（設計書 §10 楽観ロック）
# ---------------------------------------------------------------------------

REVISION=$(
  LC_ALL=C awk '/^revision:[ \t]*/ { sub(/^revision:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }' \
    "$PROGRESS_FILE"
)
EXPECTED_PREVIOUS=$(
  LC_ALL=C awk '/^expected_previous_revision:[ \t]*/ { sub(/^expected_previous_revision:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }' \
    "$PROGRESS_FILE"
)

if [ -z "$REVISION" ]; then
  add_warning 'progress.yaml に revision がありません（設計書 §10）'
elif [ -n "$EXPECTED_PREVIOUS" ]; then
  # revision は expected_previous_revision より大きくなければならない
  case $REVISION$EXPECTED_PREVIOUS in
    *[!0-9]*) add_warning "revision が数値ではありません (revision=$REVISION, expected_previous=$EXPECTED_PREVIOUS)" ;;
    *)
      if [ "$REVISION" -le "$EXPECTED_PREVIOUS" ]; then
        add_warning "revision が前進していません (revision=$REVISION, expected_previous=$EXPECTED_PREVIOUS)"
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# 2. 未解決blocking issue（設計書 §3.4.1 実行規則7）
# ---------------------------------------------------------------------------

# awkの exit は END ブロックを抑止しない。ここで END から追加出力すると
# "yes\nunknown" のような複数行になり、後続の文字列比較が一致しなくなる。
# 判定は1行だけ出力する。
HAS_BLOCKING=$(
  LC_ALL=C awk '
    /^blocking_issues:[ \t]*\[\][ \t]*$/ { print "no"; exit }
    /^blocking_issues:[ \t]*$/ { in_block = 1; next }
    in_block && /^[ ]*-[ ]/ { print "yes"; exit }
    in_block && /^[A-Za-z_]+:/ { print "no"; exit }
  ' "$PROGRESS_FILE"
)

if [ "$HAS_BLOCKING" = 'yes' ]; then
  add_warning '未解決の blocking_issues が残っています。次工程へ進めません（設計書 §3.4.1 実行規則7）'
fi

# ---------------------------------------------------------------------------
# 3. next_action の存在（設計書 §3.2 継続セッションの再開条件）
#
# 設計書 §3.2は「次のContinuation Agentが会話履歴なしで再開できる」ことを
# 初期化の終了条件に挙げる。next_actionが無いまま終えると、
# 次セッションは会話履歴に依存する。
# ---------------------------------------------------------------------------

if ! grep -Eq '^next_action:' "$PROGRESS_FILE"; then
  add_warning 'next_action がありません。次セッションが履歴なしで再開できません（設計書 §3.2）'
fi

# ---------------------------------------------------------------------------
# 4. 判定
#
# ここでの不備は「状態が未完成のまま終わろうとしている」ことを示す。
# 終了コード2で差し戻し、Orchestratorへ状態更新を促す。
# ---------------------------------------------------------------------------

if [ -n "$WARNINGS" ]; then
  printf 'Stop gate: 状態ファイルに不備があります。\n' >&2
  printf '%s\n' "$WARNINGS" >&2
  printf '\nprogress.yaml の更新は Development Orchestrator が single writer として行います（設計書 §10）。\n' >&2
  exit 2
fi

exit 0
