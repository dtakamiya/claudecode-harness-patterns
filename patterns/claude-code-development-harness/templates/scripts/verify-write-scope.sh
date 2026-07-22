#!/bin/bash
#
# 書込み対象パスが、宣言されたWrite範囲に含まれるかを判定する。
#
# 正本: 設計書 §3.6.1（Write範囲の解決規則）,
#       templates/rules/permissions.md §2, §3
#
# --- 判定順序（この順序に意味がある）---
#
# 1. canonical path化   … 正規化前のraw文字列でglob照合すると
#                          `docs/features/../../etc/x` で迂回される（§2）
# 2. symlink拒否        … リンク先が許可範囲外でも、リンク自体は範囲内に見える
# 3. repo外拒否
# 4. policy照合（最長一致、同一具体度はdeny）
# 5. create-only検査    … 証跡の追記専用要件（§2）
#
# 使用法:
#   verify-write-scope.sh --repo <dir> --policy <file> --path <path>
#
# policyの形式:
#   <mode> <pattern>
#   mode: allow | allow-create-only | deny
#   patternの ${CURRENT_TASK} は progress.yaml の current_task へ展開する。
#
# 終了コード:
#   0  許可
#   1  拒否（理由コードを標準エラーへ出力）
#   2  使用法の誤り

set -eu

REPO_DIR=''
POLICY_FILE=''
TARGET_PATH=''

usage_error() {
  printf 'USAGE_ERROR: %s\n' "$1" >&2
  exit 2
}

reject() {
  printf 'DENY %s: %s\n' "$1" "$2" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case $1 in
    --repo)
      [ $# -ge 2 ] || usage_error '--repo に値がない'
      REPO_DIR=$2; shift 2 ;;
    --policy)
      [ $# -ge 2 ] || usage_error '--policy に値がない'
      POLICY_FILE=$2; shift 2 ;;
    --path)
      [ $# -ge 2 ] || usage_error '--path に値がない'
      TARGET_PATH=$2; shift 2 ;;
    *)
      usage_error "未知の引数: $1" ;;
  esac
done

[ -n "$REPO_DIR" ]    || usage_error '--repo は必須'
[ -n "$POLICY_FILE" ] || usage_error '--policy は必須'
[ -n "$TARGET_PATH" ] || usage_error '--path は必須'
[ -d "$REPO_DIR" ]    || usage_error "repoが存在しない: $REPO_DIR"
[ -f "$POLICY_FILE" ] || usage_error "policyが読めない: $POLICY_FILE"

CANONICAL_REPO=$(CDPATH='' cd -- "$REPO_DIR" && pwd -P) \
  || usage_error "repoを正規化できない: $REPO_DIR"

# ---------------------------------------------------------------------------
# 1. symlink拒否
#
# 正規化より先に検査する。canonical path化はリンクを解決してしまうため、
# 解決後に判定すると「リンク先が許可範囲内なら通す」ことになり、
# リンクの張替えで範囲外へ到達できる。
# ---------------------------------------------------------------------------

# 相対パスはrepo基準で解釈する。
#
# 絶対パス指定は、呼び出し側が渡したprefix（例: /var/...）が
# CANONICAL_REPO（例: /private/var/...）と字句的に一致しないことがある。
# macOSの /var → /private/var のように、上位経路自体がsymlinkである場合に起きる。
# ここでrepo prefixを正規化形へ揃えておかないと、repo配下のパスが
# PATH_ESCAPES_REPOとして誤って拒否される。
case $TARGET_PATH in
  /*)
    ABSOLUTE_TARGET=$TARGET_PATH
    # 呼び出し側が非正規形のrepo prefixを使っている場合、正規形へ揃える
    if [ "$REPO_DIR" != "$CANONICAL_REPO" ]; then
      case $ABSOLUTE_TARGET in
        "$REPO_DIR"/*)
          ABSOLUTE_TARGET="$CANONICAL_REPO/${ABSOLUTE_TARGET#"$REPO_DIR"/}"
          ;;
      esac
    fi
    ;;
  *)  ABSOLUTE_TARGET="$CANONICAL_REPO/$TARGET_PATH" ;;
esac

if [ -L "$ABSOLUTE_TARGET" ]; then
  reject 'SYMLINK_REJECTED' "書込み対象がsymlink: $TARGET_PATH"
fi

# 経路上のディレクトリにsymlinkが含まれる場合も拒否する。
#
# 走査はrepo配下だけを対象とする。repoより上位（/var が /private/var への
# symlinkであるmacOS等）まで遡ると、リポジトリの構成と無関係な理由で
# 全書込みが拒否される。上位経路はCANONICAL_REPOの算出時点で
# 解決済みであり、ここで再検査する対象ではない。
symlink_scan_dir=$(dirname -- "$ABSOLUTE_TARGET")
while [ -n "$symlink_scan_dir" ] && [ "$symlink_scan_dir" != '/' ]; do
  # repoの外へ出たら走査を終える
  case $symlink_scan_dir in
    "$CANONICAL_REPO") break ;;
    "$CANONICAL_REPO"/*) : ;;
    *) break ;;
  esac
  if [ -L "$symlink_scan_dir" ]; then
    reject 'SYMLINK_REJECTED' "経路にsymlinkを含む: $symlink_scan_dir"
  fi
  parent=$(dirname -- "$symlink_scan_dir")
  [ "$parent" != "$symlink_scan_dir" ] || break
  symlink_scan_dir=$parent
done

# ---------------------------------------------------------------------------
# 2. canonical path化
#
# 書込み対象のファイル自体は未作成でよいため、親ディレクトリを正規化する。
# ---------------------------------------------------------------------------

target_parent=$(dirname -- "$ABSOLUTE_TARGET")
if [ -d "$target_parent" ]; then
  canonical_parent=$(CDPATH='' cd -- "$target_parent" && pwd -P) \
    || reject 'PATH_UNRESOLVABLE' "親ディレクトリを正規化できない: $TARGET_PATH"
else
  # 親が未作成の場合、`..` を字句的に畳んでから判定する。
  # 実在しない経路は cd で正規化できないため、ここだけ字句解決を用いる。
  canonical_parent=$(
    LC_ALL=C awk -v path="$target_parent" '
      BEGIN {
        n = split(path, parts, "/")
        depth = 0
        for (i = 1; i <= n; i++) {
          if (parts[i] == "" || parts[i] == ".") continue
          if (parts[i] == "..") { if (depth > 0) depth--; else { print "ESCAPE"; exit } ; continue }
          depth++
          stack[depth] = parts[i]
        }
        out = ""
        for (i = 1; i <= depth; i++) out = out "/" stack[i]
        print (out == "" ? "/" : out)
      }'
  )
  [ "$canonical_parent" != 'ESCAPE' ] \
    || reject 'PATH_ESCAPES_REPO' "パスがルートより上を指す: $TARGET_PATH"
fi

CANONICAL_TARGET="$canonical_parent/$(basename -- "$ABSOLUTE_TARGET")"

# ---------------------------------------------------------------------------
# 3. repo外拒否
# ---------------------------------------------------------------------------

case $CANONICAL_TARGET in
  "$CANONICAL_REPO"/*) : ;;
  *) reject 'PATH_ESCAPES_REPO' "リポジトリ外へ解決される: $CANONICAL_TARGET" ;;
esac

# repo相対の形へ戻す。policyのpatternはrepo相対で書かれている。
RELATIVE_TARGET=${CANONICAL_TARGET#"$CANONICAL_REPO"/}

# ---------------------------------------------------------------------------
# 4. policy照合（最長一致、同一具体度はdeny）
# ---------------------------------------------------------------------------

CURRENT_TASK=''
progress_file="$CANONICAL_REPO/docs/status/progress.yaml"
if [ -f "$progress_file" ]; then
  CURRENT_TASK=$(
    LC_ALL=C awk '
      /^current_task:[ \t]*/ {
        sub(/^current_task:[ \t]*/, "")
        gsub(/[ \t\r]+$/, "")
        print
        exit
      }' "$progress_file"
  )
