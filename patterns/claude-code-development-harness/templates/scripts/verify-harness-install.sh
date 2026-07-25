#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書 Version 1.11
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# 配布元: このパターンリポジトリの templates/scripts/。
# 利用者リポジトリの scripts/ へコピーして使う。
#
# 正本: 設計書 §3.5, §3.5.1, §3.6.1, §3.6.2, §14.1
#
# ---------------------------------------------------------------------------
# ハーネス導入先が fail-closed 条件を満たしているかを診断する。
#
# hooks は fail-closed 設計であり、設定漏れは「制限なし」ではなく「全拒否」に
# なる。そのため症状は常に「Bashが全部denyされる」であり、原因が
#   - verify-*.sh の未配置
#   - 実行ビットの欠落
#   - allowlistが雛形のまま（全行コメント＝全コマンド拒否）
# のいずれであっても区別がつかない。このスクリプトはその区別をつける。
#
# 使用法:
#   verify-harness-install.sh [--target <dir>]
#
# 終了コード:
#   0  必須条件を満たす（WARNのみの場合を含む）
#   1  使用法の誤り、または target が存在しない
#   2  必須条件を満たさない（FAILあり）
#
# 最初の失敗で止めず全件report する。3件欠けている利用者が、
# 3回実行し直さずに全体像を得られるようにするため。
# ---------------------------------------------------------------------------

set -eu

TARGET_DIR=${PWD}

while [ $# -gt 0 ]; do
  case $1 in
    --target)
      [ $# -ge 2 ] || { printf 'usage: %s [--target <dir>]\n' "$0" >&2; exit 1; }
      TARGET_DIR=$2
      shift 2
      ;;
    -h|--help)
      printf 'usage: %s [--target <dir>]\n' "$0"
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$TARGET_DIR" ]; then
  printf 'FAIL: 導入先が存在しない: %s\n' "$TARGET_DIR" >&2
  exit 1
fi

TARGET_DIR=$(CDPATH='' cd -- "$TARGET_DIR" && pwd)

FAIL_COUNT=0
WARN_COUNT=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
  WARN_COUNT=$((WARN_COUNT + 1))
}

# 実行可能であることを要求する。
#
# 欠落と実行ビット落ちを別メッセージにする。利用者にとって対処が
# 「コピーする」と「chmod +x する」で異なるため。
require_executable() {
  req_path="$TARGET_DIR/$1"
  req_why=$2
  if [ ! -e "$req_path" ]; then
    fail "$1 が存在しない → $req_why"
    return 0
  fi
  if [ ! -x "$req_path" ]; then
    fail "$1 に実行権限がない（chmod +x が必要）→ $req_why"
  fi
}

require_file() {
  req_path="$TARGET_DIR/$1"
  req_why=$2
  [ -f "$req_path" ] || fail "$1 が存在しない → $req_why"
}

# ---------------------------------------------------------------------------
# 1. hooks（settings.json の参照先）
# ---------------------------------------------------------------------------

require_executable '.claude/hooks/pre-tool-use.sh' \
  'PreToolUseが起動せず、write scope照合とBash構造検証が行われない（§3.6.1, §3.6.2）'
require_executable '.claude/hooks/post-tool-use.sh' \
  'PostToolUseのsecret scanが行われない（§3.5 Detective）'
require_executable '.claude/hooks/subagent-stop.sh' \
  'agent-run成果物の完了確認が行われない（§3.5 Completion check）'
require_executable '.claude/hooks/stop-gate.sh' \
  'revision整合とblocking issueの確認が行われない（§3.5 State commit）'

# ---------------------------------------------------------------------------
# 2. scripts（pre-tool-use.sh が委譲する判定ロジック）
#
# pre-tool-use.sh は ${CLAUDE_PROJECT_DIR}/scripts/ を参照する。
# .claude/scripts/ ではない。ここが最も間違えられる。
# ---------------------------------------------------------------------------

require_executable 'scripts/verify-bash-command.sh' \
  'Bashが全てdenyされる（pre-tool-use.sh のfail-closed判定）'
require_executable 'scripts/verify-write-scope.sh' \
  'Write・Edit・NotebookEditが全てdenyされる（同上）'

# verify-bash-command.sh が内部で直接呼ぶ依存。
# pre-tool-use.sh 側にガードが無いため、これだけが欠けると
# 通常のコマンドは通り、リダイレクトを含むコマンドで初めて失敗する。
# 症状が遅れて出るぶん切り分けが難しく、明示的に検査する価値が高い。
require_executable 'scripts/verify-redirect-target.sh' \
  'リダイレクトを含むBashコマンドが検証できず失敗する（verify-bash-command.sh の依存）'

