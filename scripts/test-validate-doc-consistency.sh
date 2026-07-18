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
