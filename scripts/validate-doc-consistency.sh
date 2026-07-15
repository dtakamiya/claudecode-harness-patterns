#!/bin/bash

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESIGN_FILE="$ROOT_DIR/patterns/claude-code-development-harness/docs/design.md"
ERRORS=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  ERRORS=$((ERRORS + 1))
}

if [ ! -f "$DESIGN_FILE" ] || [ ! -r "$DESIGN_FILE" ] || [ -L "$DESIGN_FILE" ]; then
  printf '%s\n' "FAIL: 設計書が通常の読取り可能ファイルではない: $DESIGN_FILE" >&2
  exit 1
fi

TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/doc-consistency.XXXXXX") || exit 1
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

PHASES_FILE="$WORK_DIR/phases"
AGENTS_FILE="$WORK_DIR/agents"
QUALITY_FILE="$WORK_DIR/quality-gates"
STATE_FILE="$WORK_DIR/state-gates"
DIRECTORY_AGENTS_FILE="$WORK_DIR/directory-agents"

if ! awk -F'|' '
  /^`PhaseDefinition`の実値は/ { in_phases = 1; next }
  /^Agentの`tools`/ { in_phases = 0 }
  in_phases && /^\| `PHASE-[0-9]+`/ {
    id = $2
    match(id, /PHASE-[0-9]+/)
    id = substr(id, RSTART, RLENGTH)
    entry = $5
    exit_gate = $6
    agents = $7
    gsub(/[ `]/, "", entry)
    gsub(/[ `]/, "", exit_gate)
    gsub(/ /, "", agents)
    print id "|" entry "|" exit_gate "|" agents
  }
' "$DESIGN_FILE" > "$PHASES_FILE"; then
  fail 'PhaseDefinition表を解析できない'
fi

if ! awk -F'|' '
  /^\| AgentDefinition id / { in_agents = 1; next }
  in_agents && /^$/ { in_agents = 0 }
  in_agents && /^\| [a-z][a-z0-9-]+ / {
    id = $2
    phases = $4
    profile = $6
    gsub(/^ +| +$/, "", id)
    gsub(/ /, "", phases)
    gsub(/^ +| +$/, "", profile)
    print id "|" phases "|" profile
  }
' "$DESIGN_FILE" > "$AGENTS_FILE"; then
  fail 'AgentDefinition表を解析できない'
fi

