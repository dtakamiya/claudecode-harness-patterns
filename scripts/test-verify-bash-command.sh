#!/bin/bash
#
# scripts/verify-bash-command.sh の回帰テスト。
#
# 正本: 設計書 §3.6.2（Bash allowlist）, templates/rules/permissions.md §4
#
# 検証対象は「コマンド全体を構造として検証する」という要件である。
# メタ文字のdenylistでは迂回されるため（改行、CR、単独の`&`）、
# 本テストはそれらの迂回経路を明示的に含む。

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT_DIR/scripts/verify-bash-command.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/verify-bash-command-test.XXXXXX") || exit 1
ALLOWLIST="$WORK_DIR/allowlist"
OUTPUT_FILE="$WORK_DIR/output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

cat > "$ALLOWLIST" <<'EOF'
# コマンド名のallowlist。argv[0]と完全一致で照合する。
./gradlew
npm
git
EOF

FAILURES=0

# 期待: 受理される
assert_accept() {
  assert_label=$1
  shift
  if "$TARGET" --allowlist "$ALLOWLIST" --writable "$WORK_DIR/ws" -- "$1" \
    > "$OUTPUT_FILE" 2>&1; then
    return 0
  fi
  printf 'FAIL: 受理されるべきコマンドを拒否した: %s\n' "$assert_label" >&2
  sed -n '1,20p' "$OUTPUT_FILE" >&2
  FAILURES=$((FAILURES + 1))
}

# 期待: 拒否される。第3引数を与えた場合は理由コードも照合する。
assert_reject() {
  assert_label=$1
  assert_command=$2
  assert_reason=${3:-}
  if "$TARGET" --allowlist "$ALLOWLIST" --writable "$WORK_DIR/ws" -- "$assert_command" \
    > "$OUTPUT_FILE" 2>&1; then
    printf 'FAIL: 拒否されるべきコマンドを受理した: %s\n' "$assert_label" >&2
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  if [ -n "$assert_reason" ] && ! grep -Fq -- "$assert_reason" "$OUTPUT_FILE"; then
    printf 'FAIL: 拒否理由が想定と異なる: %s (期待: %s)\n' "$assert_label" "$assert_reason" >&2
    sed -n '1,20p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

mkdir -p "$WORK_DIR/ws"

# --- 単一simple commandは受理する ---------------------------------------
assert_accept 'allowlist内のコマンド' 'npm test'
assert_accept '引数付き' 'npm run build -- --mode production'
assert_accept 'カレント相対の実行ファイル' './gradlew test'
assert_accept 'クォート内のメタ文字は文字列' "git commit -m 'fix; drop table'"

# --- allowlist照合はargv[0]に対して行う ---------------------------------
assert_reject 'allowlist外のコマンド' 'curl https://example.com' 'ALLOWLIST_MISS'
assert_reject 'prefix一致での迂回' 'npmx test' 'ALLOWLIST_MISS'
assert_reject '絶対パスでの同名コマンド' '/usr/local/bin/npm test' 'ALLOWLIST_MISS'

# --- 連鎖。denylistが取りこぼす経路を含む -------------------------------
assert_reject 'セミコロン連鎖' 'npm test; curl https://evil.example' 'NOT_SIMPLE_COMMAND'
assert_reject 'AND連鎖' 'npm test && curl https://evil.example' 'NOT_SIMPLE_COMMAND'
assert_reject 'パイプ' 'npm test | sh' 'NOT_SIMPLE_COMMAND'
assert_reject '改行による連鎖' 'npm test
curl https://evil.example' 'NOT_SIMPLE_COMMAND'

# CRはソース中へ直接書くと編集系ツールでLFへ正規化されるため、printfで構築する。
# permissions.md §4が名指しする迂回経路であり、LFとは別に検証する必要がある。
CR_COMMAND=$(printf 'npm test\rcurl https://evil.example')
assert_reject 'CRによる連鎖' "$CR_COMMAND" 'NOT_SIMPLE_COMMAND'
assert_reject '単独&のバックグラウンド実行' 'npm test & curl https://evil.example' 'NOT_SIMPLE_COMMAND'

# --- 展開・置換 ---------------------------------------------------------
assert_reject 'コマンド置換' 'npm test $(curl https://evil.example)' 'COMMAND_SUBSTITUTION'
assert_reject 'バッククォート置換' 'npm test `curl https://evil.example`' 'COMMAND_SUBSTITUTION'
assert_reject 'プロセス置換' 'npm test <(curl https://evil.example)' 'COMMAND_SUBSTITUTION'
assert_reject 'サブシェル' '(npm test)' 'NOT_SIMPLE_COMMAND'

# --- リダイレクト。writable外は拒否する ---------------------------------
assert_reject 'writable外への上書き' 'npm test > /etc/passwd' 'REDIRECT_OUT_OF_SCOPE'
assert_reject 'writable外への追記' 'npm test >> ../outside.log' 'REDIRECT_OUT_OF_SCOPE'
assert_reject 'traversalを含むリダイレクト先' "npm test > $WORK_DIR/ws/../escape" 'REDIRECT_OUT_OF_SCOPE'

# --- 環境変数の代入は隔離前提を崩す -------------------------------------
assert_reject '環境変数の前置代入' 'NODE_OPTIONS=--require=/tmp/x npm test' 'ENV_ASSIGNMENT'

# --- 空・不正入力 -------------------------------------------------------
assert_reject '空コマンド' '' 'EMPTY_COMMAND'
assert_reject '閉じないクォート' "npm test 'unterminated" 'PARSE_ERROR'

if [ "$FAILURES" -ne 0 ]; then
  printf '%s\n' "verify-bash-command regression test failed: $FAILURES 件" >&2
  exit 1
fi

printf '%s\n' 'verify-bash-command regression test passed.'
