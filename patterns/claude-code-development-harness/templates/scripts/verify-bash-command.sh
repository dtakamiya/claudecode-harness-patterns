#!/bin/bash
#
# Bashコマンド文字列を構造として検証し、単一のsimple commandであることと
# argv[0]がallowlistに含まれることを確認する。
#
# 正本: 設計書 §3.6.2（Bash allowlist）, templates/rules/permissions.md §4
#
# --- なぜdenylistではないのか ---
#
# permissions.md §4は「メタ文字のdenylistは迂回される」と定める。
# `;` `&&` `|` `$()` を拒否しても、改行(LF)、復帰(CR)、単独の`&`が残り、
# 列挙を増やしてもシェル文法の全体を覆うことはできない。
#
# 本スクリプトはトークナイザでクォート状態を追跡しながら入力を走査し、
# 構造トークン（連鎖・リダイレクト・置換・サブシェル）の**出現そのもの**を
# 検出する。クォート内に現れた同じ文字は文字列として扱うため、
# `git commit -m 'fix; drop table'` は受理される。
#
# 使用法:
#   verify-bash-command.sh --allowlist <file> --writable <dir> -- <command>
#
# 終了コード:
#   0  受理
#   1  拒否（理由コードを標準エラーへ出力）
#   2  使用法の誤り

set -eu

ALLOWLIST_FILE=''
WRITABLE_ROOT=''
COMMAND_STRING=''

reject() {
  # $1: 理由コード, $2: 人間向けの説明
  printf 'DENY %s: %s\n' "$1" "$2" >&2
  exit 1
}

usage_error() {
  printf 'USAGE_ERROR: %s\n' "$1" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case $1 in
    --allowlist)
      [ $# -ge 2 ] || usage_error '--allowlist に値がない'
      ALLOWLIST_FILE=$2
      shift 2
      ;;
    --writable)
      [ $# -ge 2 ] || usage_error '--writable に値がない'
      WRITABLE_ROOT=$2
      shift 2
      ;;
    --)
      shift
      [ $# -ge 1 ] || usage_error '-- の後にコマンドがない'
      COMMAND_STRING=$1
      shift
      break
      ;;
    *)
      usage_error "未知の引数: $1"
      ;;
  esac
done

[ -n "$ALLOWLIST_FILE" ] || usage_error '--allowlist は必須'
[ -f "$ALLOWLIST_FILE" ] || usage_error "allowlistが読めない: $ALLOWLIST_FILE"
[ -n "$WRITABLE_ROOT" ] || usage_error '--writable は必須'

# ---------------------------------------------------------------------------
# 1. トークナイズ
#
# awkで1文字ずつ走査し、クォート状態を追跡する。構造トークンを見つけ次第、
# 理由コードを出力して終了する。受理できる場合はargvを1行1語で出力する。
#
# awkを使うのは、Bash 3.2の`read`やパラメータ展開では
# バイト単位の状態機械を書くと極端に遅く、また改行・CRの扱いが
# 処理系依存になるためである。
# ---------------------------------------------------------------------------

