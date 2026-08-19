#!/usr/bin/env bash
# レビュー対象の差分を決定論的に取得する。
#
# 設計書 §2.2 / §4.1: 対象確定は「細い橋」であり低自由度に置く。
# 対象がずれると以降のレビューすべてが無効になるため、取得手順をここへ固定する。
#
# 使い方:
#   collect_diff.sh              作業ツリーの未コミット変更 (git diff HEAD)
#   collect_diff.sh <branch>     merge-base 起点の差分
#   collect_diff.sh '#123'       PR の差分 (gh 必須)
#   collect_diff.sh -- <path>    当該パスに触れている差分のみ（-- でパスを明示）
#   collect_diff.sh <path>       同上（曖昧な場合は -- を使う）
#
# 終了コード:
#   0  差分を取得した（stdout に diff、stderr にサマリ）
#   1  取得に失敗した / 対象が0行 → 呼び出し側は停止すること

set -uo pipefail

die() { printf 'DIFF-REVIEW-ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "gitリポジトリではありません。レビュー対象を確定できないため停止します。"

# `-- <path>` はパス指定を明示する形式。先頭ハイフンのパスやブランチ名と
# 同名のファイルを、曖昧さなくパスとして解釈させる。
FORCE_PATH=0
if [ "${1-}" = "--" ]; then
  FORCE_PATH=1
  shift
fi

ARG="${1-}"
DIFF=""
SCOPE=""

if [ "$FORCE_PATH" -eq 1 ]; then
  [ -n "$ARG" ] || die "-- の後にパスが指定されていません。"
  [ -e "$ARG" ] || die "パス '${ARG}' が存在しません。対象が確定しないため停止します。"
  SCOPE="${ARG} に触れている差分のみ（パス配下の全体ではない）"
  DIFF="$(git diff HEAD -- "$ARG" 2>/dev/null)"

elif [ -z "$ARG" ]; then
  SCOPE="作業ツリーの未コミット変更 (git diff HEAD)"
  DIFF="$(git diff HEAD 2>/dev/null)"
  # HEAD が無い（初回コミット前）場合はステージ済みを見る
  if [ -z "$DIFF" ] && ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    SCOPE="初回コミット前のステージ済み変更 (git diff --cached)"
    DIFF="$(git diff --cached 2>/dev/null)"
  fi

elif printf '%s' "$ARG" | grep -qE '^#[0-9]+$|^https?://.*/pull/[0-9]+'; then
  # `#123` と PR URL の双方から番号だけを取り出す。URL をそのまま gh へ渡すと
  # リポジトリ解決が gh 任せになり、別リポジトリの差分を掴む恐れがある。
  PR="$(printf '%s' "$ARG" | sed -E 's|^.*/pull/([0-9]+).*$|\1|; s|^#||')"
  printf '%s' "$PR" | grep -qE '^[0-9]+$' \
    || die "PR指定 '${ARG}' から番号を抽出できませんでした。"
  command -v gh >/dev/null 2>&1 \
    || die "PR指定ですが gh コマンドがありません。対象を取得できないため停止します。"
  SCOPE="PR ${ARG} (gh pr diff)"
  GH_OUT="$(gh pr diff "$PR" 2>&1)" || die "PR ${ARG} の差分を取得できませんでした。gh の出力 → ${GH_OUT}"
  DIFF="$GH_OUT"

elif git rev-parse --verify --quiet "$ARG" >/dev/null 2>&1; then
  # 同名のブランチとパスが両方存在すると、対象が黙ってずれる。
  # 「対象確定は細い橋」であり、曖昧さは推測で解決せず利用者へ返す。
  if [ -e "$ARG" ]; then
    die "'${ARG}' はブランチとパスの両方として解決できます。曖昧さを避けるため停止します。ブランチなら 'refs/heads/${ARG}'、パスなら '-- ${ARG}' と明示してください。"
  fi
  BASE="$(git merge-base HEAD "$ARG" 2>/dev/null)" \
    || die "HEAD と ${ARG} の merge-base を特定できませんでした。"
  SCOPE="${ARG} との差分 (merge-base ${BASE:0:8} 起点)"
  DIFF="$(git diff "$BASE"...HEAD 2>/dev/null)"

elif [ -e "$ARG" ]; then
  # パス指定: 配下の全体ではなく「当該パスに触れている差分」のみ（設計書 §3.4）
  SCOPE="${ARG} に触れている差分のみ（パス配下の全体ではない）"
  DIFF="$(git diff HEAD -- "$ARG" 2>/dev/null)"

else
  die "引数 '${ARG}' をブランチ・PR番号・既存パスのいずれとしても解決できませんでした。対象が確定しないため停止します。"
fi

if [ -z "$DIFF" ]; then
  die "対象の差分が0行です（範囲: ${SCOPE}）。レビュー対象が存在しないため停止します。"
fi

FILES="$(printf '%s\n' "$DIFF" | grep -c '^diff --git ' || true)"
# ヘッダ行（--- a/... +++ b/...）だけを除外し、残る +/- 行を数える。
# `^[+-]([^+-]|$)` だと `- item` のような内容行まで巻き添えで落ちる。
LINES="$(printf '%s\n' "$DIFF" | grep -vE '^(--- |\+\+\+ )' | grep -cE '^[+-]' || true)"

note "DIFF-REVIEW-SCOPE: ${SCOPE}"
note "DIFF-REVIEW-FILES: ${FILES}"
note "DIFF-REVIEW-CHANGED-LINES: ${LINES}"

printf '%s\n' "$DIFF"
