#!/bin/bash
#
# 出典: Claude Code Development Harness 設計書 Version 1.11
# https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md
#
# 配布元: このパターンリポジトリの templates/scripts/。
# このスクリプトは**テンプレート側から実行する**。導入先へコピーして使うのではない。
#
# 正本: 設計書 §3.5, §3.5.1, §3.6.1, §3.6.2, §14.1
#
# ---------------------------------------------------------------------------
# ハーネス雛形を利用者リポジトリへ冪等に導入する。
#
# なぜスクリプトが必要か:
#   hooks は fail-closed 設計であり、設定漏れは「制限なし」ではなく
#   「全拒否」になる。特に pre-tool-use.sh は ${CLAUDE_PROJECT_DIR}/scripts/
#   を参照するため、.claude/ 配下だけをコピーすると Bash・Write・Edit が
#   全てdenyされる。手作業のcp/chmodではこの漏れが再発し続ける。
#
# なぜ --target を取るか:
#   防ごうとしている障害はコピー漏れそのものである。installerが導入先に
#   存在することを前提にすると、installer自身が同じ漏れの対象になる。
#   テンプレートcheckoutから導入先を指す形にすれば、忘れようがない。
#
# 使用法:
#   install-harness.sh [--target <dir>] [--profile bootstrap|strict] [--dry-run] [--force] [--verify-only]
#
# --profile:
#   bootstrap（既定） 導入直後からharness-orchestration Skillをstartで起動でき、
#                     PHASE-0 が進む。allowlist/write-scope-policy/progress.yamlの
#                     鶏と卵を解いた最小構成。実装計画 quizzical-munching-origami 参照。
#   strict            従来のfail-closed雛形。プロジェクト固有のパスをallowへ
#                     書き込むまでBash・Writeがほぼ全deny。
#
# 終了コード:
#   0  導入と検証に成功
#   1  使用法の誤り、または target が不正
#   2  導入したが検証に失敗した
#   3  必要なテンプレートが見つからない
# ---------------------------------------------------------------------------

set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMPLATES_DIR=$(CDPATH='' cd -- "$SELF_DIR/.." && pwd)

TARGET_DIR=${PWD}
PROFILE=bootstrap
DRY_RUN=0
FORCE=0
VERIFY_ONLY=0

usage_and_exit() {
  printf 'usage: %s [--target <dir>] [--profile bootstrap|strict] [--dry-run] [--force] [--verify-only]\n' "$0" >&2
  exit "$1"
}

while [ $# -gt 0 ]; do
  case $1 in
    --target)
      [ $# -ge 2 ] || usage_and_exit 1
      TARGET_DIR=$2
      shift 2
      ;;
    --profile)
      [ $# -ge 2 ] || usage_and_exit 1
      PROFILE=$2
      shift 2
      ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --force)    FORCE=1; shift ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    -h|--help)
      usage_and_exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

case $PROFILE in
  bootstrap|strict) : ;;
  *)
    printf 'ERROR: 不正な --profile: %s（bootstrap または strict）\n' "$PROFILE" >&2
    exit 1
    ;;
esac

# 存在しないtargetは作らない。打ち間違えたパスに新しい木を生やさない。
if [ ! -d "$TARGET_DIR" ]; then
  printf 'ERROR: 導入先が存在しない: %s\n' "$TARGET_DIR" >&2
  printf 'ディレクトリを先に作成すること（typo防止のため自動作成しない）。\n' >&2
  exit 1
fi

TARGET_DIR=$(CDPATH='' cd -- "$TARGET_DIR" && pwd)