if ! awk -F'|' '
  /^# 11\. 品質ゲート/ { in_gates = 1; next }
  /^## 11\.1/ { in_gates = 0 }
  in_gates && /^\| [A-Z][A-Z0-9_]+/ {
    value = $2
    gsub(/[ `]/, "", value)
    print value
  }
' "$DESIGN_FILE" > "$QUALITY_FILE"; then
  fail '品質ゲート表を解析できない'
fi

if ! awk -F: '
  /^gates:$/ && !found { in_gates = 1; found = 1; next }
  in_gates && /^blocking_issues:/ { in_gates = 0 }
  in_gates && /^  [a-z_]+:/ {
    key = $1
    value = $2
    gsub(/^ +| +$/, "", key)
    gsub(/^ +| +$/, "", value)
    print key "|" value
  }
' "$DESIGN_FILE" > "$STATE_FILE"; then
  fail 'progress.yamlのゲート例を解析できない'
fi

if ! awk '
  /^\.claude\/$/ { in_agents = 1; next }
  in_agents && /^├─ rules\// { in_agents = 0 }
  in_agents && /\.md$/ {
    value = $0
    sub(/^.*[├└]─ /, "", value)
    sub(/\.md$/, "", value)
    print value
  }
' "$DESIGN_FILE" > "$DIRECTORY_AGENTS_FILE"; then
  fail '推奨Agentディレクトリを解析できない'
fi

if [ "$(wc -l < "$PHASES_FILE" | tr -d ' ')" -ne 11 ]; then
  fail 'PhaseDefinitionはPHASE-0〜PHASE-10の11件でなければならない'
fi

expected_phase=0
previous_exit=''
while IFS='|' read -r phase entry exit_gate phase_agents; do
  expected_id="PHASE-$expected_phase"
  if [ "$phase" != "$expected_id" ]; then
    fail "PhaseDefinitionの連番が不正: expected=$expected_id actual=$phase"
  fi
  if [ "$expected_phase" -gt 0 ] && [ "$entry" != "$previous_exit" ]; then
    fail "隣接Phaseのゲート連鎖が不一致: $phase entry=$entry previous_exit=$previous_exit"
  fi
  previous_exit=$exit_gate
  expected_phase=$((expected_phase + 1))

  for gate in "$entry" "$exit_gate"; do
    if [ "$gate" != '—' ] && ! grep -Fxq -- "$gate" "$QUALITY_FILE"; then
      fail "PhaseDefinitionが参照するゲート '$gate' が品質ゲート一覧にない"
    fi
  done

  old_ifs=$IFS
  IFS=','
  for agent in $phase_agents; do
    IFS=$old_ifs
    agent=$(printf '%s' "$agent" | sed 's/^ *//;s/ *$//')
    allowed=$(awk -F'|' -v id="$agent" '$1 == id { print $2 }' "$AGENTS_FILE")
    if [ -z "$allowed" ]; then
      fail "${phase}が未定義Agent '$agent' を参照している"
    elif [ "$allowed" != 'PHASE-0..10' ] && ! printf ',%s,' "$allowed" | grep -Fq -- ",$phase,"; then
      fail "${phase}とAgent '$agent' のallowed_phasesが双方向一致しない"
    fi
    IFS=','
  done
  IFS=$old_ifs
done < "$PHASES_FILE"

for file in "$AGENTS_FILE" "$QUALITY_FILE" "$STATE_FILE" "$DIRECTORY_AGENTS_FILE"; do
  duplicates=$(cut -d'|' -f1 "$file" | sort | uniq -d)
  if [ -n "$duplicates" ]; then
    fail "定義IDが重複している: $duplicates"
  fi
done

while IFS='|' read -r agent allowed_phases profile; do
  if [ "$agent" = 'development-orchestrator' ]; then
    continue
  fi
  if [ "$allowed_phases" = 'PHASE-0..10' ]; then
    phase_numbers='0 1 2 3 4 5 6 7 8 9 10'
  else
    phase_numbers=$(printf '%s' "$allowed_phases" | sed 's/PHASE-//g;s/,/ /g')
  fi
  for number in $phase_numbers; do
    phase="PHASE-$number"
    phase_agents=$(awk -F'|' -v id="$phase" '$1 == id { print $4 }' "$PHASES_FILE")
    if ! printf ',%s,' "$phase_agents" | grep -Fq -- ",$agent,"; then
      fail "Agent '$agent' の${phase}許可がPhaseDefinition側にない"
    fi
  done
done < "$AGENTS_FILE"

while IFS= read -r directory_agent; do
  if ! awk -F'|' -v id="$directory_agent" '$1 == id { found = 1 } END { exit !found }' "$AGENTS_FILE"; then
    fail "推奨ディレクトリのAgent '$directory_agent' がAgentDefinitionにない"
  fi
done < "$DIRECTORY_AGENTS_FILE"

while IFS='|' read -r agent allowed_phases profile; do
  if ! grep -Fxq -- "$agent" "$DIRECTORY_AGENTS_FILE"; then
    fail "AgentDefinitionのAgent '$agent' が推奨ディレクトリにない"
  fi
done < "$AGENTS_FILE"

while IFS='|' read -r state_gate status; do
  canonical_gate=$(printf '%s' "$state_gate" | tr '[:lower:]' '[:upper:]')
  if ! grep -Fxq -- "$canonical_gate" "$QUALITY_FILE"; then
    fail "progress.yamlのゲート '$state_gate' が品質ゲート一覧にない"
  fi
  case "$status" in
    pending|passed|failed|blocked|not_applicable) ;;
    *) fail "progress.yamlのゲート '$state_gate' の状態 '$status' が不正" ;;
  esac
done < "$STATE_FILE"

while IFS= read -r quality_gate; do
  state_gate=$(printf '%s' "$quality_gate" | tr '[:upper:]' '[:lower:]')
  if ! awk -F'|' -v id="$state_gate" '$1 == id { found = 1 } END { exit !found }' "$STATE_FILE"; then
    fail "品質ゲート '$quality_gate' がprogress.yamlの例にない"
  fi
done < "$QUALITY_FILE"

DUPLICATE_DECISIONS=$(sed -n 's/^| \(DEC-[0-9][0-9][0-9]\) |.*/\1/p' "$DESIGN_FILE" | sort | uniq -d)
if [ -n "$DUPLICATE_DECISIONS" ]; then
  fail "Decision IDが重複している: $DUPLICATE_DECISIONS"
fi

EXPECTED_DECISION=1
while IFS= read -r decision; do
  expected=$(printf 'DEC-%03d' "$EXPECTED_DECISION")
  if [ "$decision" != "$expected" ]; then
    fail "Decision IDの連番が不正: expected=$expected actual=$decision"
  fi
  EXPECTED_DECISION=$((EXPECTED_DECISION + 1))
done <<EOF
$(sed -n 's/^| \(DEC-[0-9][0-9][0-9]\) |.*/\1/p' "$DESIGN_FILE")
EOF
if [ "$EXPECTED_DECISION" -ne 14 ]; then
  fail 'Decision IDはDEC-001〜DEC-013の13件でなければならない'
fi

HEADER_VERSION=$(sed -n 's/^| 版.*Version \([0-9][0-9.]*\).*$/\1/p' "$DESIGN_FILE")
LATEST_APPENDIX_VERSION=$(sed -n 's/^# 付録[A-Z]\. Version \([0-9][0-9.]*\).*$/\1/p' "$DESIGN_FILE" | tail -1)
LATEST_TARGET_VERSION=$(sed -n 's/^  target_version: \([0-9][0-9.]*\)$/\1/p' "$DESIGN_FILE" | tail -1)
if [ -z "$HEADER_VERSION" ] || [ "$HEADER_VERSION" != "$LATEST_APPENDIX_VERSION" ] || [ "$HEADER_VERSION" != "$LATEST_TARGET_VERSION" ]; then
  fail "版番号が一致しない: header=$HEADER_VERSION appendix=$LATEST_APPENDIX_VERSION target=$LATEST_TARGET_VERSION"
fi

CURRENT_REVIEW=$(sed -n '/^# 付録J\./,$p' "$DESIGN_FILE")
if printf '%s\n' "$CURRENT_REVIEW" | grep -Fq 'production_ready'; then
  fail '現行版の未実証モードがproduction_readyと表記されている'
fi

if ! grep -Fxq 'context-builder|PHASE-0..10|context_builder' "$AGENTS_FILE"; then
  fail 'Context Builderが専用の最小権限profileで登録されていない'
fi
if ! grep -Fxq 'IMPLEMENTATION_REVIEW_TARGET' "$QUALITY_FILE" || ! grep -Fxq 'CODE_REVIEW_TARGET' "$QUALITY_FILE"; then
  fail '実装評価用と最終コードレビュー用の固定対象が分離されていない'
fi
if ! grep -Fxq 'ui-verifier|PHASE-8|ui_verifier' "$AGENTS_FILE"; then
  fail 'UI_VERIFICATIONを実行する専用Agent/profileが定義されていない'
fi
if grep -Eq 'docs/(requirements|design|plans|tests|reviews|handoffs)/' "$DESIGN_FILE"; then
  fail '機能固有成果物がdocs/features/<feature-id>/外の旧global pathを参照している'
fi

if [ "$ERRORS" -ne 0 ]; then
  printf '%s\n' "Document consistency validation failed with $ERRORS error(s)." >&2
  exit 1
fi

printf '%s\n' 'Document consistency validation passed.'
