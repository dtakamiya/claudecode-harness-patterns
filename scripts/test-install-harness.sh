#!/bin/bash
#
# templates/scripts/install-harness.sh の回帰テスト。
#
# 正本: 設計書 §3.5, §3.5.1, §3.6.1, §3.6.2, §14.1
#
# 検証対象は「導入漏れを構造的に起こせないこと」である。
#   - コピー漏れが無いこと（特にネストした skills/**）
#   - chmod +x が必ず付くこと、落ちていたら修復されること
#   - 再実行が冪等であること（アップグレード経路として使えること）
#   - カスタマイズ済みの設定を壊さないこと
#
# 最後の2点は互いに緊張関係にある。ロジック（hooks, verify-*.sh）は
# 上書きし、利用者所有の設定（allowlist, policy, settings.json）は
# 保護する、という分類が正しく効いているかを確認する。

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATES="$ROOT_DIR/patterns/claude-code-development-harness/templates"
TARGET="$TEMPLATES/scripts/install-harness.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/install-harness-test.XXXXXX") || exit 1
OUTPUT_FILE="$WORK_DIR/output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

FAILURES=0

# 使い捨ての導入先ディレクトリを作る（空＝新規プロジェクト相当）
new_target() {
  new_dir="$WORK_DIR/$1"
  rm -rf -- "$new_dir"
  mkdir -p "$new_dir"
  printf '%s' "$new_dir"
}

run_install() {
  "$TARGET" --target "$1" > "$OUTPUT_FILE" 2>&1
}

