#!/bin/bash
#
# templates/hooks/post-tool-use.sh の回帰テスト。
#
# 正本: 設計書 §3.5（Detective / Recovery）, §14
#
# 検出漏れが直接セキュリティ事故になるため、secret scanを重点的に検証する。
# `\y` のようなGNU awk拡張はmacOS標準awkで**黙ってマッチしない**。
# 「拒否されるべきものが素通りする」失敗は出力を見ても気付けないので、
# 代表的な秘密情報の形ごとに検出を確認する。

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK_SRC="$ROOT_DIR/patterns/claude-code-development-harness/templates/hooks/post-tool-use.sh"
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/post-tool-use-hook-test.XXXXXX") || exit 1
PROJECT="$WORK_DIR/project"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$PROJECT/.claude/hooks" "$PROJECT/src" "$PROJECT/docs/status"
cp "$HOOK_SRC" "$PROJECT/.claude/hooks/post-tool-use.sh"
chmod +x "$PROJECT/.claude/hooks/post-tool-use.sh"
printf 'current_task: TASK-004\n' > "$PROJECT/docs/status/progress.yaml"

HOOK="$PROJECT/.claude/hooks/post-tool-use.sh"
FAILURES=0

# $1: ラベル, $2: ファイルへ書く内容, $3: detect | clean
assert_scan() {
  assert_label=$1
  assert_content=$2
  assert_expect=$3

  target="$PROJECT/src/sample.txt"
  printf '%s\n' "$assert_content" > "$target"

  set +e
  printf '{"tool_name":"Write","tool_input":{"file_path":"src/sample.txt"}}' \
    | CLAUDE_PROJECT_DIR="$PROJECT" "$HOOK" > "$WORK_DIR/out" 2>"$WORK_DIR/err"
  hook_exit=$?
  set -e

  if [ "$assert_expect" = 'detect' ]; then
    if [ "$hook_exit" -ne 2 ]; then
      printf 'FAIL: 秘密情報を検出できなかった: %s (exit=%s)\n' "$assert_label" "$hook_exit" >&2
      FAILURES=$((FAILURES + 1))
    fi
  else
    if [ "$hook_exit" -ne 0 ]; then
      printf 'FAIL: 通常の内容を秘密情報と誤検出した: %s (exit=%s)\n' "$assert_label" "$hook_exit" >&2
      sed -n '1,5p' "$WORK_DIR/err" >&2
      FAILURES=$((FAILURES + 1))
    fi
  fi
}

# --- 検出すべきもの -----------------------------------------------------
#
# 以下はいずれも実在しないダミー値である。
#
# 重要: 各トークン形式のケースは、末尾の汎用「ハードコード認証情報」
# パターン（key = "value" の形）に**引っかからない書き方**にする。
# `token: ghp_...` のように書くと汎用側で拾われてしまい、
# 個別パターンを無効化しても検出漏れが表面化せず、テストが空振りする。
# そのため代入形ではなく、裸のトークンを含む行として与える。
#
# さらに、テストデータは**実行時に組み立てる**。値はいずれも実在しない
# ダミーだが、リテラルで書くとGitHubのpush protectionが本物の
# 秘密情報とみなしてpushを拒否する。prefixと本体を分けて連結すれば、
# ソース上に完全な形が現れず、hookへ渡る文字列は同一に保てる。
# 検出能力を落とさずにスキャナとの衝突だけを避けるための措置である。
AWS_PREFIX='AKIA'
GITHUB_PREFIX='ghp'
SLACK_PREFIX='xoxb'
OPENAI_PREFIX='sk'
PEM_HEAD='-----BEGIN'

assert_scan 'AWS access key id' \
  "${AWS_PREFIX}IOSFODNN7EXAMPLE" 'detect'
assert_scan 'GitHub token' \
  "${GITHUB_PREFIX}_0123456789abcdefghijklmnopqrstuvwxyzAB" 'detect'
assert_scan 'Slack token' \
  "${SLACK_PREFIX}-0000000000-abcdefghijklmno" 'detect'
assert_scan 'OpenAI風APIキー' \
  "${OPENAI_PREFIX}-0123456789abcdefghijklmnopqrstuvwxyzABCD" 'detect'
assert_scan 'private key' \
  "${PEM_HEAD} RSA PRIVATE KEY-----" 'detect'

# 汎用パターン自体の検証。こちらは代入形で与える。
assert_scan 'ハードコードされた認証情報' 'password = "hunter2hunter2"' 'detect'
assert_scan 'api_key形式' 'api_key: "abcdefghijklmnop"' 'detect'

# --- 検出すべきでないもの（誤検出は運用を壊す）--------------------------
assert_scan '通常のソースコード' 'public class Order { int total; }' 'clean'
assert_scan '短いプレースホルダ' 'password = ""' 'clean'
assert_scan '環境変数参照' 'password = os.environ["DB_PASSWORD"]' 'clean'

# --- 変更ファイルの記録 -------------------------------------------------
printf 'public class Clean {}\n' > "$PROJECT/src/clean.java"
printf '{"tool_name":"Write","tool_input":{"file_path":"src/clean.java"}}' \
  | CLAUDE_PROJECT_DIR="$PROJECT" "$HOOK" > /dev/null 2>&1 || true

if [ ! -f "$PROJECT/docs/status/changes/TASK-004.touched" ]; then
  printf 'FAIL: 変更ファイルが記録されなかった\n' >&2
  FAILURES=$((FAILURES + 1))
elif ! grep -Fq 'src/clean.java' "$PROJECT/docs/status/changes/TASK-004.touched"; then
  printf 'FAIL: 記録内容に対象ファイルが含まれない\n' >&2
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -ne 0 ]; then
  printf '%s\n' "post-tool-use hook regression test failed: $FAILURES 件" >&2
  exit 1
fi

printf '%s\n' 'post-tool-use hook regression test passed.'
