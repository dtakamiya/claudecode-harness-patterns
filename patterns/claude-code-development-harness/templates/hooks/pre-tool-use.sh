#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書 Version 1.10
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# この雛形は上記パターンリポジトリの`templates/hooks/`が配布元であり、
# 利用者の`.claude/hooks/`へコピーして使う。本文中の「設計書 §N」は
# すべて上記URLの設計書の該当節を指す。
#
# 正本: 設計書 §3.5（Preventive）, §3.6.1（Write範囲）, §3.6.2（Bash allowlist）,
#       §14.1（Fullモードの適用順序）, templates/rules/permissions.md §2, §4
#
# --- このHookの位置づけ（重要）---
#
# 本Hookは設計書 §3.5の`Preventive`段を担うが、**単独では境界にならない。**
# 設計書 §3.5は「Hookだけをサンドボックスやpermissionsの代替にしない」と定める。
# permissions（settings.jsonのdeny）とsandboxを併用すること。
#
# 本Hookが担うのは、permissionsのglobでは表現できない次の判定である。
#   - canonical path正規化後のwrite scope照合（§3.6.1）
#   - 証跡のcreate-only強制（§3.6.1）
#   - Bashコマンドの構造検証とallowlist照合（§3.6.2）
#
# --- 前提となるバイナリ ---
#
# 判定ロジックは scripts/ 配下の2本へ委譲する。Hook側は
# Claude Codeのプロトコル変換だけを行う。
#   scripts/verify-bash-command.sh
#   scripts/verify-write-scope.sh
#
# --- 入出力（Claude Code hooks プロトコル）---
#
# stdin:  PreToolUseのイベントJSON（tool_name, tool_input, cwd を使う）
# stdout: permissionDecision を含むJSON
# 終了コード0で、JSONの permissionDecision により allow / deny を伝える。
#
# fail-closed: 判定に必要な情報が得られない場合はdenyとする（設計書 §3.4.1 実行規則3）。

set -eu

HOOK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(CDPATH='' cd -- "$HOOK_DIR/../.." && pwd)}

SCRIPTS_DIR="$PROJECT_DIR/scripts"
POLICY_FILE="$PROJECT_DIR/.claude/write-scope-policy"
ALLOWLIST_FILE="$PROJECT_DIR/.claude/bash-allowlist"

# ---------------------------------------------------------------------------
# 応答ヘルパ
# ---------------------------------------------------------------------------

json_escape() {
  # 制御文字を含む理由文字列をJSON文字列へ埋め込めるようにする。
  #
  # 値は -v ではなくstdinで渡す。awkの -v は代入時にエスケープを解釈するため、
  # 実際の改行を含む文字列を渡すと "newline in string" で異常終了する。
  # 理由文字列は複数行になり得るため、ここは必ずstdin経由とする。
  printf '%s' "$1" | LC_ALL=C awk '
    BEGIN { RS = "\0" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/,  "\\\"", s)
      gsub(/\n/, "\\n", s)
      gsub(/\r/, "\\r", s)
      gsub(/\t/, "\\t", s)
      printf "%s", s
    }'
}

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}\n'
  exit 0
}

deny() {
  deny_reason=$(json_escape "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$deny_reason"
  exit 0
}

# ---------------------------------------------------------------------------
# 入力の取得
#
# jqへ依存しない。ハーネスの導入先にjqがあるとは限らず、
# 前提が増えるほど「Hookが動かないので外す」という運用へ傾く。
# ---------------------------------------------------------------------------

EVENT_JSON=$(cat)

json_string_field() {
  # $1: フィールド名。トップレベルまたはtool_input直下の文字列値を取り出す。
  #
  # RS="\0" で入力全体を1レコードとして受け取る。この処理はBEGINではなく
  # レコード処理ブロックへ置く必要がある（BEGINの時点では$0が未設定）。
  LC_ALL=C awk -v field="$1" '
    BEGIN { RS = "\0" }
    {
      key = "\"" field "\""
      idx = index($0, key)
      if (idx == 0) { exit }
      rest = substr($0, idx + length(key))

      # コロンと空白を読み飛ばす
      i = 1
      while (i <= length(rest)) {
        c = substr(rest, i, 1)
        if (c == ":" || c == " " || c == "\t" || c == "\n" || c == "\r") { i++; continue }
        break
      }
      if (substr(rest, i, 1) != "\"") { exit }
      i++

      out = ""
      while (i <= length(rest)) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          esc = substr(rest, i + 1, 1)
          if      (esc == "n")  { out = out "\n" }
          else if (esc == "r")  { out = out "\r" }
          else if (esc == "t")  { out = out "\t" }
          else if (esc == "\\") { out = out "\\" }
          else if (esc == "\"") { out = out "\"" }
          else if (esc == "/")  { out = out "/" }
          else if (esc == "u") {
            # \uXXXX。ASCII範囲だけ復元し、範囲外は判定不能として印を付ける
            hex = substr(rest, i + 2, 4)
            if (hex ~ /^00[0-7][0-9A-Fa-f]$/) {
              code = 0
              for (k = 1; k <= 4; k++) {
                ch = substr(hex, k, 1)
                v = index("0123456789abcdef", tolower(ch)) - 1
                code = code * 16 + v
              }
              out = out sprintf("%c", code)
            } else {
              print "__NON_ASCII_ESCAPE__"
              exit
            }
            i += 4
          }
          else { out = out esc }
          i += 2
          continue
        }
        if (c == "\"") { break }
        out = out c
        i++
      }
      print out
    }' <<EOF