TOKENIZER_OUTPUT=$(
  LC_ALL=C awk '
    BEGIN {
      # 入力全体を1レコードとして受け取る（RSに現れない文字を指定）
      cmd = ARGV[1]
      delete ARGV[1]

      n = length(cmd)
      state = "PLAIN"      # PLAIN | SQUOTE | DQUOTE
      word = ""
      has_word = 0
      argc = 0

      for (i = 1; i <= n; i++) {
        c = substr(cmd, i, 1)
        next_c = (i < n) ? substr(cmd, i + 1, 1) : ""

        if (state == "SQUOTE") {
          if (c == "'"'"'") { state = "PLAIN" } else { word = word c }
          has_word = 1
          continue
        }

        if (state == "DQUOTE") {
          if (c == "\\") {
            # 二重引用符内のバックスラッシュは限定的にエスケープする
            if (next_c == "$" || next_c == "`" || next_c == "\"" || next_c == "\\") {
              word = word next_c
              i++
            } else {
              word = word c
            }
            has_word = 1
            continue
          }
          if (c == "\"") { state = "PLAIN"; has_word = 1; continue }
          # 二重引用符内でもコマンド置換は解釈される
          if (c == "$" && next_c == "(") { deny("COMMAND_SUBSTITUTION", "二重引用符内のコマンド置換") }
          if (c == "`") { deny("COMMAND_SUBSTITUTION", "二重引用符内のバッククォート置換") }
          word = word c
          has_word = 1
          continue
        }

        # --- state == PLAIN ---

        if (c == "\\") {
          if (next_c == "") { deny("PARSE_ERROR", "行末のバックスラッシュ") }
          word = word next_c
          has_word = 1
          i++
          continue
        }

        if (c == "'"'"'") { state = "SQUOTE"; has_word = 1; continue }
        if (c == "\"")    { state = "DQUOTE"; has_word = 1; continue }

        # 置換・展開
        if (c == "`") { deny("COMMAND_SUBSTITUTION", "バッククォート置換") }
        if (c == "$" && next_c == "(") { deny("COMMAND_SUBSTITUTION", "コマンド置換 $()") }
        if ((c == "<" || c == ">") && next_c == "(") { deny("COMMAND_SUBSTITUTION", "プロセス置換") }

        # 連鎖・制御構造。改行とCRを含めることが要点である。
        if (c == ";")  { deny("NOT_SIMPLE_COMMAND", "セミコロンによる連鎖") }
        if (c == "&")  { deny("NOT_SIMPLE_COMMAND", "&によるバックグラウンド実行またはAND連鎖") }
        if (c == "|")  { deny("NOT_SIMPLE_COMMAND", "パイプまたはOR連鎖") }
        if (c == "\n") { deny("NOT_SIMPLE_COMMAND", "改行による連鎖") }
        if (c == "\r") { deny("NOT_SIMPLE_COMMAND", "復帰(CR)による連鎖") }
        if (c == "(" || c == ")") { deny("NOT_SIMPLE_COMMAND", "サブシェル") }
        if (c == "{" || c == "}") { deny("NOT_SIMPLE_COMMAND", "グループコマンドまたはブレース展開") }

        # リダイレクト。先頭のfd指定も含めて検出する。
        if (c == "<" || c == ">") { deny("REDIRECT", "リダイレクト") }

        # 語の区切り
        if (c == " " || c == "\t") {
          if (has_word) { argc++; argv[argc] = word; word = ""; has_word = 0 }
          continue
        }

        word = word c
        has_word = 1
      }

      if (state == "SQUOTE") { deny("PARSE_ERROR", "閉じていない単一引用符") }
      if (state == "DQUOTE") { deny("PARSE_ERROR", "閉じていない二重引用符") }
      if (has_word) { argc++; argv[argc] = word }

      if (argc == 0) { deny("EMPTY_COMMAND", "コマンドが空") }

      # 前置の環境変数代入を拒否する（§4: 隔離前提を崩し得る）
      if (argv[1] ~ /^[A-Za-z_][A-Za-z_0-9]*=/) {
        deny("ENV_ASSIGNMENT", "コマンド前置の環境変数代入")
      }

      print "OK"
      for (j = 1; j <= argc; j++) { print argv[j] }
      exit 0
    }

    function deny(code, message) {
      print "DENY"
      print code
      print message
      exit 0
    }
  ' "$COMMAND_STRING"
)

TOKENIZER_VERDICT=$(printf '%s\n' "$TOKENIZER_OUTPUT" | sed -n '1p')

if [ "$TOKENIZER_VERDICT" = 'DENY' ]; then
  deny_code=$(printf '%s\n' "$TOKENIZER_OUTPUT" | sed -n '2p')
  deny_message=$(printf '%s\n' "$TOKENIZER_OUTPUT" | sed -n '3p')

  # リダイレクトは、先がwritable内であれば許可し得る。§4に従い
  # canonical path化してwritableと照合する。判定できない場合は拒否する。
  if [ "$deny_code" = 'REDIRECT' ]; then
    "$(dirname -- "$0")/verify-redirect-target.sh" \
      --writable "$WRITABLE_ROOT" -- "$COMMAND_STRING" \
      || reject 'REDIRECT_OUT_OF_SCOPE' 'リダイレクト先がwritable範囲外'

    # リダイレクト先が許可された場合、リダイレクト部を除いた本体を再検証する
    COMMAND_BODY=$("$(dirname -- "$0")/verify-redirect-target.sh" \
      --writable "$WRITABLE_ROOT" --print-body -- "$COMMAND_STRING")
    exec "$0" --allowlist "$ALLOWLIST_FILE" --writable "$WRITABLE_ROOT" -- "$COMMAND_BODY"
  fi

  reject "$deny_code" "$deny_message"
fi

if [ "$TOKENIZER_VERDICT" != 'OK' ]; then
  reject 'PARSE_ERROR' 'トークナイザが判定を返さなかった'
fi

# ---------------------------------------------------------------------------
# 2. allowlist照合
#
# §4: 照合はパース後のargv[0]に対して行う。生文字列へのprefix一致は
# 後続に何が続いても通過するため照合にならない。
# ---------------------------------------------------------------------------

ARGV0=$(printf '%s\n' "$TOKENIZER_OUTPUT" | sed -n '2p')

[ -n "$ARGV0" ] || reject 'EMPTY_COMMAND' 'argv[0]が空'

allowlist_hit=0
while IFS= read -r allowlist_entry || [ -n "$allowlist_entry" ]; do
  case $allowlist_entry in
    ''|'#'*) continue ;;
  esac
  if [ "$allowlist_entry" = "$ARGV0" ]; then
    allowlist_hit=1
    break
  fi
done < "$ALLOWLIST_FILE"

[ "$allowlist_hit" -eq 1 ] \
  || reject 'ALLOWLIST_MISS' "argv[0]がallowlistにない: $ARGV0"

exit 0