# 配布元へ自分自身を導入すると、テンプレートを自分で上書きし得る。
case "$TARGET_DIR" in
  "$TEMPLATES_DIR"|"$TEMPLATES_DIR"/*)
    printf 'ERROR: 配布元テンプレートへは導入できない: %s\n' "$TARGET_DIR" >&2
    exit 1
    ;;
esac

VERIFIER="$SELF_DIR/verify-harness-install.sh"

if [ "$VERIFY_ONLY" -eq 1 ]; then
  [ -x "$VERIFIER" ] || { printf 'ERROR: verify-harness-install.sh が無い\n' >&2; exit 3; }
  "$VERIFIER" --target "$TARGET_DIR"
  exit $?
fi

CREATED=0
UPDATED=0
SKIPPED=0

# ---------------------------------------------------------------------------
# Policy A: 無条件で雛形に合わせる（ロジック。カスタマイズ余地なし）
#
# 内容が一致していれば何も言わない。差分があるときだけUPDATEと報告する。
# これにより再実行が「出力としても静か」になり、アップグレード経路になる。
# ---------------------------------------------------------------------------
install_managed() {
  src=$1
  rel=$2
  dst="$TARGET_DIR/$rel"

  if [ ! -f "$src" ]; then
    printf 'ERROR: テンプレートが見つからない: %s\n' "$src" >&2
    exit 3
  fi

  if [ ! -e "$dst" ]; then
    printf 'CREATE %s\n' "$rel"
    CREATED=$((CREATED + 1))
    [ "$DRY_RUN" -eq 1 ] && return 0
    mkdir -p -- "$(dirname -- "$dst")"
    cp -- "$src" "$dst"
    return 0
  fi

  if cmp -s -- "$src" "$dst"; then
    return 0
  fi

  printf 'UPDATE %s\n' "$rel"
  UPDATED=$((UPDATED + 1))
  [ "$DRY_RUN" -eq 1 ] && return 0
  cp -- "$src" "$dst"
}

# ---------------------------------------------------------------------------
# Policy B: 無ければ作る、あれば触らない（利用者所有の設定）
#
# .new を毎回置くのは採らない。それ自体が非冪等で、利用者が
# 差分ファイルを無視するよう訓練されるため。差分確認は --dry-run を正とする。
# ---------------------------------------------------------------------------
install_owned() {
  src=$1
  rel=$2
  dst="$TARGET_DIR/$rel"

  if [ ! -f "$src" ]; then
    printf 'ERROR: テンプレートが見つからない: %s\n' "$src" >&2
    exit 3
  fi

  if [ ! -e "$dst" ]; then
    printf 'CREATE %s\n' "$rel"
    CREATED=$((CREATED + 1))
    [ "$DRY_RUN" -eq 1 ] && return 0
    mkdir -p -- "$(dirname -- "$dst")"
    cp -- "$src" "$dst"
    return 0
  fi

  if cmp -s -- "$src" "$dst"; then
    return 0
  fi

  printf 'SKIP   %s（カスタマイズ済み。雛形との差分は --dry-run で確認できる）\n' "$rel"
  SKIPPED=$((SKIPPED + 1))

  if [ "$FORCE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    cp -- "$src" "$dst.template"
    printf '       雛形を %s.template へ併置した（--force）\n' "$rel"
  fi
}

# ---------------------------------------------------------------------------
# Policy C: ディレクトリツリー（各ファイルは Policy A）
#
# skills/ は references/ や agents/ を含みネストする。
# Bash 3.2 に globstar は無いため find で走査し相対パスを再構成する。
# フラットな cp * では取りこぼす。
# ---------------------------------------------------------------------------
install_tree() {
  tree_src="$TEMPLATES_DIR/$1"
  tree_rel_base=$2

  if [ ! -d "$tree_src" ]; then
    printf 'ERROR: テンプレートディレクトリが見つからない: %s\n' "$tree_src" >&2
    exit 3
  fi

  find "$tree_src" -type f | while IFS= read -r found; do
    rel_path=${found#"$tree_src"/}
    printf '%s\n' "$tree_rel_base/$rel_path"
  done > "$TREE_LIST"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    sub=${rel#"$tree_rel_base"/}
    install_managed "$tree_src/$sub" "$rel"
  done < "$TREE_LIST"
}

TREE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/install-harness.XXXXXX") || exit 1
TREE_LIST="$TREE_TMP/list"
tmp_cleanup() {
  rm -rf -- "$TREE_TMP"
}
trap tmp_cleanup EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# 導入
# ---------------------------------------------------------------------------

printf '導入先: %s\n' "$TARGET_DIR"
printf 'プロファイル: %s\n' "$PROFILE"
[ "$DRY_RUN" -eq 1 ] && printf '(--dry-run: 実際には書き込まない)\n'

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p -- "$TARGET_DIR/.claude/hooks" "$TARGET_DIR/scripts"
fi

# hooks（Claude Codeプロトコル変換）
for hook in pre-tool-use.sh post-tool-use.sh subagent-stop.sh stop-gate.sh; do
  install_managed "$TEMPLATES_DIR/hooks/$hook" ".claude/hooks/$hook"
done

# 判定ロジック。参照先は ${CLAUDE_PROJECT_DIR}/scripts/ であり
# .claude/scripts/ ではない。ここが最も間違えられる。
for vscript in verify-bash-command.sh verify-redirect-target.sh verify-write-scope.sh; do
  install_managed "$TEMPLATES_DIR/scripts/$vscript" "scripts/$vscript"
done

# 診断スクリプトも配置する。障害時に導入先だけで切り分けられるようにする。
install_managed "$TEMPLATES_DIR/scripts/verify-harness-install.sh" \
  'scripts/verify-harness-install.sh'

# 状態書込みラッパ（bootstrapプロファイルのallowlistが参照する専用コマンド）。
# strictプロファイルでも配置する。ラッパ自体は害がなく、後日bootstrapへ
# 切り替える際に揃っている方が移行が滑らかである。
install_managed "$TEMPLATES_DIR/scripts/harness-state-write.sh" \
  'scripts/harness-state-write.sh'

# 利用者所有の設定。プロファイルにより配布元を切り替える。
if [ "$PROFILE" = 'bootstrap' ]; then
  install_owned "$TEMPLATES_DIR/settings.json"              '.claude/settings.json'
  install_owned "$TEMPLATES_DIR/bootstrap/bash-allowlist"    '.claude/bash-allowlist'
  install_owned "$TEMPLATES_DIR/bootstrap/write-scope-policy" '.claude/write-scope-policy'
else
  install_owned "$TEMPLATES_DIR/settings.json"       '.claude/settings.json'
  install_owned "$TEMPLATES_DIR/bash-allowlist"      '.claude/bash-allowlist'
  install_owned "$TEMPLATES_DIR/write-scope-policy"  '.claude/write-scope-policy'
fi

# ツリー
install_tree 'agents'    '.claude/agents'
install_tree 'rules'     '.claude/rules'
install_tree 'skills'    '.claude/skills'
install_tree 'workflows' '.claude/workflows'

# ---------------------------------------------------------------------------
# docsツリーのscaffold（bootstrapプロファイルのみ）。
#
# harness-orchestration Skill が start で PHASE-0 を進めるには、これらの
# ディレクトリが最初から存在している必要がある。存在しない場合、
# 最初のWriteが親ディレクトリの作成から始まり、write scope照合の
# 対象パス解決（§3.6.1のcanonical path化）が複雑になる。
# ---------------------------------------------------------------------------
if [ "$PROFILE" = 'bootstrap' ] && [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p -- \
    "$TARGET_DIR/docs/status/.staging" \
    "$TARGET_DIR/docs/status/agent-runs" \
    "$TARGET_DIR/docs/status/phase-runs" \
    "$TARGET_DIR/docs/status/changes" \
    "$TARGET_DIR/docs/project" \
    "$TARGET_DIR/docs/context/manifests" \
    "$TARGET_DIR/docs/features"

  STAGING_GITIGNORE="$TARGET_DIR/docs/status/.staging/.gitignore"
  if [ ! -e "$STAGING_GITIGNORE" ]; then
    printf '*\n!.gitignore\n' > "$STAGING_GITIGNORE"
    printf 'CREATE %s\n' 'docs/status/.staging/.gitignore'
    CREATED=$((CREATED + 1))
  fi

  # progress.yaml は無い場合のみ種を配置する。既存のprogress.yamlを
  # 上書きすると、進行中のプロジェクトの状態を破壊するため（Policy B相当）。
  PROGRESS_DEST="$TARGET_DIR/docs/status/progress.yaml"
  if [ ! -e "$PROGRESS_DEST" ]; then
    HEAD_COMMIT=''
    if git -C "$TARGET_DIR" rev-parse HEAD >/dev/null 2>&1; then
      HEAD_COMMIT=$(git -C "$TARGET_DIR" rev-parse HEAD)
    fi
    sed -e "s|current_commit: \"\"|current_commit: \"${HEAD_COMMIT}\"|" \
      "$TEMPLATES_DIR/bootstrap/progress.yaml" > "$PROGRESS_DEST"
    printf 'CREATE %s\n' 'docs/status/progress.yaml（種）'
    CREATED=$((CREATED + 1))
  fi
fi

# ---------------------------------------------------------------------------
# chmod は毎回無条件に適用する。
#
# コピーの有無に条件づけない。実行ビット落ちの修復こそが、
# このスクリプトが排除しようとしているバグclassそのものであるため。
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
  for sh_file in "$TARGET_DIR/.claude/hooks/"*.sh; do
    [ -f "$sh_file" ] && chmod +x "$sh_file"
  done
  for sh_file in "$TARGET_DIR/scripts/"verify-*.sh; do
    [ -f "$sh_file" ] && chmod +x "$sh_file"
  done
  [ -f "$TARGET_DIR/scripts/harness-state-write.sh" ] && chmod +x "$TARGET_DIR/scripts/harness-state-write.sh"
fi

printf '\nCREATE %d件 / UPDATE %d件 / SKIP %d件\n' "$CREATED" "$UPDATED" "$SKIPPED"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '(--dry-run のため何も書き込んでいない)\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# 導入直後に検証する。
#
# 「コピーした」ことと「機能する」ことは別である。
# 雛形のままのallowlistは全コマンドを拒否するため、
# ここで警告が出ることは正常な初回導入の姿である。
# ---------------------------------------------------------------------------
printf '\n--- 導入結果の検証 ---\n'

if [ ! -x "$VERIFIER" ]; then
  printf 'ERROR: verify-harness-install.sh が実行できない\n' >&2
  exit 3
fi

if "$VERIFIER" --target "$TARGET_DIR"; then
  if [ "$PROFILE" = 'bootstrap' ]; then
    printf '\n次の手順:\n'
    printf '  1. 今すぐ harness-orchestration Skill を start で起動できる。\n'
    printf '  2. ビルド/テストコマンドは PHASE-0 の実測後、監査（§16-2）を経て .claude/bash-allowlist へ追記する。\n'
    printf '  3. .claude/write-scope-policy をプロジェクトの構成に合わせて調整する。\n'
  else
    printf '\n次の手順:\n'
    printf '  1. .claude/bash-allowlist へ実際に使うコマンドを追記する（§16-2 の監査を経ること）\n'
    printf '  2. .claude/write-scope-policy をプロジェクトの構成に合わせる\n'
    printf '  3. docs/status/ に baseline.yaml と progress.yaml を用意し PHASE-0 を開始する\n'
  fi
  exit 0
fi

printf '\n検証に失敗した。上記のFAILを解消すること。\n' >&2
exit 2