$EVENT_JSON
EOF
}

TOOL_NAME=$(json_string_field 'tool_name')
[ -n "$TOOL_NAME" ] || deny 'PreToolUse: tool_nameを取得できず判定できない（fail-closed）'

# 判定に使う設定が無い場合は通さない。設定漏れを「制限なし」と解釈しない。
case $TOOL_NAME in
  Bash)
    # 変数展開は必ず ${VAR} で閉じる。直後に続く全角括弧が変数名の一部として
    # 解釈され、set -u のもとで unbound variable となるため。
    [ -f "$ALLOWLIST_FILE" ] \
      || deny "Bash allowlistが存在しない: ${ALLOWLIST_FILE}（fail-closed。設計書 §3.6.2）"
    [ -x "$SCRIPTS_DIR/verify-bash-command.sh" ] \
      || deny "verify-bash-command.sh が実行できない（fail-closed）"
    ;;
  Write|Edit|NotebookEdit)
    [ -f "$POLICY_FILE" ] \
      || deny "write scope policyが存在しない: ${POLICY_FILE}（fail-closed。設計書 §3.6.1）"
    [ -x "$SCRIPTS_DIR/verify-write-scope.sh" ] \
      || deny "verify-write-scope.sh が実行できない（fail-closed）"
    ;;
  *)
    # 判定対象外のツールは、permissions側の既定に委ねる
    allow
    ;;
esac

# ---------------------------------------------------------------------------
# Bash: コマンドの構造検証とallowlist照合（設計書 §3.6.2）
# ---------------------------------------------------------------------------

if [ "$TOOL_NAME" = 'Bash' ]; then
  COMMAND=$(json_string_field 'command')

  [ "$COMMAND" != '__NON_ASCII_ESCAPE__' ] \
    || deny 'コマンドに復元できないエスケープが含まれ、構造を検証できない（fail-closed）'
  [ -n "$COMMAND" ] \
    || deny 'Bashコマンドを取得できず判定できない（fail-closed）'

  # 実行時作業領域（設計書 §3.6.3）。リポジトリ外の使い捨て領域を渡す。
  WRITABLE_ROOT=${HARNESS_SCRATCH_DIR:-}
  if [ -z "$WRITABLE_ROOT" ] || [ ! -d "$WRITABLE_ROOT" ]; then
    # scratchが未設定の場合、リダイレクトを含むコマンドは判定できない。
    # 通さずに差し戻す（設計書 §3.6.3: 判定できない場合は拒否）。
    WRITABLE_ROOT="$PROJECT_DIR/.harness-scratch-unset"
  fi

  if verify_output=$("$SCRIPTS_DIR/verify-bash-command.sh" \
      --allowlist "$ALLOWLIST_FILE" \
      --writable "$WRITABLE_ROOT" \
      -- "$COMMAND" 2>&1); then
    allow
  fi

  deny "Bashコマンドを拒否しました。$verify_output
（設計書 §3.6.2 / rules/permissions.md §4。allowlistへの追加は §16-2 の監査を経ること）"
fi

# ---------------------------------------------------------------------------
# Write / Edit: write scope照合（設計書 §3.6.1）
# ---------------------------------------------------------------------------

FILE_PATH=$(json_string_field 'file_path')

[ "$FILE_PATH" != '__NON_ASCII_ESCAPE__' ] \
  || deny 'file_pathに復元できないエスケープが含まれ、判定できない（fail-closed）'
[ -n "$FILE_PATH" ] \
  || deny "${TOOL_NAME}: file_pathを取得できず判定できない（fail-closed）"

if verify_output=$("$SCRIPTS_DIR/verify-write-scope.sh" \
    --repo "$PROJECT_DIR" \
    --policy "$POLICY_FILE" \
    --path "$FILE_PATH" 2>&1); then
  allow
fi

deny "書込みを拒否しました。$verify_output
（設計書 §3.6.1 / rules/permissions.md §2）"
