#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書 Version 1.10
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# 正本: 設計書 §3.5（Detective）, §14
#
# --- このHookの位置づけ（重要）---
#
# 設計書 §3.5は次を明記する。
#
#   「`PostToolUse`は操作後の検知であり、秘密情報の書込み自体を予防できない。
#     機密パスと危険操作はpermissionsおよび`PreToolUse`で遮断し、
#     `PostToolUse`は差分検査と復旧判断に使用する。」
#
# したがって本Hookは**予防ではない**。ここで秘密情報を検出したときには、
# すでにファイルへ書かれている。検出は復旧手続きの起点であって、
# 「防いだ」ことにはならない。予防はpre-tool-use.shとpermissionsが担う。
#
# 本Hookの責務:
#   - 変更ファイルの記録（設計書 §14「ファイル編集後: 変更一覧記録」）
#   - secret scanによる検知と、検出時のFAIL化（設計書 §3.5 Recovery）
#
# formatter / lint はプロジェクト固有のため、雛形では起動点だけを示す。

set -eu

HOOK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(CDPATH='' cd -- "$HOOK_DIR/../.." && pwd)}

CHANGES_DIR="$PROJECT_DIR/docs/status/changes"
PROGRESS_FILE="$PROJECT_DIR/docs/status/progress.yaml"

EVENT_JSON=$(cat)

json_string_field() {
  LC_ALL=C awk -v field="$1" '
    BEGIN { RS = "\0" }
    {
      key = "\"" field "\""
      idx = index($0, key)
      if (idx == 0) { exit }
      rest = substr($0, idx + length(key))
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

FILE_PATH=$(json_string_field 'file_path')

# 対象が取れない場合、検知は行えないが、PostToolUseはすでに実行後である。
# ここでブロックしても書込みは戻らないため、警告して終える。
if [ -z "$FILE_PATH" ]; then
  printf 'PostToolUse: file_pathを取得できず、変更記録とsecret scanを実行できません\n' >&2
  exit 0
fi

case $FILE_PATH in
  /*) ABSOLUTE_PATH=$FILE_PATH ;;
  *)  ABSOLUTE_PATH="$PROJECT_DIR/$FILE_PATH" ;;
esac

[ -f "$ABSOLUTE_PATH" ] || exit 0

# ---------------------------------------------------------------------------
# 1. secret scan（設計書 §3.5 Detective / Recovery）
#
# 検出時は終了コード2でブロックし、復旧を促す。設計書 §3.5 Recovery行は
# 「秘密情報検出時のタスクFAIL化」を求める。
# ---------------------------------------------------------------------------

# 単語境界 `\y` はGNU awkの拡張であり、macOS標準のawkでは
# マッチせず**検出漏れになる**。移植性のため使用しない。
# 同様に `\x27` も避け、シングルクォートは文字クラスで表現する。
SECRET_HIT=$(
  LC_ALL=C awk '
    # 代表的な秘密情報の形。プロジェクトの実態に合わせて追加すること。
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/     { print "private key"; exit }
    /AKIA[0-9A-Z]{16}/                       { print "AWS access key id"; exit }
    /gh[pousr]_[A-Za-z0-9]{36,}/             { print "GitHub token"; exit }
    /xox[baprs]-[A-Za-z0-9-]{10,}/           { print "Slack token"; exit }
    /sk-[A-Za-z0-9]{32,}/                    { print "OpenAI-style API key"; exit }
    /(password|passwd|secret|api[_-]?key|token)[ \t]*[:=][ \t]*["'"'"'][^"'"'"']{8,}["'"'"']/ {
      print "hardcoded credential"; exit
    }
  ' "$ABSOLUTE_PATH" 2>/dev/null || true
)

if [ -n "$SECRET_HIT" ]; then
  printf '秘密情報の可能性を検出しました: %s (%s)\n' "$FILE_PATH" "$SECRET_HIT" >&2
  printf '設計書 §3.5 Recovery: タスクをFAILとし、値のローテーションと差分の取消しを行ってください。\n' >&2
  printf 'PostToolUseは事後検知です。すでにファイルへ書き込まれている前提で対処してください。\n' >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 2. 変更ファイルの記録（設計書 §14 / §3.8 changed_files_manifest）
#
# レビュー対象の変更一覧（docs/status/changes/<task>.yaml）の材料とする。
# ---------------------------------------------------------------------------

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

[ -n "$CURRENT_TASK" ] || exit 0

mkdir -p "$CHANGES_DIR"
CHANGES_FILE="$CHANGES_DIR/${CURRENT_TASK}.touched"

# 相対パスへ揃えて追記する。重複は後段で集約する。
RELATIVE_PATH=${ABSOLUTE_PATH#"$PROJECT_DIR"/}
printf '%s\n' "$RELATIVE_PATH" >> "$CHANGES_FILE"

exit 0