assert_installed() {
  if [ ! -f "$2/$3" ]; then
    printf 'FAIL: 導入されていない: %s (%s)\n' "$3" "$1" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_executable() {
  if [ ! -x "$2/$3" ]; then
    printf 'FAIL: 実行権限が無い: %s (%s)\n' "$3" "$1" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_content_equals() {
  if ! printf '%s' "$3" | cmp -s - "$2"; then
    printf 'FAIL: 内容が保存されていない: %s\n' "$1" >&2
    printf '  実際: %s\n' "$(cat "$2")" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_output_contains() {
  if ! grep -q -- "$2" "$OUTPUT_FILE"; then
    printf 'FAIL: 出力に %s が現れない (%s)\n' "$2" "$1" >&2
    sed -n '1,30p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_output_lacks() {
  if grep -q -- "$2" "$OUTPUT_FILE"; then
    printf 'FAIL: 出力に %s が現れてはいけない (%s)\n' "$2" "$1" >&2
    sed -n '1,30p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# 新規導入
# ---------------------------------------------------------------------------

DIR=$(new_target fresh)
if ! run_install "$DIR"; then
  printf 'FAIL: 新規導入が失敗した\n' >&2
  sed -n '1,40p' "$OUTPUT_FILE" >&2
  FAILURES=$((FAILURES + 1))
fi

for f in pre-tool-use.sh post-tool-use.sh subagent-stop.sh stop-gate.sh; do
  assert_installed '新規導入' "$DIR" ".claude/hooks/$f"
  assert_executable '新規導入' "$DIR" ".claude/hooks/$f"
done

# scripts/ はプロジェクトルート直下。.claude/scripts/ ではない。
# ここを取り違えるとBash・Write・Editが全てdenyされる。
for f in verify-bash-command.sh verify-redirect-target.sh verify-write-scope.sh; do
  assert_installed '新規導入' "$DIR" "scripts/$f"
  assert_executable '新規導入' "$DIR" "scripts/$f"
done

assert_installed '新規導入' "$DIR" '.claude/settings.json'
assert_installed '新規導入' "$DIR" '.claude/bash-allowlist'
assert_installed '新規導入' "$DIR" '.claude/write-scope-policy'

# ネストしたテンプレート。フラットな cp * では取りこぼす。
assert_installed 'ネスト' "$DIR" '.claude/skills/harness-orchestration/SKILL.md'
assert_installed 'ネスト' "$DIR" '.claude/skills/harness-orchestration/references/state-restore.md'
assert_installed 'ネスト' "$DIR" '.claude/skills/tdd-development/references/unit-test-policy.md'
assert_installed 'ネスト' "$DIR" '.claude/skills/tdd-development/agents/openai.yaml'

# ディレクトリツリー
assert_installed 'ツリー' "$DIR" '.claude/workflows/00-initialization.md'
assert_installed 'ツリー' "$DIR" '.claude/rules/permissions.md'

# 導入直後は検証器が緑になること（installer自身が最終段で呼ぶ）
assert_output_contains '新規導入' 'ok'

# ---------------------------------------------------------------------------
# 冪等性
#
# 2回目は何も変更せず、CREATE/UPDATE を出力しないこと。
# 「効果として冪等」だけでなく「出力としても静か」であることを求める。
# 毎回差分が出ると、利用者は出力を読まなくなる。
# ---------------------------------------------------------------------------

BEFORE="$WORK_DIR/before-tree"
AFTER="$WORK_DIR/after-tree"
(cd "$DIR" && find . -type f | sort | xargs shasum) > "$BEFORE" 2>/dev/null

if ! run_install "$DIR"; then
  printf 'FAIL: 再実行が失敗した\n' >&2
  sed -n '1,40p' "$OUTPUT_FILE" >&2
  FAILURES=$((FAILURES + 1))
fi

(cd "$DIR" && find . -type f | sort | xargs shasum) > "$AFTER" 2>/dev/null
if ! cmp -s "$BEFORE" "$AFTER"; then
  printf 'FAIL: 再実行でツリーが変化した\n' >&2
  diff "$BEFORE" "$AFTER" >&2 || true
  FAILURES=$((FAILURES + 1))
fi

# 個々の操作行のみを見る。集計行（"CREATE 0件 / UPDATE 0件 / SKIP 0件"）は
# 常に出力され行頭も CREATE のため、行頭一致でも判定にならない。
# 操作行は必ずパスを伴うので、末尾の .sh / .md / .json / .yaml で識別する。
assert_output_lacks '再実行' '^CREATE .*\.\(sh\|md\|json\|yaml\)$'
assert_output_lacks '再実行' '^UPDATE .*\.\(sh\|md\|json\|yaml\)$'

# ---------------------------------------------------------------------------
# カスタマイズ済み設定の保護（Policy B）
# ---------------------------------------------------------------------------

DIR=$(new_target customized)
run_install "$DIR" || true

CUSTOM_ALLOWLIST='./gradlew
git
'
printf '%s' "$CUSTOM_ALLOWLIST" > "$DIR/.claude/bash-allowlist"

CUSTOM_POLICY='allow src/main/kotlin/**
deny  .claude/**
'
printf '%s' "$CUSTOM_POLICY" > "$DIR/.claude/write-scope-policy"

CUSTOM_SETTINGS='{"note":"customized by operator"}'
printf '%s' "$CUSTOM_SETTINGS" > "$DIR/.claude/settings.json"

run_install "$DIR" || true

assert_content_equals 'bash-allowlist が保護される' \
  "$DIR/.claude/bash-allowlist" "$CUSTOM_ALLOWLIST"
assert_content_equals 'write-scope-policy が保護される' \
  "$DIR/.claude/write-scope-policy" "$CUSTOM_POLICY"
assert_content_equals 'settings.json が保護される' \
  "$DIR/.claude/settings.json" "$CUSTOM_SETTINGS"
assert_output_contains 'カスタマイズ済み' 'SKIP'

# ---------------------------------------------------------------------------
# 修復（今回の障害の直接の再発防止）
# ---------------------------------------------------------------------------

DIR=$(new_target repair)
run_install "$DIR" || true

# 実行ビットが落ちた場合。chmodはコピー有無に条件づけてはならない。
chmod -x "$DIR/scripts/verify-bash-command.sh"
run_install "$DIR" || true
assert_executable '実行ビットの修復' "$DIR" 'scripts/verify-bash-command.sh'

# scriptが削除された場合
rm -f "$DIR/scripts/verify-write-scope.sh"
run_install "$DIR" || true
assert_installed 'script の復元' "$DIR" 'scripts/verify-write-scope.sh'
assert_executable 'script の復元' "$DIR" 'scripts/verify-write-scope.sh'

# 未ガード依存も同様に復元されること
rm -f "$DIR/scripts/verify-redirect-target.sh"
run_install "$DIR" || true
assert_installed 'redirect verifier の復元' "$DIR" 'scripts/verify-redirect-target.sh'

# hookが改変された場合は上書きする（Policy A）。
# ロジックにカスタマイズ余地を認めると、アップグレードができなくなる。
printf '\n# tampered\n' >> "$DIR/.claude/hooks/pre-tool-use.sh"
run_install "$DIR" || true
if ! cmp -s "$DIR/.claude/hooks/pre-tool-use.sh" "$TEMPLATES/hooks/pre-tool-use.sh"; then
  printf 'FAIL: 改変されたhookが雛形へ戻されていない\n' >&2
  FAILURES=$((FAILURES + 1))
fi

# ---------------------------------------------------------------------------
# --dry-run は何も書かない
# ---------------------------------------------------------------------------

DIR=$(new_target dryrun)
if ! "$TARGET" --target "$DIR" --dry-run > "$OUTPUT_FILE" 2>&1; then
  printf 'FAIL: --dry-run が失敗した\n' >&2
  sed -n '1,30p' "$OUTPUT_FILE" >&2
  FAILURES=$((FAILURES + 1))
fi

REMAINING=$(find "$DIR" -type f | wc -l | tr -d ' ')
if [ "$REMAINING" != '0' ]; then
  printf 'FAIL: --dry-run がファイルを作成した (%s件)\n' "$REMAINING" >&2
  FAILURES=$((FAILURES + 1))
fi
assert_output_contains '--dry-run' 'CREATE'

# ---------------------------------------------------------------------------
# 引数の扱い
# ---------------------------------------------------------------------------

# 存在しないtargetは作らない。打ち間違いで新しい木を作らせない。
MISSING="$WORK_DIR/does-not-exist"
if "$TARGET" --target "$MISSING" > "$OUTPUT_FILE" 2>&1; then
  printf 'FAIL: 存在しないtargetを成功と判定した\n' >&2
  FAILURES=$((FAILURES + 1))
fi
if [ -e "$MISSING" ]; then
  printf 'FAIL: 存在しないtargetを作成してしまった\n' >&2
  FAILURES=$((FAILURES + 1))
fi

# テンプレート自身へ導入すると、配布元を自分で上書きし得る
if "$TARGET" --target "$TEMPLATES" > "$OUTPUT_FILE" 2>&1; then
  printf 'FAIL: 自己導入を拒否しなかった\n' >&2
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -ne 0 ]; then
  printf '\n%d件失敗\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok\n'
