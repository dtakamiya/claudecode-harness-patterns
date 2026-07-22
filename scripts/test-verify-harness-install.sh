#!/bin/bash
#
# templates/scripts/verify-harness-install.sh の回帰テスト。
#
# 正本: 設計書 §3.5, §3.5.1, §3.6.1, §3.6.2, §14.1
#
# 検証対象は「導入先がfail-closed条件を満たしているかを診断できること」である。
# pre-tool-use.sh の各deny経路に1:1で対応した検査が、実際にその欠落を
# 検知することを確認する。検査が実質何も見ていない状態を防ぐため、
# 正常系だけでなく個別の欠落ごとにnegative caseを置く。
#
# 特に重要な2件:
#   - verify-redirect-target.sh の欠落（pre-tool-use.sh のガード対象外であり、
#     リダイレクトを含むコマンドで初めて失敗する）
#   - bash-allowlist が全行コメント（-f を通過しつつ全コマンドが拒否され、
#     症状が「hook未設置」と区別できない）

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATES="$ROOT_DIR/patterns/claude-code-development-harness/templates"
TARGET="$TEMPLATES/scripts/verify-harness-install.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/verify-harness-install-test.XXXXXX") || exit 1
OUTPUT_FILE="$WORK_DIR/output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

FAILURES=0

