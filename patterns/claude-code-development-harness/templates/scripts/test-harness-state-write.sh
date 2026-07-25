#!/bin/bash
#
# harness-state-write.sh の回帰テスト。
#
# 配布元: このパターンリポジトリの templates/scripts/。
# 利用者リポジトリの scripts/ へコピーして使う（他の配布スクリプトと同様）。
#
# 正本: 実装計画 quizzical-munching-origami §1
#
# 検証対象:
#   - revision不整合（expected_previous_revisionの不一致、revisionが+1でない）の拒否
#   - パス脱出（識別子への `..` や `/`）の拒否
#   - symlink（staging側・確定先側）の拒否
#   - gate-runsを確定先に指定できないこと
#   - 正常系のatomic rename

set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TARGET="$SELF_DIR/harness-state-write.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/harness-state-write-test.XXXXXX") || exit 1

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

new_project() {
  proj="$WORK_DIR/$1"
  rm -rf -- "$proj"
  mkdir -p "$proj/docs/status/.staging" "$proj/docs/status/phase-runs" \
    "$proj/docs/status/gate-runs" "$proj/docs/features"
  printf '%s' "$proj"
}

run_state_write() {
  # $1: project dir, 残りはharness-state-write.shへの引数
  proj=$1
  shift
  CLAUDE_PROJECT_DIR="$proj" "$TARGET" "$@" > "$WORK_DIR/out" 2>"$WORK_DIR/err"
}

# ---------------------------------------------------------------------------
# 正常系: 初回のprogress確定
# ---------------------------------------------------------------------------

PROJ=$(new_project ok-first)
cat > "$PROJ/docs/status/.staging/progress.yaml" <<'EOF'
revision: 1
expected_previous_revision: 0
current_task: PHASE-0
next_action: "start"
blocking_issues: []
EOF

if ! run_state_write "$PROJ" progress; then
  fail "正常系(初回): progress確定が失敗した: $(cat "$WORK_DIR/err")"
fi
[ -f "$PROJ/docs/status/progress.yaml" ] || fail '正常系(初回): 確定先にファイルが無い'
[ -f "$PROJ/docs/status/.staging/progress.yaml" ] && fail '正常系(初回): ステージング側が残っている（atomic renameされていない）'

# ---------------------------------------------------------------------------
# 正常系: revision+1での再確定
# ---------------------------------------------------------------------------

cat > "$PROJ/docs/status/.staging/progress.yaml" <<'EOF'
revision: 2
expected_previous_revision: 1
current_task: PHASE-1
next_action: "continue"
blocking_issues: []
EOF

if ! run_state_write "$PROJ" progress; then
  fail "正常系(再確定): progress確定が失敗した: $(cat "$WORK_DIR/err")"
fi
grep -q '^revision: 2$' "$PROJ/docs/status/progress.yaml" \
  || fail '正常系(再確定): revisionが更新されていない'

# ---------------------------------------------------------------------------
# revision不整合: expected_previous_revisionが既存revisionと一致しない
# ---------------------------------------------------------------------------

cat > "$PROJ/docs/status/.staging/progress.yaml" <<'EOF'
revision: 3
expected_previous_revision: 999
current_task: PHASE-1
next_action: "continue"
blocking_issues: []
EOF

if run_state_write "$PROJ" progress; then
  fail 'revision不整合: expected_previous_revisionの不一致を拒否しなかった'
fi
[ -f "$PROJ/docs/status/.staging/progress.yaml" ] \
  || fail 'revision不整合: 拒否時にステージングのファイルが消えている（fail-closedでは残すべき）'
rm -f "$PROJ/docs/status/.staging/progress.yaml"

# ---------------------------------------------------------------------------
# revision不整合: revisionが+1でない（スキップ）
# ---------------------------------------------------------------------------

cat > "$PROJ/docs/status/.staging/progress.yaml" <<'EOF'
revision: 5
expected_previous_revision: 2
current_task: PHASE-1
next_action: "continue"
blocking_issues: []
EOF

if run_state_write "$PROJ" progress; then
  fail 'revision不整合: revisionの飛び越しを拒否しなかった'
fi
rm -f "$PROJ/docs/status/.staging/progress.yaml"

# ---------------------------------------------------------------------------
# 必須フィールド欠如
# ---------------------------------------------------------------------------