# ---------------------------------------------------------------------------
# 3. 設定ファイルの存在
# ---------------------------------------------------------------------------

require_file '.claude/bash-allowlist' \
  'Bashが全てdenyされる（pre-tool-use.sh のfail-closed判定）'
require_file '.claude/write-scope-policy' \
  'Write・Edit・NotebookEditが全てdenyされる（同上）'
require_file '.claude/settings.json' \
  'hooksが登録されず、guardrailが一切起動しない'

# ---------------------------------------------------------------------------
# 4. 設定ファイルの中身が雛形のままでないか
#
# bootstrapプロファイル（.claude/bash-allowlist に
# ./scripts/harness-state-write.sh の実効行がある）では、allowlist実効行0や
# プレースホルダ残存は「導入成功、ただし全deny」を正常終了として報告する
# ことになるため、WARNではなくFAILとして扱う。
#
# strictプロファイルでは、§16-2の監査前の正当な中間状態でありうるため
# 従来どおりWARNのままとする。
# ---------------------------------------------------------------------------

ALLOWLIST="$TARGET_DIR/.claude/bash-allowlist"
IS_BOOTSTRAP_PROFILE=0
if [ -f "$ALLOWLIST" ] && grep -Fxq './scripts/harness-state-write.sh' "$ALLOWLIST"; then
  IS_BOOTSTRAP_PROFILE=1
fi

if [ -f "$ALLOWLIST" ]; then
  # コメントと空行を除いた実効行を数える
  ENTRY_COUNT=$(grep -cv -E '^[[:space:]]*(#|$)' "$ALLOWLIST" || true)
  if [ "$ENTRY_COUNT" -eq 0 ]; then
    if [ "$IS_BOOTSTRAP_PROFILE" -eq 1 ]; then
      fail '.claude/bash-allowlist に実効行が無い（全行コメント）→ 全てのBashコマンドがALLOWLIST_MISSで拒否される。bootstrapプロファイルの種が壊れている'
    else
      warn '.claude/bash-allowlist に実効行が無い（全行コメント）→ 全てのBashコマンドがALLOWLIST_MISSで拒否される。雛形のままでは使えない（§16-2）'
    fi
  fi
fi

POLICY="$TARGET_DIR/.claude/write-scope-policy"
if [ -f "$POLICY" ]; then
  if grep -q 'com/example/order' "$POLICY"; then
    if [ "$IS_BOOTSTRAP_PROFILE" -eq 1 ]; then
      fail '.claude/write-scope-policy に雛形のプレースホルダ（com/example/order）が残っている → bootstrapプロファイルの種が壊れている'
    else
      warn '.claude/write-scope-policy に雛形のプレースホルダ（com/example/order）が残っている → 実プロジェクトの構成へ置き換えが必要'
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. settings.json の hook パスが実在するか
#
# jq に依存せず "command" 行を抽出する（macOS awk + Bash 3.2 のみ）。
# ---------------------------------------------------------------------------