# ---------------------------------------------------------------------------
# fixture: 完全に正しい導入先を作る
#
# 各テストはこれを新しいディレクトリへ複製し、1箇所だけ壊して検証する。
# 「正しい状態」を1箇所で定義することで、テストが古い前提のまま
# 緑になり続けることを防ぐ。
# ---------------------------------------------------------------------------
make_good_install() {
  make_dir=$1
  mkdir -p "$make_dir/.claude/hooks" "$make_dir/scripts"

  cp "$TEMPLATES/hooks/pre-tool-use.sh" \
     "$TEMPLATES/hooks/post-tool-use.sh" \
     "$TEMPLATES/hooks/subagent-stop.sh" \
     "$TEMPLATES/hooks/stop-gate.sh" "$make_dir/.claude/hooks/"
  cp "$TEMPLATES/scripts/verify-bash-command.sh" \
     "$TEMPLATES/scripts/verify-redirect-target.sh" \
     "$TEMPLATES/scripts/verify-write-scope.sh" "$make_dir/scripts/"
  cp "$TEMPLATES/settings.json" "$make_dir/.claude/settings.json"
  cp "$TEMPLATES/write-scope-policy" "$make_dir/.claude/write-scope-policy"

  chmod +x "$make_dir/.claude/hooks/"*.sh "$make_dir/scripts/"*.sh

  # 雛形のwrite-scope-policyはプレースホルダを含むため、
  # 「正しい導入先」では実プロジェクト相当へ置き換えておく。
  cat > "$make_dir/.claude/write-scope-policy" <<'EOF'
allow src/main/order/**
deny  .claude/**
EOF

  # 雛形のbash-allowlistは全行コメントのため、
  # 「正しい導入先」では実コマンドを入れておく。
  cat > "$make_dir/.claude/bash-allowlist" <<'EOF'
npm
./gradlew
EOF
}

# 使い捨ての導入先を作り、パスを返す
new_install() {
  new_name=$1
  new_dir="$WORK_DIR/$new_name"
  rm -rf -- "$new_dir"
  make_good_install "$new_dir"
  printf '%s' "$new_dir"
}

run_verify() {
  "$TARGET" --target "$1" > "$OUTPUT_FILE" 2>&1
}

# 期待: 検証が失敗し、理由に needle が現れる
#
# 終了コードだけを見ると、別の理由でたまたま失敗した場合を
# 「正しく検知した」と誤認するため、必ず理由文字列まで照合する。
assert_detects() {
  assert_label=$1
  assert_dir=$2
  assert_needle=$3
  if run_verify "$assert_dir"; then
    printf 'FAIL: 欠落を検知しなかった: %s\n' "$assert_label" >&2
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  if ! grep -q -- "$assert_needle" "$OUTPUT_FILE"; then
    printf 'FAIL: 検知したが理由が該当ファイルを名指ししない: %s (期待: %s)\n' \
      "$assert_label" "$assert_needle" >&2
    sed -n '1,20p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# 期待: 検証が成功する（exit 0）
assert_passes() {
  assert_label=$1
  assert_dir=$2
  if run_verify "$assert_dir"; then
    return 0
  fi
  printf 'FAIL: 正常な導入先を失敗と判定した: %s\n' "$assert_label" >&2
  sed -n '1,30p' "$OUTPUT_FILE" >&2
  FAILURES=$((FAILURES + 1))
}

# 期待: exit 0 だが、警告として needle を報告する
assert_warns() {
  assert_label=$1
  assert_dir=$2
  assert_needle=$3
  if ! run_verify "$assert_dir"; then
    printf 'FAIL: WARN扱いのはずがハード失敗した: %s\n' "$assert_label" >&2
    sed -n '1,20p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  if ! grep -q -- "$assert_needle" "$OUTPUT_FILE"; then
    printf 'FAIL: 警告が報告されなかった: %s (期待: %s)\n' \
      "$assert_label" "$assert_needle" >&2
    sed -n '1,20p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# 正常系
# ---------------------------------------------------------------------------

DIR=$(new_install good)
assert_passes '完全な導入先' "$DIR"

# ---------------------------------------------------------------------------
# scripts/ の欠落と実行権限（Bash・Write全denyの直接原因）
# ---------------------------------------------------------------------------

DIR=$(new_install missing-bash-verifier)
rm -f "$DIR/scripts/verify-bash-command.sh"
assert_detects 'verify-bash-command.sh の欠落' "$DIR" 'verify-bash-command.sh'

DIR=$(new_install nonexec-bash-verifier)
chmod -x "$DIR/scripts/verify-bash-command.sh"
assert_detects 'verify-bash-command.sh の実行権限なし' "$DIR" 'verify-bash-command.sh'

DIR=$(new_install missing-write-verifier)
rm -f "$DIR/scripts/verify-write-scope.sh"
assert_detects 'verify-write-scope.sh の欠落' "$DIR" 'verify-write-scope.sh'

# pre-tool-use.sh がガードしていない依存。
# これを検知できることが、この検証器を追加する主目的のひとつである。
DIR=$(new_install missing-redirect-verifier)
rm -f "$DIR/scripts/verify-redirect-target.sh"
assert_detects 'verify-redirect-target.sh の欠落（未ガード依存）' \
  "$DIR" 'verify-redirect-target.sh'

DIR=$(new_install nonexec-redirect-verifier)
chmod -x "$DIR/scripts/verify-redirect-target.sh"
assert_detects 'verify-redirect-target.sh の実行権限なし' \
  "$DIR" 'verify-redirect-target.sh'

# ---------------------------------------------------------------------------
# .claude/ 配下の設定ファイル
# ---------------------------------------------------------------------------

DIR=$(new_install missing-allowlist)
rm -f "$DIR/.claude/bash-allowlist"
assert_detects 'bash-allowlist の欠落' "$DIR" 'bash-allowlist'

DIR=$(new_install missing-policy)
rm -f "$DIR/.claude/write-scope-policy"
assert_detects 'write-scope-policy の欠落' "$DIR" 'write-scope-policy'

# ---------------------------------------------------------------------------
# hooks の欠落・実行権限
# ---------------------------------------------------------------------------

DIR=$(new_install missing-hook)
rm -f "$DIR/.claude/hooks/pre-tool-use.sh"
assert_detects 'pre-tool-use.sh の欠落' "$DIR" 'pre-tool-use.sh'

DIR=$(new_install nonexec-hook)
chmod -x "$DIR/.claude/hooks/pre-tool-use.sh"
assert_detects 'pre-tool-use.sh の実行権限なし' "$DIR" 'pre-tool-use.sh'

DIR=$(new_install missing-stop-gate)
rm -f "$DIR/.claude/hooks/stop-gate.sh"
assert_detects 'stop-gate.sh の欠落' "$DIR" 'stop-gate.sh'

# ---------------------------------------------------------------------------
# 雛形のまま運用（WARN。ハード失敗にはしない）
#
# §16-2 の監査前は正当な中間状態でありうるため exit 0 とするが、
# 名指しで報告しなければ「hook未設置」と症状が区別できない。
# ---------------------------------------------------------------------------

DIR=$(new_install template-allowlist)
cp "$TEMPLATES/bash-allowlist" "$DIR/.claude/bash-allowlist"
assert_warns '全行コメントのbash-allowlist' "$DIR" 'bash-allowlist'

DIR=$(new_install template-policy)
cp "$TEMPLATES/write-scope-policy" "$DIR/.claude/write-scope-policy"
assert_warns 'プレースホルダが残るwrite-scope-policy' "$DIR" 'write-scope-policy'

# ---------------------------------------------------------------------------
# 疎通スモークテスト（変異テスト）
#
# 個々のファイルが揃っていても配線が壊れていることはある。
# hookを常時denyへ改変し、検証器がそれを検知することを確認する。
# これが赤にならない場合、スモークテストは実質何も見ていない。
# ---------------------------------------------------------------------------

DIR=$(new_install broken-hook)
cat > "$DIR/.claude/hooks/pre-tool-use.sh" <<'EOF'
#!/bin/bash
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"mutation"}}\n'
EOF
chmod +x "$DIR/.claude/hooks/pre-tool-use.sh"
assert_detects '許可されるべきコマンドをdenyするhook（変異）' "$DIR" 'deny'

# ---------------------------------------------------------------------------
# 引数の扱い
# ---------------------------------------------------------------------------

if "$TARGET" --target "$WORK_DIR/does-not-exist" > "$OUTPUT_FILE" 2>&1; then
  printf 'FAIL: 存在しないtargetを成功と判定した\n' >&2
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -ne 0 ]; then
  printf '\n%d件失敗\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok\n'