cat > "$PROJ/docs/status/.staging/progress.yaml" <<'EOF'
revision: 3
expected_previous_revision: 2
next_action: "continue"
blocking_issues: []
EOF

if run_state_write "$PROJ" progress; then
  fail 'current_task欠如を拒否しなかった'
fi
rm -f "$PROJ/docs/status/.staging/progress.yaml"

# ---------------------------------------------------------------------------
# パス脱出: 識別子に `..` や `/` を含む
# ---------------------------------------------------------------------------

PROJ2=$(new_project path-escape)
cat > "$PROJ2/docs/status/.staging/phase-run-x.yaml" <<'EOF'
phase_run_id: x
EOF

if run_state_write "$PROJ2" phase-run '../../etc/passwd'; then
  fail 'パス脱出(phase-run): `..`を含む識別子を拒否しなかった'
fi

if run_state_write "$PROJ2" handoff '../escape' 'name'; then
  fail 'パス脱出(handoff feature-id): `..`を含む識別子を拒否しなかった'
fi

if run_state_write "$PROJ2" handoff 'feature' 'a/../../b'; then
  fail 'パス脱出(handoff name): `/`を含む識別子を拒否しなかった'
fi

# ---------------------------------------------------------------------------
# symlink拒否: ステージング側がsymlink
# ---------------------------------------------------------------------------

PROJ3=$(new_project symlink-staging)
printf 'outside\n' > "$WORK_DIR/outside-progress.yaml"
ln -s "$WORK_DIR/outside-progress.yaml" "$PROJ3/docs/status/.staging/progress.yaml"

if run_state_write "$PROJ3" progress; then
  fail 'symlink(ステージング): symlinkを拒否しなかった'
fi

# ---------------------------------------------------------------------------
# symlink拒否: 確定先がsymlink
# ---------------------------------------------------------------------------

PROJ4=$(new_project symlink-dest)
printf 'outside\n' > "$WORK_DIR/outside-target.yaml"
ln -s "$WORK_DIR/outside-target.yaml" "$PROJ4/docs/status/progress.yaml"
cat > "$PROJ4/docs/status/.staging/progress.yaml" <<'EOF'
revision: 1
expected_previous_revision: 0
current_task: PHASE-0
next_action: "start"
blocking_issues: []
EOF

if run_state_write "$PROJ4" progress; then
  fail 'symlink(確定先): 確定先symlinkを拒否しなかった'
fi

# ---------------------------------------------------------------------------
# gate-runsを確定先に指定できないこと
#
# gate-run / phase-run / handoff の3サブコマンドしか存在せず、
# gate-runsへ書くサブコマンド自体が無いことを確認する。
# ---------------------------------------------------------------------------

PROJ5=$(new_project no-gate-runs)
if run_state_write "$PROJ5" gate-run 'x'; then
  fail 'gate-runs: 未知のサブコマンドgate-runを受理してしまった（確定先に含めてはならない）'
fi

# ---------------------------------------------------------------------------
# 正常系: phase-run
# ---------------------------------------------------------------------------

PROJ6=$(new_project ok-phase-run)
cat > "$PROJ6/docs/status/.staging/phase-run-abc.yaml" <<'EOF'
phase_run_id: abc
status: ready
EOF

if ! run_state_write "$PROJ6" phase-run abc; then
  fail "正常系(phase-run): 確定が失敗した: $(cat "$WORK_DIR/err")"
fi
[ -f "$PROJ6/docs/status/phase-runs/abc.yaml" ] || fail '正常系(phase-run): 確定先にファイルが無い'

# ---------------------------------------------------------------------------
# 正常系: handoff
# ---------------------------------------------------------------------------

PROJ7=$(new_project ok-handoff)
mkdir -p "$PROJ7/docs/status/.staging"
cat > "$PROJ7/docs/status/.staging/handoff-feat-note.md" <<'EOF'
# handoff note
EOF

if ! run_state_write "$PROJ7" handoff feat note; then
  fail "正常系(handoff): 確定が失敗した: $(cat "$WORK_DIR/err")"
fi
[ -f "$PROJ7/docs/features/feat/handoffs/note.md" ] || fail '正常系(handoff): 確定先にファイルが無い'

if [ "$FAILURES" -ne 0 ]; then
  printf '\n%d件失敗\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok\n'
