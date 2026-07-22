#!/bin/bash
#
# templates/scripts/verify-write-scope.sh の回帰テスト。
#
# 正本: 設計書 §3.6.1（Write範囲の解決規則）,
#       templates/rules/permissions.md §2, §3
#
# 検証対象:
#   - 既定deny・最長一致・競合時deny
#   - canonical path正規化（.. traversal / symlink / repo外）
#   - 証跡の追記専用（create-only）
#   - 証跡パスのtaskがprogress.yamlのcurrent_taskと一致すること

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TARGET="$ROOT_DIR/patterns/claude-code-development-harness/templates/scripts/verify-write-scope.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/verify-write-scope-test.XXXXXX") || exit 1
REPO="$WORK_DIR/repo"
POLICY="$WORK_DIR/policy"
OUTPUT_FILE="$WORK_DIR/output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$REPO/src/main/order" "$REPO/src/test/order" \
         "$REPO/docs/status/agent-runs/TASK-004" \
         "$REPO/docs/status/agent-runs/TASK-009" \
         "$REPO/docs/features/order/design" \
         "$REPO/docs/context/manifests" \
         "$REPO/secrets" \
         "$REPO/.claude"

printf 'current_task: TASK-004\n' > "$REPO/docs/status/progress.yaml"
printf 'existing\n' > "$REPO/docs/status/agent-runs/TASK-004/run-001.yaml"
printf 'secret\n' > "$REPO/secrets/token"
printf 'outside\n' > "$WORK_DIR/outside.txt"
ln -s "$WORK_DIR/outside.txt" "$REPO/src/main/order/escape-link.java"

# TDD Generatorの論理Write範囲（permissions.md §3）を、
# 個別pathとcreate-only証跡へ具体化したもの。
cat > "$POLICY" <<'EOF'
# 形式: <mode> <path-pattern>
# mode: allow | allow-create-only | deny
allow             src/main/order/**
allow             src/test/order/**
allow-create-only docs/status/agent-runs/${CURRENT_TASK}/**
deny              src/main/order/generated/**
deny              docs/status/progress.yaml
deny              docs/context/manifests/**
deny              .claude/**
deny              secrets/**
EOF

FAILURES=0

assert_allow() {
  if "$TARGET" --repo "$REPO" --policy "$POLICY" --path "$2" \
    > "$OUTPUT_FILE" 2>&1; then
    return 0
  fi
  printf 'FAIL: 許可されるべき書込みを拒否した: %s\n' "$1" >&2
  sed -n '1,10p' "$OUTPUT_FILE" >&2
  FAILURES=$((FAILURES + 1))
}

assert_deny() {
  assert_label=$1
  assert_path=$2
  assert_reason=${3:-}
  if "$TARGET" --repo "$REPO" --policy "$POLICY" --path "$assert_path" \
    > "$OUTPUT_FILE" 2>&1; then
    printf 'FAIL: 拒否されるべき書込みを許可した: %s\n' "$assert_label" >&2
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  if [ -n "$assert_reason" ] && ! grep -Fq -- "$assert_reason" "$OUTPUT_FILE"; then
    printf 'FAIL: 拒否理由が想定と異なる: %s (期待: %s)\n' "$assert_label" "$assert_reason" >&2
    sed -n '1,10p' "$OUTPUT_FILE" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# --- 許可範囲 -----------------------------------------------------------
assert_allow '対象モジュール' "$REPO/src/main/order/Order.java"
assert_allow 'テストコード' "$REPO/src/test/order/OrderTest.java"
assert_allow '相対パス指定' 'src/main/order/Nested.java'

# --- 既定deny -----------------------------------------------------------
assert_deny '許可されていないモジュール' "$REPO/src/main/payment/Payment.java" 'NOT_IN_WRITE_SCOPE'
assert_deny 'リポジトリ直下の新規ファイル' "$REPO/README.md" 'NOT_IN_WRITE_SCOPE'

# --- 最長一致（most-specific-wins）--------------------------------------
# allow src/main/order/** と deny src/main/order/generated/** が重なる。
# より具体的なdenyが勝つ。
assert_deny '最長一致でdenyが勝つ' "$REPO/src/main/order/generated/Stub.java" 'EXPLICIT_DENY'

# --- 保護パス -----------------------------------------------------------
assert_deny 'progress.yamlはOrchestratorのsingle writer' "$REPO/docs/status/progress.yaml" 'EXPLICIT_DENY'
assert_deny 'context manifestの自己拡張' "$REPO/docs/context/manifests/TASK-004.context.yaml" 'EXPLICIT_DENY'
assert_deny 'Agent定義の自己改変' "$REPO/.claude/agents/tdd-generator.md" 'EXPLICIT_DENY'
assert_deny 'secretsへの書込み' "$REPO/secrets/token" 'EXPLICIT_DENY'

# --- canonical path正規化 -----------------------------------------------
# src/main/order から3階層戻るとrepoルートへ着地する。repo外へは出ないため、
# 期待する拒否理由はNOT_IN_WRITE_SCOPE／EXPLICIT_DENYであってPATH_ESCAPES_REPOではない。
# 要点は「許可範囲内で始まるパスがtraversalで範囲外へ抜けられないこと」である。
assert_deny 'traversalで許可範囲外へ抜ける' "$REPO/src/main/order/../../../etc/passwd" 'NOT_IN_WRITE_SCOPE'
assert_deny 'traversalで保護パスへ到達する' "$REPO/src/main/order/../../../secrets/token" 'EXPLICIT_DENY'

# repoルートより上へ抜けるtraversalはPATH_ESCAPES_REPOとする
assert_deny 'traversalでrepo外へ抜ける' "$REPO/src/main/order/../../../../outside.txt" 'PATH_ESCAPES_REPO'
assert_deny 'symlink経由の書込み' "$REPO/src/main/order/escape-link.java" 'SYMLINK_REJECTED'
assert_deny 'リポジトリ外の絶対パス' "$WORK_DIR/outside.txt" 'PATH_ESCAPES_REPO'

# --- 証跡はcreate-only（permissions.md §2）-------------------------------
assert_allow '証跡の新規作成' "$REPO/docs/status/agent-runs/TASK-004/run-002.yaml"
assert_deny '既存証跡の上書き' "$REPO/docs/status/agent-runs/TASK-004/run-001.yaml" 'CREATE_ONLY_VIOLATION'

# --- 証跡のtaskはcurrent_taskと一致すること ------------------------------
assert_deny '他taskの証跡ディレクトリ' "$REPO/docs/status/agent-runs/TASK-009/run-001.yaml" 'NOT_IN_WRITE_SCOPE'

if [ "$FAILURES" -ne 0 ]; then
  printf '%s\n' "verify-write-scope regression test failed: $FAILURES 件" >&2
  exit 1
fi

printf '%s\n' 'verify-write-scope regression test passed.'
