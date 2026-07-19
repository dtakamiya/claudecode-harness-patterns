#!/bin/bash
#
# リダイレクトを含むコマンドについて、リダイレクト先がwritable範囲内かを判定する。
#
# 正本: 設計書 §3.6.1（Write範囲の解決規則）, §3.6.2,
#       templates/rules/permissions.md §2, §4
#
# §4: 「リダイレクトを許可する場合、リダイレクト先をcanonical path化して
#       writableと照合する。判定できない場合は拒否する。」
#
# 使用法:
#   verify-redirect-target.sh --writable <dir> [--print-body] -- <command>
#
# --print-body を与えた場合、リダイレクト部を除いたコマンド本体を標準出力へ返す。
# 呼び出し側はこれを再帰的に検証する。
#
# 終了コード:
#   0  リダイレクト先がすべてwritable範囲内
#   1  範囲外、または判定不能
#   2  使用法の誤り

set -eu

WRITABLE_ROOT=''
PRINT_BODY=0
COMMAND_STRING=''

usage_error() {
  printf 'USAGE_ERROR: %s\n' "$1" >&2
  exit 2
}

reject() {
  printf 'DENY REDIRECT_OUT_OF_SCOPE: %s\n' "$1" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case $1 in
    --writable)
      [ $# -ge 2 ] || usage_error '--writable に値がない'
      WRITABLE_ROOT=$2
      shift 2
      ;;
    --print-body)
      PRINT_BODY=1
      shift
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

[ -n "$WRITABLE_ROOT" ] || usage_error '--writable は必須'

# writable rootをcanonical path化する。存在しないrootは判定不能として扱う。
[ -d "$WRITABLE_ROOT" ] || reject "writable rootが存在しない: $WRITABLE_ROOT"
CANONICAL_WRITABLE=$(CDPATH='' cd -- "$WRITABLE_ROOT" && pwd -P) \
  || reject "writable rootを正規化できない: $WRITABLE_ROOT"

# ---------------------------------------------------------------------------
# リダイレクトの切り出し
#
# クォート状態を追跡しながら `>` `>>` `<` を検出し、直後の語を
# リダイレクト先として取り出す。本体語とリダイレクト語を別々に出力する。
# ---------------------------------------------------------------------------