fi

best_specificity=-1
best_mode=''

while IFS= read -r policy_line || [ -n "$policy_line" ]; do
  case $policy_line in
    ''|'#'*) continue ;;
  esac

  policy_mode=${policy_line%%[ 	]*}
  policy_pattern=${policy_line#*[ 	]}
  # 先頭の余白を落とす
  while :; do
    case $policy_pattern in
      ' '*|'	'*) policy_pattern=${policy_pattern#?} ;;
      *) break ;;
    esac
  done

  case $policy_mode in
    allow|allow-create-only|deny) : ;;
    *) usage_error "未知のpolicy mode: $policy_mode" ;;
  esac

  # ${CURRENT_TASK} を展開する。current_taskが未確定なら、
  # このパターンは照合対象にしない（fail-closed）。
  case $policy_pattern in
    *'${CURRENT_TASK}'*)
      [ -n "$CURRENT_TASK" ] || continue
      policy_pattern=$(
        LC_ALL=C awk -v p="$policy_pattern" -v t="$CURRENT_TASK" '
          BEGIN {
            idx = index(p, "${CURRENT_TASK}")
            while (idx > 0) {
              p = substr(p, 1, idx - 1) t substr(p, idx + length("${CURRENT_TASK}"))
              idx = index(p, "${CURRENT_TASK}")
            }
            print p
          }'
      )
      ;;
  esac

  # 照合。`**` を任意深さ、`*` を単一階層として扱う。
  # caseのglobは `**` と `*` を区別しないため、`**` を含むpatternは
  # prefix照合、含まないpatternは完全一致で判定する。
  matched=0
  case $policy_pattern in
    *'**')
      pattern_prefix=${policy_pattern%'**'}
      case $RELATIVE_TARGET in
        "$pattern_prefix"*) matched=1 ;;
      esac
      ;;
    *)
      case $RELATIVE_TARGET in
        $policy_pattern) matched=1 ;;
      esac
      ;;
  esac

  [ "$matched" -eq 1 ] || continue

  # 具体度はパターンの文字数で測る。長いほど具体的とみなす。
  specificity=${#policy_pattern}

  if [ "$specificity" -gt "$best_specificity" ]; then
    best_specificity=$specificity
    best_mode=$policy_mode
  elif [ "$specificity" -eq "$best_specificity" ] && [ "$best_mode" != "$policy_mode" ]; then
    # 同一具体度の競合はdenyを採る（§2 競合時deny / fail-closed）
    best_mode='deny'
  fi
done < "$POLICY_FILE"

if [ "$best_specificity" -lt 0 ]; then
  reject 'NOT_IN_WRITE_SCOPE' "許可されたWrite範囲にない: $RELATIVE_TARGET"
fi

if [ "$best_mode" = 'deny' ]; then
  reject 'EXPLICIT_DENY' "明示的に禁止されたパス: $RELATIVE_TARGET"
fi

# ---------------------------------------------------------------------------
# 5. create-only検査（§2 証跡は追記専用）
# ---------------------------------------------------------------------------

if [ "$best_mode" = 'allow-create-only' ] && [ -e "$CANONICAL_TARGET" ]; then
  reject 'CREATE_ONLY_VIOLATION' "既存ファイルへの書込みは禁止: $RELATIVE_TARGET"
fi

exit 0