SETTINGS="$TARGET_DIR/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  # "command": "..." の値を取り出し、${CLAUDE_PROJECT_DIR} を実パスへ展開する
  COMMAND_PATHS=$(LC_ALL=C awk '
    /"command"[[:space:]]*:/ {
      line = $0
      idx = index(line, "\"command\"")
      rest = substr(line, idx + 9)
      # : の後の最初の "..." を取る
      if (match(rest, /"[^"]*"/)) {
        print substr(rest, RSTART + 1, RLENGTH - 2)
      }
    }' "$SETTINGS" || true)

  # COMMAND_PATHS は改行区切りの複数行文字列であり、プロジェクトパスに
  # 空白を含む場合がある。単語分割（IFS=空白）で走査すると1パスが
  # 複数トークンに割れて誤FAILする。改行だけをセパレータにする。
  OLD_IFS=$IFS
  IFS='
'
  for cmd_path in $COMMAND_PATHS; do
    IFS=$OLD_IFS
    [ -n "$cmd_path" ] || continue
    # ${CLAUDE_PROJECT_DIR} と $CLAUDE_PROJECT_DIR の両表記を展開
    resolved=$(printf '%s' "$cmd_path" \
      | sed -e "s|\${CLAUDE_PROJECT_DIR}|$TARGET_DIR|g" \
            -e "s|\$CLAUDE_PROJECT_DIR|$TARGET_DIR|g")
    case $resolved in
      /*) ;;
      *) resolved="$TARGET_DIR/$resolved" ;;
    esac
    if [ ! -x "$resolved" ]; then
      fail "settings.json が参照する hook が実行できない: $cmd_path"
    fi
    IFS='
'
  done
  IFS=$OLD_IFS
fi

# ---------------------------------------------------------------------------
# 6. 疎通スモークテスト
#
# 個々のファイルが揃っていても配線が壊れていることはある。
# allowlistに実際に載っているコマンドをPreToolUseイベントとして流し、
# denyされないことを確認する。これが配線をend-to-endで見る唯一の検査。
#
# 前段でFAILが出ている場合は実施しない（denyされて当然のため、
# 二重に報告しても切り分けの役に立たない）。
# ---------------------------------------------------------------------------

HOOK="$TARGET_DIR/.claude/hooks/pre-tool-use.sh"

# bootstrapプロファイルでは harness-state-write.sh 用の専用スモークを使う
# （後述）。汎用スモークはそれ以外のコマンド（strictプロファイルで
# 追記されたビルド/テストコマンド等）を対象とする。
if [ "$IS_BOOTSTRAP_PROFILE" -eq 1 ] && [ -f "$ALLOWLIST" ]; then
  SMOKE_CMD=$(grep -v -E '^[[:space:]]*(#|$)' "$ALLOWLIST" 2>/dev/null \
    | grep -v -F './scripts/harness-state-write.sh' | head -n 1 || true)
else
  SMOKE_CMD=$(grep -v -E '^[[:space:]]*(#|$)' "$ALLOWLIST" 2>/dev/null | head -n 1 || true)
fi

if [ "$FAIL_COUNT" -eq 0 ] && [ -x "$HOOK" ] && [ -f "$ALLOWLIST" ]; then
  if [ -n "$SMOKE_CMD" ]; then
    SMOKE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-smoke.XXXXXX") || exit 2
    smoke_cleanup() {
      rm -rf -- "$SMOKE_TMP"
    }
    trap smoke_cleanup EXIT HUP INT TERM

    SMOKE_EVENT=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s --version"},"cwd":"%s"}' \
      "$SMOKE_CMD" "$TARGET_DIR")

    SMOKE_OUT="$SMOKE_TMP/out"
    printf '%s' "$SMOKE_EVENT" \
      | CLAUDE_PROJECT_DIR="$TARGET_DIR" HARNESS_SCRATCH_DIR="$SMOKE_TMP" \
        "$HOOK" > "$SMOKE_OUT" 2>"$SMOKE_TMP/err" || true

    DECISION=$(LC_ALL=C awk '
      BEGIN { RS = "\0" }
      {
        idx = index($0, "\"permissionDecision\"")
        if (idx == 0) { print "NO_DECISION"; exit }
        rest = substr($0, idx + length("\"permissionDecision\""))
        if (match(rest, /"[a-z]+"/)) {
          print substr(rest, RSTART + 1, RLENGTH - 2)
        } else { print "UNPARSEABLE" }
      }' "$SMOKE_OUT")

    case $DECISION in
      # pre-tool-use.sh の allow() は "defer" を返す。hookは通す判断を
      # permissions側へ委ね、自分では force-allow しない（settings.json の
      # $comment が述べる二層構造）。したがって "allow" は正常応答ではない。
      defer)
        ;;
      deny)
        REASON=$(sed -n '1,3p' "$SMOKE_OUT" | tr -d '\n' | cut -c1-300)
        fail "疎通確認: allowlist上のコマンド '$SMOKE_CMD' がdenyされた。個々のファイルは揃っているが配線が正しくない。応答: $REASON"
        ;;
      NO_DECISION|UNPARSEABLE)
        fail "疎通確認: pre-tool-use.sh がpermissionDecisionを返さない（hookプロトコル不整合）"
        ;;
      *)
        fail "疎通確認: 想定外のpermissionDecision: $DECISION"
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# 7. bootstrapプロファイル専用スモーク（実装計画 quizzical-munching-origami §6）
#
# 「導入直後にharness-orchestration Skillをstartで起動でき、PHASE-0が進む」
# ことをend-to-endで見る。個々のファイルが揃っていても、この3点のどれかが
# 壊れていれば鶏と卵は解けていない。
# ---------------------------------------------------------------------------

smoke_permission_decision() {
  # $1: HOOKへ渡すevent JSON, $2: 追加の環境変数（"NAME=value" 形式、無ければ空）
  smoke_out=$(
    if [ -n "$2" ]; then
      env "$2" CLAUDE_PROJECT_DIR="$TARGET_DIR" "$HOOK"
    else
      CLAUDE_PROJECT_DIR="$TARGET_DIR" "$HOOK"
    fi <<SMOKE_EOF
$1
SMOKE_EOF
  ) || true
  LC_ALL=C awk '
    BEGIN { RS = "\0" }
    {
      idx = index($0, "\"permissionDecision\"")
      if (idx == 0) { print "NO_DECISION"; exit }
      rest = substr($0, idx + length("\"permissionDecision\""))
      if (match(rest, /"[a-z]+"/)) {
        print substr(rest, RSTART + 1, RLENGTH - 2)
      } else { print "UNPARSEABLE" }
    }' <<SMOKE_EOF
$smoke_out
SMOKE_EOF
}

if [ "$FAIL_COUNT" -eq 0 ] && [ "$IS_BOOTSTRAP_PROFILE" -eq 1 ] && [ -x "$HOOK" ]; then
  BOOTSTRAP_SMOKE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-bootstrap-smoke.XXXXXX") || exit 2
  bootstrap_smoke_cleanup() {
    rm -rf -- "$BOOTSTRAP_SMOKE_TMP"
  }
  trap bootstrap_smoke_cleanup EXIT HUP INT TERM

  # 7a. Bash: ./scripts/harness-state-write.sh が defer を返す
  DECISION=$(smoke_permission_decision \
    '{"tool_name":"Bash","tool_input":{"command":"./scripts/harness-state-write.sh progress"}}' \
    "HARNESS_SCRATCH_DIR=$BOOTSTRAP_SMOKE_TMP")
  if [ "$DECISION" != 'defer' ]; then
    fail "疎通確認(bootstrap): ./scripts/harness-state-write.sh がdeferを返さない（応答: $DECISION）"
  fi

  # 7b. Write: docs/features/x/y.md が defer、docs/status/progress.yaml が deny
  DECISION=$(smoke_permission_decision \
    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TARGET_DIR/docs/features/x/y.md\"}}" '')
  if [ "$DECISION" != 'defer' ]; then
    fail "疎通確認(bootstrap): docs/features/x/y.md へのWriteがdeferを返さない（応答: $DECISION）"
  fi

  DECISION=$(smoke_permission_decision \
    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TARGET_DIR/docs/status/progress.yaml\"}}" '')
  if [ "$DECISION" != 'deny' ]; then
    fail "疎通確認(bootstrap): docs/status/progress.yaml へのWriteがdenyされない（応答: $DECISION）。single writer原則が破られている"
  fi

  # 7c. 状態書込み: ステージング経由の progress.yaml 確定が成功する
  #
  # 実際のprogress.yamlを書き換えないよう、隔離した一時repoで検証する。
  STATE_WRITE="$TARGET_DIR/scripts/harness-state-write.sh"
  if [ -x "$STATE_WRITE" ] && [ -f "$TARGET_DIR/docs/status/progress.yaml" ]; then
    STATE_TMP="$BOOTSTRAP_SMOKE_TMP/state-write-check"
    mkdir -p -- "$STATE_TMP/docs/status/.staging" "$STATE_TMP/docs/status"

    EXISTING_REVISION=$(
      LC_ALL=C awk '/^revision:[ \t]*/ { sub(/^revision:[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit }' \
        "$TARGET_DIR/docs/status/progress.yaml"
    )
    cp -- "$TARGET_DIR/docs/status/progress.yaml" "$STATE_TMP/docs/status/progress.yaml"

    NEXT_REVISION=$((EXISTING_REVISION + 1))
    {
      printf 'revision: %s\n' "$NEXT_REVISION"
      printf 'expected_previous_revision: %s\n' "$EXISTING_REVISION"
      printf 'current_task: PHASE-0\n'
      printf 'next_action: "smoke test"\n'
      printf 'blocking_issues: []\n'
    } > "$STATE_TMP/docs/status/.staging/progress.yaml"

    if CLAUDE_PROJECT_DIR="$STATE_TMP" "$STATE_WRITE" progress >/dev/null 2>"$BOOTSTRAP_SMOKE_TMP/state-write-err"; then
      :
    else
      STATE_ERR=$(tr -d '\n' < "$BOOTSTRAP_SMOKE_TMP/state-write-err" | cut -c1-300)
      fail "疎通確認(bootstrap): harness-state-write.sh progress がステージング経由で確定できない: $STATE_ERR"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 結果
# ---------------------------------------------------------------------------

if [ "$FAIL_COUNT" -ne 0 ]; then
  printf '\n%d件のFAIL、%d件のWARN。ハーネスは正しく機能しない。\n' \
    "$FAIL_COUNT" "$WARN_COUNT" >&2
  printf 'install-harness.sh --target %s で修復できる。\n' "$TARGET_DIR" >&2
  exit 2
fi

if [ "$WARN_COUNT" -ne 0 ]; then
  printf '\n必須条件は満たすが、%d件のWARNがある（雛形のまま運用すると意図した保護は得られない）。\n' \
    "$WARN_COUNT" >&2
  exit 0
fi

printf 'ok: ハーネス導入は正常（%s）\n' "$TARGET_DIR"