PARSED=$(
  LC_ALL=C awk '
    BEGIN {
      cmd = ARGV[1]
      delete ARGV[1]

      n = length(cmd)
      state = "PLAIN"
      word = ""
      has_word = 0
      pending_redirect = 0
      body_n = 0
      target_n = 0

      for (i = 1; i <= n; i++) {
        c = substr(cmd, i, 1)
        next_c = (i < n) ? substr(cmd, i + 1, 1) : ""

        if (state == "SQUOTE") {
          if (c == "'"'"'") { state = "PLAIN" } else { word = word c }
          has_word = 1
          continue
        }
        if (state == "DQUOTE") {
          if (c == "\\" && (next_c == "$" || next_c == "`" || next_c == "\"" || next_c == "\\")) {
            word = word next_c; i++; has_word = 1; continue
          }
          if (c == "\"") { state = "PLAIN"; has_word = 1; continue }
          word = word c; has_word = 1; continue
        }

        if (c == "\\") {
          if (next_c == "") { print "ERROR"; print "行末のバックスラッシュ"; exit 0 }
          word = word next_c; i++; has_word = 1; continue
        }
        if (c == "'"'"'") { state = "SQUOTE"; has_word = 1; continue }
        if (c == "\"")    { state = "DQUOTE"; has_word = 1; continue }

        if (c == ">" || c == "<") {
          # 語を確定させる。`2>` のようなfd指定は語末の数字として現れる。
          if (has_word) {
            if (word ~ /^[0-9]+$/) {
              # fd指定。本体語にしない。
              word = ""; has_word = 0
            } else {
              emit_body(word); word = ""; has_word = 0
            }
          }
          # `>>` は1つのリダイレクト演算子として消費する
          if (c == ">" && next_c == ">") { i++ }
          pending_redirect = 1
          continue
        }

        if (c == " " || c == "\t") {
          if (has_word) {
            if (pending_redirect) { emit_target(word); pending_redirect = 0 }
            else { emit_body(word) }
            word = ""; has_word = 0
          }
          continue
        }

        word = word c
        has_word = 1
      }

      if (state != "PLAIN") { print "ERROR"; print "閉じていない引用符"; exit 0 }
      if (has_word) {
        if (pending_redirect) { emit_target(word); pending_redirect = 0 }
        else { emit_body(word) }
      }
      if (pending_redirect) { print "ERROR"; print "リダイレクト先が指定されていない"; exit 0 }

      print "OK"
      print body_n
      for (j = 1; j <= body_n; j++) { print body[j] }
      print target_n
      for (j = 1; j <= target_n; j++) { print target[j] }
      exit 0
    }

    function emit_body(w)   { body_n++;   body[body_n] = w }
    function emit_target(w) { target_n++; target[target_n] = w }
  ' "$COMMAND_STRING"
)

VERDICT=$(printf '%s\n' "$PARSED" | sed -n '1p')
if [ "$VERDICT" != 'OK' ]; then
  reject "$(printf '%s\n' "$PARSED" | sed -n '2p')"
fi

BODY_COUNT=$(printf '%s\n' "$PARSED" | sed -n '2p')
TARGET_START=$((3 + BODY_COUNT))
TARGET_COUNT=$(printf '%s\n' "$PARSED" | sed -n "${TARGET_START}p")

[ "$TARGET_COUNT" -ge 1 ] || reject 'リダイレクト先を特定できなかった'

# ---------------------------------------------------------------------------
# リダイレクト先の照合
#
# §2: canonical pathへ正規化してから判定し、`..` traversal、
#     writable外へ解決されるパス、symlinkを拒否する。
# ---------------------------------------------------------------------------

target_index=0
while [ "$target_index" -lt "$TARGET_COUNT" ]; do
  target_index=$((target_index + 1))
  line_no=$((TARGET_START + target_index))
  redirect_target=$(printf '%s\n' "$PARSED" | sed -n "${line_no}p")

  [ -n "$redirect_target" ] || reject 'リダイレクト先が空'

  # 未展開の変数・チルダを含む先は判定不能として拒否する
  case $redirect_target in
    *'$'*|'~'*) reject "リダイレクト先に未展開の展開が含まれ判定できない: $redirect_target" ;;
  esac

  # symlinkそのものへの書込みを拒否する
  if [ -L "$redirect_target" ]; then
    reject "リダイレクト先がsymlink: $redirect_target"
  fi

  # 親ディレクトリを正規化する。ファイル自体は未作成でもよい。
  target_dir=$(dirname -- "$redirect_target")
  [ -d "$target_dir" ] || reject "リダイレクト先の親ディレクトリが存在せず判定できない: $redirect_target"

  canonical_dir=$(CDPATH='' cd -- "$target_dir" && pwd -P) \
    || reject "リダイレクト先を正規化できない: $redirect_target"

  canonical_target="$canonical_dir/$(basename -- "$redirect_target")"

  # writable root配下であることを、正規化後のパスで照合する
  case $canonical_target in
    "$CANONICAL_WRITABLE"/*) : ;;
    *) reject "リダイレクト先がwritable範囲外: $canonical_target" ;;
  esac
done

if [ "$PRINT_BODY" -eq 1 ]; then
  body_index=0
  body_output=''
  while [ "$body_index" -lt "$BODY_COUNT" ]; do
    body_index=$((body_index + 1))
    line_no=$((2 + body_index))
    body_word=$(printf '%s\n' "$PARSED" | sed -n "${line_no}p")
    if [ -z "$body_output" ]; then
      body_output=$body_word
    else
      body_output="$body_output $body_word"
    fi
  done
  printf '%s\n' "$body_output"
fi

exit 0
