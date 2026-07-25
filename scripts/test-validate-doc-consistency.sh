#!/bin/bash

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/validate-doc-consistency-test.XXXXXX") || exit 1
FIXTURE_DIR="$WORK_DIR/repository"
OUTPUT_FILE="$WORK_DIR/validator-output"
SPLIT_FIXTURE_DIR="$WORK_DIR/split-repository"
SPLIT_OUTPUT_FILE="$WORK_DIR/split-validator-output"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir "$FIXTURE_DIR"
cp -R "$ROOT_DIR/README.md" "$ROOT_DIR/patterns" "$ROOT_DIR/research" "$ROOT_DIR/scripts" "$FIXTURE_DIR/"

DESIGN_FILE="$FIXTURE_DIR/patterns/claude-code-development-harness/docs/design.md"
MUTATED_DESIGN_FILE="$WORK_DIR/design.md"

awk '
  $0 == "  gate_definition: IMPLEMENTATION_REVIEW_TARGET" { in_target = 1 }
  in_target && $0 == "  evaluated_code_commit: 890xyz111222" { next }
  in_target && $0 == "  status: passed" { in_target = 0; next }
  { print }
' "$DESIGN_FILE" > "$MUTATED_DESIGN_FILE"
mv "$MUTATED_DESIGN_FILE" "$DESIGN_FILE"

if bash "$FIXTURE_DIR/scripts/validate-doc-consistency.sh" > "$OUTPUT_FILE" 2>&1; then
  printf '%s\n' 'FAIL: IMPLEMENTATION_REVIEW_TARGETの欠落fieldを後続gateから採用した' >&2
  exit 1
fi

if ! grep -Fq -- 'FAIL: IMPLEMENTATION_REVIEW_TARGET GateRun例にevaluated_code_commitがない' "$OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: IMPLEMENTATION_REVIEW_TARGETの欠落fieldを検出できなかった' >&2
  sed -n '1,120p' "$OUTPUT_FILE" >&2
  exit 1
fi

printf '%s\n' 'Validator regression test passed.'

mkdir "$SPLIT_FIXTURE_DIR"
cp -R "$ROOT_DIR/README.md" "$ROOT_DIR/patterns" "$ROOT_DIR/research" "$ROOT_DIR/scripts" "$SPLIT_FIXTURE_DIR/"

SPLIT_DESIGN_FILE="$SPLIT_FIXTURE_DIR/patterns/claude-code-development-harness/docs/design.md"
SPLIT_MUTATED_DESIGN_FILE="$WORK_DIR/split-design.md"

awk '
  $0 == "  gate_definition: IMPLEMENTATION_REVIEW_TARGET" { in_target = 1 }
  in_target && $0 == "  status: passed" {
    print "- gate_run_id: gate-run-TASK-004-implementation-review-target-008"
    print "  gate_definition: IMPLEMENTATION_REVIEW_TARGET"
    print "  phase_run_id: phase-run-TASK-004-007"
    print "  task: TASK-004"
    print "  input_revision: 41"
    print "  status: passed"
    in_target = 0
    next
  }
  { print }
' "$SPLIT_DESIGN_FILE" > "$SPLIT_MUTATED_DESIGN_FILE"
mv "$SPLIT_MUTATED_DESIGN_FILE" "$SPLIT_DESIGN_FILE"

if bash "$SPLIT_FIXTURE_DIR/scripts/validate-doc-consistency.sh" > "$SPLIT_OUTPUT_FILE" 2>&1; then
  printf '%s\n' 'FAIL: 複数のIMPLEMENTATION_REVIEW_TARGETからfieldを合成した' >&2
  exit 1
fi

if ! grep -Fq -- 'FAIL: IMPLEMENTATION_REVIEW_TARGET GateRun例にevaluated_code_commitがない' "$SPLIT_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: 同一IMPLEMENTATION_REVIEW_TARGET内の必須field欠落を検出できなかった' >&2
  sed -n '1,120p' "$SPLIT_OUTPUT_FILE" >&2
  exit 1
fi

printf '%s\n' 'Validator split-record regression test passed.'

# 版番号とDecision ID件数の検査が、未改変の設計書へ誤検知しないこと。
# 付録は新しい版を先頭に置くため、出現順の末尾は最古の版になる。
# Decision IDの件数を定数で固定すると、決定を追加するたびに誤検知する。
PRISTINE_FIXTURE_DIR="$WORK_DIR/pristine-repository"
PRISTINE_OUTPUT_FILE="$WORK_DIR/pristine-validator-output"

mkdir "$PRISTINE_FIXTURE_DIR"
cp -R "$ROOT_DIR/README.md" "$ROOT_DIR/patterns" "$ROOT_DIR/research" "$ROOT_DIR/scripts" "$PRISTINE_FIXTURE_DIR/"

