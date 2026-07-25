#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# 配布元: このパターンリポジトリの templates/scripts/。
# 利用者リポジトリの scripts/ へコピーして使う。
#
# 正本: 実装計画 quizzical-munching-origami §1
#
# ---------------------------------------------------------------------------
# bootstrapプロファイルの鶏と卵を解く状態書込みラッパ。
#
# なぜ必要か:
#   docs/status/progress.yaml は write-scope-policy と permissions.deny の
#   二重でdenyされており、通常のWriteツールでは確定できない。しかし
#   revision整合の検証を経ずに任意コピーを許すと、write-scope-policyの
#   fail-closedな検証を丸ごと迂回する穴になる。
#
#   本スクリプトは argv[0]（./scripts/harness-state-write.sh）の完全一致で
#   allowlistへ載る専用コマンドとし、確定先パスをスクリプト内で
#   ホワイトリスト固定する。モデルは docs/status/.staging/ 配下へ
#   通常のWriteツールで書き、本スクリプトが検証してから
#   atomic renameで確定させる。
#
# 使用法:
#   harness-state-write.sh progress
#   harness-state-write.sh phase-run <id>
#   harness-state-write.sh handoff <feature-id> <name>
#
# 終了コード:
#   0  確定に成功
#   1  検証エラー、使用法の誤り（fail-closed）
# ---------------------------------------------------------------------------

set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(CDPATH='' cd -- "$SELF_DIR/.." && pwd)}

STAGING_DIR="$PROJECT_DIR/docs/status/.staging"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'usage: %s progress|phase-run <id>|handoff <feature-id> <name>\n' "$0" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 識別子の検証。パス構成に使う値は英数字・ハイフン・アンダースコアのみ許す。
# `..`、`/`、symlink化されうる文字を含めない。
# ---------------------------------------------------------------------------

validate_identifier() {
  id_value=$1
  id_label=$2
  case $id_value in
    '') fail "${id_label}が空" ;;
    *[!A-Za-z0-9_-]*) fail "${id_label}に使用できない文字が含まれる: $id_value" ;;
  esac
}

# ---------------------------------------------------------------------------
# staging側のファイルを検証する。symlinkは拒否する。
# ---------------------------------------------------------------------------

require_staged_file() {
  staged_path=$1
  [ -e "$staged_path" ] || fail "ステージングにファイルが無い: ${staged_path#"$PROJECT_DIR"/}"
  [ -L "$staged_path" ] && fail "ステージングのファイルがsymlink: ${staged_path#"$PROJECT_DIR"/}"
  [ -f "$staged_path" ] || fail "ステージングのパスが通常ファイルでない: ${staged_path#"$PROJECT_DIR"/}"
}

# ---------------------------------------------------------------------------
# progress.yaml の内容検証（stop-gate.shの検証条件と同一の不変条件を
# 書込み前に課す）。
# ---------------------------------------------------------------------------

validate_progress_content() {
  staged_path=$1
  dest_path=$2

  revision=$(
    LC_ALL=C awk '/^revision:[ \t]*/ { sub(/^revision:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }' \
      "$staged_path"
  )
  expected_previous=$(
    LC_ALL=C awk '/^expected_previous_revision:[ \t]*/ { sub(/^expected_previous_revision:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }' \
      "$staged_path"
  )

  [ -n "$revision" ] || fail 'progress: revision が無い'
  case $revision in
    *[!0-9]*) fail "progress: revision が数値でない: $revision" ;;
  esac

  [ -n "$expected_previous" ] || fail 'progress: expected_previous_revision が無い'
  case $expected_previous in
    *[!0-9]*) fail "progress: expected_previous_revision が数値でない: $expected_previous" ;;
  esac

  # 既存のprogress.yamlがあれば、その revision と expected_previous_revision が
  # 一致することを要求する（楽観ロック）。無ければ初回として expected_previous
  # が既存の値と同じであること自体は不要（種の配置時点）。
  if [ -f "$dest_path" ]; then
    existing_revision=$(
      LC_ALL=C awk '/^revision:[ \t]*/ { sub(/^revision:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }' \
        "$dest_path"
    )
    [ -n "$existing_revision" ] || fail '既存のprogress.yamlにrevisionが無い（壊れている）'
    case $existing_revision in
      *[!0-9]*) fail "既存のprogress.yamlのrevisionが数値でない: $existing_revision" ;;
    esac
    [ "$expected_previous" -eq "$existing_revision" ] \
      || fail "expected_previous_revision(${expected_previous})が既存のrevision(${existing_revision})と一致しない（楽観ロック違反）"
    [ "$revision" -eq $((existing_revision + 1)) ] \
      || fail "revision(${revision})は既存revision(${existing_revision})の+1でなければならない"
  else
    [ "$revision" -eq $((expected_previous + 1)) ] \
      || fail "revision(${revision})はexpected_previous_revision(${expected_previous})の+1でなければならない"
  fi

  grep -Eq '^current_task:[ \t]*[^ \t]' "$staged_path" \
    || fail 'progress: current_task が無い'
  grep -Eq '^next_action:' "$staged_path" \
    || fail 'progress: next_action が無い'
  grep -Eq '^blocking_issues:[ \t]*(\[\])?[ \t]*$' "$staged_path" \
    || fail 'progress: blocking_issues が無い'
}

# ---------------------------------------------------------------------------
# atomic rename。同一ファイルシステム上の mv はatomicであることを前提とする
# （docs/status/.staging と確定先は同一リポジトリ内）。
# ---------------------------------------------------------------------------

atomic_commit() {
  staged_path=$1
  dest_path=$2

  [ -L "$dest_path" ] && fail "確定先がsymlink: ${dest_path#"$PROJECT_DIR"/}"

  mkdir -p -- "$(dirname -- "$dest_path")"
  mv -f -- "$staged_path" "$dest_path"
}

[ $# -ge 1 ] || usage

case $1 in
  progress)
    [ $# -eq 1 ] || usage
    staged="$STAGING_DIR/progress.yaml"
    dest="$PROJECT_DIR/docs/status/progress.yaml"
    require_staged_file "$staged"
    validate_progress_content "$staged" "$dest"
    atomic_commit "$staged" "$dest"
    printf 'OK progress -> docs/status/progress.yaml\n'
    ;;

  phase-run)
    [ $# -eq 2 ] || usage
    validate_identifier "$2" 'phase-run id'
    staged="$STAGING_DIR/phase-run-$2.yaml"
    dest="$PROJECT_DIR/docs/status/phase-runs/$2.yaml"
    require_staged_file "$staged"
    grep -Eq '^phase_run_id:[ \t]*[^ \t]' "$staged" \
      || fail 'phase-run: phase_run_id が無い'
    atomic_commit "$staged" "$dest"
    printf 'OK phase-run -> docs/status/phase-runs/%s.yaml\n' "$2"
    ;;

  handoff)
    [ $# -eq 3 ] || usage
    validate_identifier "$2" 'feature-id'
    validate_identifier "$3" 'handoff name'
    staged="$STAGING_DIR/handoff-$2-$3.md"
    dest="$PROJECT_DIR/docs/features/$2/handoffs/$3.md"
    require_staged_file "$staged"
    atomic_commit "$staged" "$dest"
    printf 'OK handoff -> docs/features/%s/handoffs/%s.md\n' "$2" "$3"
    ;;

  *)
    usage
    ;;
esac