bash "$PRISTINE_FIXTURE_DIR/scripts/validate-doc-consistency.sh" > "$PRISTINE_OUTPUT_FILE" 2>&1 || true

if grep -Fq -- 'FAIL: 版番号が一致しない' "$PRISTINE_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: 未改変の設計書に対して版番号の不一致を誤検知した' >&2
  grep -F -- 'FAIL: 版番号が一致しない' "$PRISTINE_OUTPUT_FILE" >&2
  exit 1
fi

if grep -Fq -- 'FAIL: Decision IDは' "$PRISTINE_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: 未改変の設計書に対してDecision ID件数の不一致を誤検知した' >&2
  grep -F -- 'FAIL: Decision IDは' "$PRISTINE_OUTPUT_FILE" >&2
  exit 1
fi

# 品質ゲート表の抽出が§11.0以降へ及ばないこと。
# §11.0のintra-phase評価順序表は第1列がPhase IDであり、ゲート名ではない。
if grep -Eq -- "FAIL: 品質ゲート 'PHASE-[0-9]+' " "$PRISTINE_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: Phase IDを品質ゲート名として抽出した' >&2
  grep -E -- "FAIL: 品質ゲート 'PHASE-[0-9]+' " "$PRISTINE_OUTPUT_FILE" >&2
  exit 1
fi

# 未改変の設計書は文書整合性検証を通過すること。
if [ -s "$PRISTINE_OUTPUT_FILE" ] && grep -Fq -- 'FAIL:' "$PRISTINE_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: 未改変の設計書が文書整合性検証を通過しなかった' >&2
  grep -F -- 'FAIL:' "$PRISTINE_OUTPUT_FILE" >&2
  exit 1
fi

printf '%s\n' 'Validator false-positive regression test passed.'

# 版番号の不一致そのものは引き続き検出できること。
MISMATCH_FIXTURE_DIR="$WORK_DIR/mismatch-repository"
MISMATCH_OUTPUT_FILE="$WORK_DIR/mismatch-validator-output"

mkdir "$MISMATCH_FIXTURE_DIR"
cp -R "$ROOT_DIR/README.md" "$ROOT_DIR/patterns" "$ROOT_DIR/research" "$ROOT_DIR/scripts" "$MISMATCH_FIXTURE_DIR/"

MISMATCH_DESIGN_FILE="$MISMATCH_FIXTURE_DIR/patterns/claude-code-development-harness/docs/design.md"
MISMATCH_MUTATED_DESIGN_FILE="$WORK_DIR/mismatch-design.md"

sed 's/^| 版 \(.*\)Version [0-9][0-9.]*/| 版 \1Version 99.0/' "$MISMATCH_DESIGN_FILE" > "$MISMATCH_MUTATED_DESIGN_FILE"
mv "$MISMATCH_MUTATED_DESIGN_FILE" "$MISMATCH_DESIGN_FILE"

bash "$MISMATCH_FIXTURE_DIR/scripts/validate-doc-consistency.sh" > "$MISMATCH_OUTPUT_FILE" 2>&1 || true

if ! grep -Fq -- 'FAIL: 版番号が一致しない' "$MISMATCH_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: header版番号の不一致を検出できなかった' >&2
  sed -n '1,120p' "$MISMATCH_OUTPUT_FILE" >&2
  exit 1
fi

printf '%s\n' 'Validator version-mismatch regression test passed.'

# Decision IDの連番欠落は引き続き検出できること。
GAP_FIXTURE_DIR="$WORK_DIR/gap-repository"
GAP_OUTPUT_FILE="$WORK_DIR/gap-validator-output"

mkdir "$GAP_FIXTURE_DIR"
cp -R "$ROOT_DIR/README.md" "$ROOT_DIR/patterns" "$ROOT_DIR/research" "$ROOT_DIR/scripts" "$GAP_FIXTURE_DIR/"

GAP_DESIGN_FILE="$GAP_FIXTURE_DIR/patterns/claude-code-development-harness/docs/design.md"
GAP_MUTATED_DESIGN_FILE="$WORK_DIR/gap-design.md"

grep -v '^| DEC-002 |' "$GAP_DESIGN_FILE" > "$GAP_MUTATED_DESIGN_FILE"
mv "$GAP_MUTATED_DESIGN_FILE" "$GAP_DESIGN_FILE"

bash "$GAP_FIXTURE_DIR/scripts/validate-doc-consistency.sh" > "$GAP_OUTPUT_FILE" 2>&1 || true

if ! grep -Fq -- 'FAIL: Decision IDの連番が不正' "$GAP_OUTPUT_FILE"; then
  printf '%s\n' 'FAIL: Decision IDの連番欠落を検出できなかった' >&2
  sed -n '1,120p' "$GAP_OUTPUT_FILE" >&2
  exit 1
fi

printf '%s\n' 'Validator decision-gap regression test passed.'
