#!/bin/bash

set -u

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
DESIGN_FILE="$ROOT_DIR/patterns/claude-code-development-harness/docs/design.md"
JIRA_README_FILE="$ROOT_DIR/patterns/claude-code-jira-ticket-harness/README.md"
JIRA_DESIGN_FILE="$ROOT_DIR/patterns/claude-code-jira-ticket-harness/docs/design.md"
LIGHTWEIGHT_DESIGN_FILE="$ROOT_DIR/patterns/claude-code-lightweight-feature-harness/docs/design.md"
MICRO_DESIGN_FILE="$ROOT_DIR/patterns/claude-code-micro-bugfix-harness/docs/design.md"
INCIDENT_README_FILE="$ROOT_DIR/patterns/claude-code-incident-response-harness/README.md"
INCIDENT_DESIGN_FILE="$ROOT_DIR/patterns/claude-code-incident-response-harness/docs/design.md"
INCIDENT_STATE_TEMPLATE_FILE="$ROOT_DIR/patterns/claude-code-incident-response-harness/templates/incident-state.yaml"
ROOT_README_FILE="$ROOT_DIR/README.md"
PATTERNS_README_FILE="$ROOT_DIR/patterns/README.md"
HUMAN_GATE_POLICY_FILE="$ROOT_DIR/patterns/human-gate-policy.md"
CHANGE_INTENT_POLICY_FILE="$ROOT_DIR/patterns/change-intent-record.md"
DESIGN_INTENT_RESEARCH_FILE="$ROOT_DIR/research/ai-generated-code-design-intent-traceability.md"
TDD_SKILL_FILE="$ROOT_DIR/patterns/claude-code-development-harness/templates/skills/tdd-development/SKILL.md"
TDD_SKILL_AGENT_FILE="$ROOT_DIR/patterns/claude-code-development-harness/templates/skills/tdd-development/agents/openai.yaml"
TDD_UNIT_POLICY_FILE="$ROOT_DIR/patterns/claude-code-development-harness/templates/skills/tdd-development/references/unit-test-policy.md"
TDD_INTEGRATION_POLICY_FILE="$ROOT_DIR/patterns/claude-code-development-harness/templates/skills/tdd-development/references/integration-test-policy.md"
DEVELOPMENT_README_FILE="$ROOT_DIR/patterns/claude-code-development-harness/README.md"
DEVELOPMENT_AGENTS_DIR="$ROOT_DIR/patterns/claude-code-development-harness/templates/agents"
ERRORS=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  ERRORS=$((ERRORS + 1))
}

assert_line() {
  expected=$1
  file=$2
  message=$3
  if ! grep -Fxq -- "$expected" "$file"; then
    fail "$message"
  fi
}

assert_unique_line() {
  expected=$1
  file=$2
  message=$3
  count=$(grep -Fxc -- "$expected" "$file")
  if [ "$count" -ne 1 ]; then
    fail "$message: count=$count"
  fi
}

assert_key_once() {
  key=$1
  file=$2
  message=$3
  count=$(awk -F: -v key="$key" '
    {
      candidate = $1
      gsub(/^ +| +$/, "", candidate)
      if (candidate == key) count++
    }
    END { print count + 0 }
  ' "$file")
  if [ "$count" -ne 1 ]; then
    fail "$message: count=$count"
  fi
}

assert_contains() {
  expected=$1
  file=$2
  message=$3
  if ! grep -Fq -- "$expected" "$file"; then
    fail "$message"
  fi
}

assert_order_in_file() {
  file=$1
  first=$2
  second=$3
  message=$4
  if ! awk -v first="$first" -v second="$second" '
    $0 == first && !first_line { first_line = NR }
    $0 == second && !second_line { second_line = NR }
    END { exit !(first_line && second_line && first_line < second_line) }
  ' "$file"; then
    fail "$message"
  fi
}

assert_source_line() {
  expected=$1
  file=$2
  message=$3
  if ! awk -v expected="$expected" '
    $0 == "## 一次資料" { in_sources = 1; next }
    in_sources && /^## / { in_sources = 0 }
    in_sources && $0 == expected { found = 1 }
    END { exit !found }
  ' "$file"; then
    fail "$message"
  fi
}

for design_path in "$DESIGN_FILE" "$JIRA_DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE" "$INCIDENT_DESIGN_FILE"; do
  if [ ! -f "$design_path" ] || [ ! -r "$design_path" ] || [ -L "$design_path" ]; then
    printf '%s\n' "FAIL: 設計書が通常の読取り可能ファイルではない: $design_path" >&2
    exit 1
  fi
done

for required_path in "$JIRA_README_FILE" "$INCIDENT_README_FILE" "$INCIDENT_STATE_TEMPLATE_FILE" "$ROOT_README_FILE" "$PATTERNS_README_FILE" "$HUMAN_GATE_POLICY_FILE" "$CHANGE_INTENT_POLICY_FILE" "$DESIGN_INTENT_RESEARCH_FILE" "$TDD_SKILL_FILE" "$TDD_SKILL_AGENT_FILE" "$TDD_UNIT_POLICY_FILE" "$TDD_INTEGRATION_POLICY_FILE"; do
  if [ ! -f "$required_path" ] || [ ! -r "$required_path" ] || [ -L "$required_path" ]; then
    printf '%s\n' "FAIL: 必須文書が通常の読取り可能ファイルではない: $required_path" >&2
    exit 1
  fi
done

assert_line '- [TDD Development Skill雛形](templates/skills/tdd-development/SKILL.md)' "$ROOT_DIR/patterns/claude-code-development-harness/README.md" 'Development READMEにTDD Development Skill雛形へのリンクがない'
assert_line 'name: tdd-development' "$TDD_SKILL_FILE" 'TDD Development Skillのnameが不正'
assert_contains 'PHASE-6:tdd-generator' "$TDD_SKILL_FILE" 'TDD Development SkillにPHASE-6の許可pairがない'
assert_contains 'PHASE-7:tdd-generator' "$TDD_SKILL_FILE" 'TDD Development SkillにPHASE-7の許可pairがない'
assert_contains 'PHASE-8:integration-test-engineer' "$TDD_SKILL_FILE" 'TDD Development SkillにPHASE-8の許可pairがない'
assert_contains 'UNIT_TEST_RED' "$TDD_SKILL_FILE" 'TDD Development SkillにRED gate手順がない'
assert_contains 'POST_REFACTOR_GREEN' "$TDD_SKILL_FILE" 'TDD Development SkillにREFACTOR後のGREEN手順がない'
assert_contains 'production codeを変更しない' "$TDD_SKILL_FILE" 'TDD Development SkillにPHASE-8のproduction code保護がない'
assert_contains 'progress.yamlを直接更新しない' "$TDD_SKILL_FILE" 'TDD Development Skillにsingle-writer規則がない'
assert_line '- Before any test execution, verify that the command and every transitive executable or configuration it invokes passed the trusted harness audit.' "$TDD_SKILL_FILE" 'TDD Development Skillに推移的な実行対象の監査条件がない'
assert_line '- Invalidate that audit when build, test-harness, CI, dependency, or invoked configuration changes; block execution and gate evidence until an independent re-audit passes.' "$TDD_SKILL_FILE" 'TDD Development Skillに設定変更時の監査失効条件がない'
assert_line '5. Bind Integration Test evidence to the PHASE-8 result commit that contains the IT code. Record the PHASE-7 implementation target commit separately as the evaluated production-code baseline, and require the result commit to be its descendant.' "$TDD_SKILL_FILE" 'TDD Development SkillのPHASE-8証跡commit束縛が不正'
assert_line '3. If test-support configuration changes, require a new independent audit before execution and exclude all pre-audit results from `INTEGRATION_TEST` gate evidence.' "$TDD_INTEGRATION_POLICY_FILE" 'Integration Test Policyにテスト支援設定変更時の再監査がない'
assert_line '  display_name: "TDD Development"' "$TDD_SKILL_AGENT_FILE" 'TDD Development Skillのdisplay_nameが不正'
assert_contains '$tdd-development' "$TDD_SKILL_AGENT_FILE" 'TDD Development Skillのdefault promptにSkill名がない'

assert_contains '`integration_test_engineer_write_allowlist`' "$DESIGN_FILE" 'Integration Test Engineerのcanonical write allowlistが設計書にない'
assert_line '| integration-test-engineer | generator | PHASE-8 | tdd-development@1 | generator / `integration_test_engineer_write_allowlist`のみwrite |' "$DESIGN_FILE" 'AgentDefinitionがIntegration Test Engineerのcanonical write allowlistを参照していない'
assert_line '| Integration Test Engineer | `integration_test_engineer_write_allowlist` | test/container限定、ローカルスタブのみ | permissions＋接続先allowlist＋write allowlist検証 | 本番環境接続、production code・Unit Test・ビルド・CI・依存定義の変更 |' "$DESIGN_FILE" 'Permission BoundaryがIntegration Test Engineerのcanonical write allowlistと一致しない'
assert_line '  write_profile: integration_test_engineer_write_allowlist' "$DESIGN_FILE" 'PHASE-8 context manifestがcanonical write allowlistを参照していない'
assert_line '- `evaluated_code_commit`から`evaluated_commit`までの許可差分は、review targetと`docs/status/changes/<task>.yaml`の正確な2パスだけとする。' "$DESIGN_FILE" 'Evaluator入力checkpointのcommit境界allowlistがない'
assert_line '- 各`evaluation_step_input_commit`から対応する`evaluation_output_commit`までの許可差分は、当該Evaluatorが新規作成するreview結果とagent-runの正確な2パスだけとする。' "$DESIGN_FILE" 'Evaluator出力checkpointのcommit境界allowlistがない'
assert_line '  evaluation_input_commit: abc123def456' "$DESIGN_FILE" 'PhaseRun schemaにEvaluator入力checkpointがない'
assert_line '  evaluation_step_input_commit: abc123def456' "$DESIGN_FILE" 'Evaluator GateRun schemaにstep入力checkpointがない'
assert_line '  evaluation_output_commit: bcd234efa567' "$DESIGN_FILE" 'Evaluator GateRun schemaに出力checkpointがない'
assert_contains 'コードcommit系列の外にあるappend-only control-state store' "$DESIGN_FILE" 'control plane記録がコードcommitを進める自己参照を回避していない'
assert_contains 'Evaluatorごとに一つのstep' "$DESIGN_FILE" '複数Evaluatorの逐次checkpoint契約がない'
assert_contains '三境界' "$DEVELOPMENT_AGENTS_DIR/implementation-evaluator.md" 'Implementation Evaluatorが三境界契約を説明していない'
assert_contains 'evaluation_output_commit' "$DEVELOPMENT_AGENTS_DIR/development-orchestrator.md" 'Development OrchestratorがEvaluator出力checkpointを検証しない'
if ! awk '
  function finish_record() {
    if (is_target && found_commit && found_status) valid = 1
  }
  /^- gate_run_id:/ {
    finish_record()
    is_target = 0
    found_commit = 0
    found_status = 0
  }
  $0 == "  gate_definition: IMPLEMENTATION_REVIEW_TARGET" { is_target = 1 }
  is_target && $0 == "  evaluated_code_commit: 890xyz111222" { found_commit = 1 }
  is_target && $0 == "  status: passed" { found_status = 1 }
  END {
    finish_record()
    exit !valid
  }
' "$DESIGN_FILE"; then
  fail 'IMPLEMENTATION_REVIEW_TARGET GateRun例にevaluated_code_commitがない'
fi
assert_line '| Cross-cutting gate | `ACCESS_POLICY`は各AgentRun開始時、`STATE_REVISION`は各`progress.yaml`更新時に反復評価 | `ACCESS_POLICY`, `STATE_REVISION` |' "$DESIGN_FILE" 'cross-cutting gateの評価時点が詳細定義と一致しない'
assert_line '  document_consistency: failed' "$DESIGN_FILE" 'Version 1.10レビューが既知の文書不整合をpassedと誤記している'
assert_line '  known_document_consistency_failures:' "$DESIGN_FILE" 'Version 1.10レビューに既知の文書不整合が記録されていない'

assert_line '- [Integration Test Engineer Agent雛形](templates/agents/integration-test-engineer.md)' "$DEVELOPMENT_README_FILE" 'READMEにIntegration Test Engineer雛形リンクがない'
assert_line '- [Integration Test Reviewer Agent雛形](templates/agents/integration-test-reviewer.md)' "$DEVELOPMENT_README_FILE" 'READMEにIntegration Test Reviewer雛形リンクがない'
assert_line '- [UI Verifier Agent雛形](templates/agents/ui-verifier.md)' "$DEVELOPMENT_README_FILE" 'READMEにUI Verifier雛形リンクがない'

for precedence_agent in architect design-reviewer detailed-designer implementation-planner task-generator requirements-analyst requirements-planner requirements-reviewer architecture-planner plan-reviewer; do
  precedence_file="$DEVELOPMENT_AGENTS_DIR/$precedence_agent.md"
  assert_contains '最も具体的なpathを優先し、同一specificityで競合した場合だけdenyを優先する' "$precedence_file" "Agent雛形のwrite precedenceが不正: $precedence_agent"
done

for transition_file in "$DEVELOPMENT_AGENTS_DIR"/*.md; do
  if ! awk '
    $0 == "requested_gate_transition:" {
      if (in_transition && gate_count != 1) invalid = 1
      in_transition = 1
      gate_count = 0
      next
    }
    in_transition && /^[^[:space:]]/ {
      if (gate_count != 1) invalid = 1
      in_transition = 0
    }
    in_transition && /^[[:space:]]+gate_definition:/ { invalid = 1 }
    in_transition && /^[[:space:]]+gate:/ { gate_count++ }
    END {
      if (in_transition && gate_count != 1) invalid = 1
      exit invalid
    }
  ' "$transition_file"; then
    fail "requested_gate_transition schemaが不正: $transition_file"
  fi
done

assert_line 'input_revision: <current progress.yaml.revision>' "$DEVELOPMENT_AGENTS_DIR/context-builder.md" 'context manifestテンプレートにinput_revisionがない'
assert_contains 'Use this agent only when resuming work at PHASE-7' "$DEVELOPMENT_AGENTS_DIR/continuation.md" 'ContinuationのdescriptionがPHASE-7限定でない'
assert_line 'tools: Read, Grep, Glob, Write' "$DEVELOPMENT_AGENTS_DIR/continuation.md" 'ContinuationがBashを持つかtoolsが不正'
assert_contains 'docs/status/agent-runs/<current-task>/<new-run-id>.yaml' "$DEVELOPMENT_AGENTS_DIR/continuation.md" 'Continuationのagent-run write範囲がcurrent task/run一点に限定されていない'
assert_contains '既存ファイルへのWriteを拒否する（create-only）' "$DEVELOPMENT_AGENTS_DIR/continuation.md" 'Continuationのagent-runがcreate-onlyでない'
assert_contains '一つの作業単位を選定し、TDD Generatorへの次アクション' "$DEVELOPMENT_AGENTS_DIR/continuation.md" 'Continuationの完了条件が制御層の責務と一致しない'
assert_contains 'test_support_configuration_changed:' "$DEVELOPMENT_AGENTS_DIR/integration-test-engineer.md" 'Integration Test Engineerのagent-runにテスト支援設定変更宣言がない'
assert_contains 'independent_reaudit_status:' "$DEVELOPMENT_AGENTS_DIR/integration-test-engineer.md" 'Integration Test Engineerのagent-runに独立再監査statusがない'
assert_contains '独立再監査がPASSするまでITを実行しない' "$DEVELOPMENT_AGENTS_DIR/integration-test-engineer.md" 'Integration Test Engineerの実行手順に再監査停止条件がない'
assert_contains 'raw logを作成しない' "$DEVELOPMENT_AGENTS_DIR/integration-test-engineer.md" 'Integration Test Engineerがstdout/stderr captureを信頼済みRunnerへ移管していない'
if grep -Fq '<run-id>.stdout.redacted.log' "$DEVELOPMENT_AGENTS_DIR/integration-test-engineer.md" || grep -Fq '<run-id>.stderr.redacted.log' "$DEVELOPMENT_AGENTS_DIR/integration-test-engineer.md"; then
  fail 'Integration Test Engineerがallowlist外のローカルlogを書き込むschemaを持つ'
fi

if awk '
  previous ~ /^>/ && $0 == "" { quoted_then_blank = 1; next }
  quoted_then_blank && /^>/ { exit 1 }
  { quoted_then_blank = 0; previous = $0 }
' "$DEVELOPMENT_AGENTS_DIR/implementation-evaluator.md"; then
  :
else
  fail 'Implementation EvaluatorにMD028違反の連続blockquote間空行がある'
fi
if ! awk '
  /^```[^`]+$/ { in_fence = 1; next }
  /^```$/ {
    if (!in_fence) error = 1
    in_fence = 0
  }
  END { exit (error || in_fence) }
' "$DEVELOPMENT_AGENTS_DIR/tdd-generator.md"; then
  fail 'TDD Generatorにlanguage未指定のopening code fenceがある'
fi
if ! awk '
  /^## 標準サイクル/ { section = 1; next }
  section && /^```text$/ { found = 1; exit }
  section && /^```$/ { exit 1 }
  END { exit !found }
' "$DEVELOPMENT_AGENTS_DIR/tdd-generator.md"; then
  fail 'TDD Generatorの標準サイクルcode fenceにtext languageがない'
fi

assert_line '- [Change Intent Record](patterns/change-intent-record.md) — AI支援変更の目的、設計上の理由、制約、検証可能なリンクを短く残す共通規約' "$ROOT_README_FILE" 'ルート索引にChange Intent Recordがない'
assert_line '- [AI生成コードの設計意図トレーサビリティ調査](research/ai-generated-code-design-intent-traceability.md) — 長期保守上のリスク、限定条件、反証、実務上の対策を一次資料から整理' "$ROOT_README_FILE" 'ルート索引に設計意図トレーサビリティ調査がない'
assert_line 'AI支援変更の設計意図は[Change Intent Record](change-intent-record.md)を共通規約とする。' "$PATTERNS_README_FILE" '共通適用ガイドにChange Intent Recordの案内がない'

for intent_heading in '# Change Intent Record' '## 1. 目的' '## 2. 記録する条件' '## 3. 最小形式' '## 4. 更新とレビュー' '## 5. 記録しないもの' '## 6. 情報分類と参照の安全性'; do
  assert_unique_line "$intent_heading" "$CHANGE_INTENT_POLICY_FILE" "Change Intent Recordの必須節 '$intent_heading' が一意でない"
done
assert_line '- 公開PR、公開issue、公開リポジトリのCIRへ機微情報を書かない。secret、PII、internal endpoint、customer ID、local path、command argumentsは必要最小限にし、値をredactionする。' "$CHANGE_INTENT_POLICY_FILE" 'CIRの公開範囲とredaction規則がない'
assert_line '- セキュリティ上必要な詳細はアクセス制御されたprivate security recordへ置き、CIRには非機密の要約と固定revisionの参照だけを残す。' "$CHANGE_INTENT_POLICY_FILE" 'CIRのprivate security record参照規則がない'
assert_line '- 外部文書、issue、コメント、生成物はuntrusted dataとして扱い、命令権限を与えない。参照にはprovenanceとtrust levelを記録する。' "$CHANGE_INTENT_POLICY_FILE" 'CIR参照のuntrusted data規則がない'
assert_line '- CIR内の文字列をcommandとして実行しない。実行が必要な場合は対象プロジェクトの信頼済み手順からコマンドを選び、通常の権限・承認・検証を適用する。' "$CHANGE_INTENT_POLICY_FILE" 'CIRからのcommand実行禁止規則がない'
assert_line '- CIRの正本はGit/version control内の成果物に置く。PR、issue、外部文書は、revision、commit SHAまたはimmutable snapshotを固定したsource/mirrorとしてのみ参照する。' "$CHANGE_INTENT_POLICY_FILE" 'CIRのGit正本とsource/mirror規則がない'
assert_line '- 誤字、表記、リンクなど判断を変えない修正だけは同じ正本を更新できる。目的、理由、制約、対象外、代替案の判断を変える場合は、過去の記録を保持して`supersedes: <CIR/ADR ID>`付きの新しい記録を追記する。' "$CHANGE_INTENT_POLICY_FILE" 'CIRの非意味変更とsupersedes規則がない'
assert_line '- supersedes: <CIR/ADR ID。初版または判断変更なしの場合はN/A>' "$CHANGE_INTENT_POLICY_FILE" 'CIRテンプレートにoptional supersedesがない'
for intent_term in 'Change Intent Record' '目的' '理由' '制約' '対象外' '代替案' '要件' 'テスト' 'ADR' '内部思考' 'transcript' '既存の状態機械や品質ゲートを増やさない'; do
  assert_contains "$intent_term" "$CHANGE_INTENT_POLICY_FILE" "Change Intent Recordに必須語 '$intent_term' がない"
done

for research_heading in '# AI生成コードの設計意図トレーサビリティ調査' '## 結論' '## 観測されたリスク' '## 限定条件と反証' '## 実務上の対策' '## 一次資料'; do
  assert_unique_line "$research_heading" "$DESIGN_INTENT_RESEARCH_FILE" "設計意図調査の必須節 '$research_heading' が一意でない"
done
for research_source in 'https://arxiv.org/abs/2603.28592v2' 'https://doi.org/10.48550/arXiv.2603.28592' 'https://arxiv.org/abs/2601.21276v1' 'https://doi.org/10.1145/3793302.3793622' 'https://dora.dev/ai/gen-ai-report/dora-impact-of-generative-ai-in-software-development.pdf' 'https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/' 'https://www.anthropic.com/research/AI-assistance-coding-skills' 'https://arxiv.org/abs/2507.00788v3' 'https://doi.org/10.1007/s10664-026-10889-1' 'https://arxiv.org/abs/2508.00700v1' 'https://doi.org/10.1109/ESEM64174.2025.00036' 'https://www.microsoft.com/en-us/research/publication/the-impact-of-generative-ai-on-critical-thinking-self-reported-reductions-in-cognitive-effort-and-confidence-effects-from-a-survey-of-knowledge-workers/' 'https://doi.org/10.1145/3706598.3713778' 'https://google.github.io/eng-practices/review/developer/small-cls.html' 'https://docs.github.com/en/copilot/responsible-use/agents' 'https://google.github.io/eng-practices/review/developer/handling-comments.html' 'https://google.github.io/eng-practices/review/reviewer/looking-for.html'; do
  if ! awk -v source="$research_source" '
    $0 == "## 一次資料" { in_sources = 1; next }
    in_sources && /^## / { in_sources = 0 }
    in_sources && index($0, source) { found = 1 }
    END { exit !found }
  ' "$DESIGN_INTENT_RESEARCH_FILE"; then
    fail "設計意図調査の一次資料節にURL '$research_source' がない"
  fi
done
assert_source_line '- [Technical-debt study (arXiv:2603.28592v2)](https://arxiv.org/abs/2603.28592v2) / [DOI](https://doi.org/10.48550/arXiv.2603.28592) — AI生成コードと技術的負債を扱う2026年のpreprint。査読状況と測定範囲を限定して解釈する。版: v2（2026-04-26）。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" '2603研究の固定版・DOI・参照日が不正'
assert_source_line '- [Code-redundancy study (arXiv:2601.21276v1)](https://arxiv.org/abs/2601.21276v1) / [DOI](https://doi.org/10.1145/3793302.3793622) — AI支援とコードの冗長性・重複を扱い、MSR 2026に採録された研究。版: v1。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" '2601研究の固定版・DOI・参照日が不正'
assert_source_line '- [DORA Impact of Generative AI in Software Development](https://dora.dev/ai/gen-ai-report/dora-impact-of-generative-ai-in-software-development.pdf) — 開発成果との関連を扱う調査報告。観察的な関連を因果効果とみなさない。版: 2025.2。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'DORAの版・参照日が不正'
assert_source_line '- [METR: Early-2025 AI experienced OSS developer study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) — 経験豊富なOSS開発者を対象にした無作為化比較研究。公開日: 2025-07-10。著者がout of dateと明記したhistorical snapshotであり、対象とツール時点に限定がある。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'METRの公開日・historical snapshot・参照日が不正'
assert_source_line '- [Anthropic: AI assistance and coding skills](https://www.anthropic.com/research/AI-assistance-coding-skills) — AI支援と技能形成の無作為化研究。短期の学習課題という限定がある。公開日: 2026-01-29。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'Anthropicの公開日・参照日が不正'
assert_source_line '- [Counterevidence study (arXiv:2507.00788v3)](https://arxiv.org/abs/2507.00788v3) / [DOI](https://doi.org/10.1007/s10664-026-10889-1) — AI支援の肯定的効果を含む査読済み研究（初稿2025年）。実験条件外へ一般化しない。版: v3。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" '2507研究の査読状態・固定版・DOI・参照日が不正'
assert_source_line '- [Maintainability-related study (arXiv:2508.00700v1)](https://arxiv.org/abs/2508.00700v1) / [DOI](https://doi.org/10.1109/ESEM64174.2025.00036) — AI生成コードの品質・保守性を扱い、ESEM 2025に採録された研究。評価指標と対象範囲に依存する。版: v1。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" '2508研究の採録情報・固定版・DOI・参照日が不正'
assert_source_line '- [Microsoft Research: The Impact of Generative AI on Critical Thinking](https://www.microsoft.com/en-us/research/publication/the-impact-of-generative-ai-on-critical-thinking-self-reported-reductions-in-cognitive-effort-and-confidence-effects-from-a-survey-of-knowledge-workers/) / [DOI](https://doi.org/10.1145/3706598.3713778) — 知識労働者の自己申告調査。客観的コード品質や因果関係の測定ではない。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'Microsoft研究のDOI・参照日が不正'
assert_source_line '- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html) — 小さく自己完結した変更を推奨するレビュー実務。公開日なし。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'Small CLsの公開日注記・参照日が不正'
assert_source_line '- [GitHub Copilot coding agent responsible use](https://docs.github.com/en/copilot/responsible-use/agents) — 生成結果を利用者がレビューし、検証する責任を明記する公式文書。公開日なし。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'GitHub文書の公開日注記・参照日が不正'
assert_source_line '- [Google Engineering Practices: Handling reviewer comments](https://google.github.io/eng-practices/review/developer/handling-comments.html) — コメントの理解、合意、修正を扱う実務指針。公開日なし。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'Handling commentsの公開日注記・参照日が不正'
assert_source_line '- [Google Engineering Practices: What to look for in a code review](https://google.github.io/eng-practices/review/reviewer/looking-for.html) — 設計、複雑性、テスト、コメント等を確認するレビュー指針。公開日なし。参照日: 2026-07-15。' "$DESIGN_INTENT_RESEARCH_FILE" 'Review checklistの公開日注記・参照日が不正'
assert_contains 'preprint' "$DESIGN_INTENT_RESEARCH_FILE" '設計意図調査にpreprintの限定がない'
assert_contains '因果関係' "$DESIGN_INTENT_RESEARCH_FILE" '設計意図調査に因果関係の限定がない'
assert_contains '反証' "$DESIGN_INTENT_RESEARCH_FILE" '設計意図調査に反証がない'
assert_line '- 2026年のコード重複に関する研究は、生成AI利用と冗長・重複コードの関係を報告し、MSR 2026に採録されている。モデル、言語、リポジトリ特性への一般化には注意が必要である。' "$DESIGN_INTENT_RESEARCH_FILE" 'コード重複研究のMSR 2026採録情報が不正確'
assert_line '独立Reviewerに加え、その変更に責任を持つ人間がコード、テスト、設計意図の一致をレビューする。AI/LLM Reviewerの説明またはPASSだけで完了としない。' "$DESIGN_INTENT_RESEARCH_FILE" '設計意図調査の独立Reviewerと責任ある人間の関係が不明確'
assert_line '- AI支援が常に保守性を悪化させるわけではない。2025年に初稿が公開された研究には、限定された課題・評価条件で品質または保守性の改善を報告する査読済み研究もある。' "$DESIGN_INTENT_RESEARCH_FILE" '反証研究の査読状態が古い'

for intent_readme in "$ROOT_DIR/patterns/claude-code-development-harness/README.md" "$ROOT_DIR/patterns/claude-code-lightweight-feature-harness/README.md" "$ROOT_DIR/patterns/claude-code-micro-bugfix-harness/README.md"; do
  assert_contains 'Change Intent Record' "$intent_readme" "READMEからChange Intent Recordを参照していない: $intent_readme"
  assert_line 'Human Review Evidenceは認証済みreview provider、protected branch approvalまたはsigned attestationからread-onlyで取得し、Git内の自己申告を承認根拠にしない。' "$intent_readme" "READMEに認証済みHuman Review Evidenceの規則がない: $intent_readme"
done
for intent_design in "$DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE"; do
  assert_contains 'Change Intent Record' "$intent_design" "設計書からChange Intent Recordを参照していない: $intent_design"
  assert_contains '内部思考' "$intent_design" "設計書に内部思考を保存しない規則がない: $intent_design"
  assert_line '- AI/LLM ReviewerのPASSは補助証拠に限る。変更を理解した人間Reviewerがコード、テスト、設計意図の一致を確認するまで完了としない。' "$intent_design" "設計書に人間レビューの完了条件がない: $intent_design"
  assert_line '- Human Review EvidenceはGit内の自己申告を権威として扱わず、authenticated review provider、protected branch approvalまたはtrusted keyによるsigned attestationからread-onlyで取得する。' "$intent_design" "Human Review Evidenceの権威ある取得元がない: $intent_design"
  assert_line '- AI/LLM、Implementer、レビュー対象を変更できるworkloadにはHuman Review Evidenceの発行・更新・失効権限またはprovider credentialを与えない。' "$intent_design" "Human Review Evidenceの発行権限分離がない: $intent_design"
  assert_line '- 必須fieldは`issuer`、PIIを複製しないopaqueな`stable_subject_id`、`verdict`、`issued_at`、排他的な`target`、およびimmutable evidence URLと`revision`の組または信頼済み`signature`とする。' "$intent_design" "Human Review Evidenceの必須fieldが不十分: $intent_design"
  assert_line '- committed targetは完全な40桁または64桁hexの`commit_oid`だけを持つ。uncommitted targetは完全な40桁または64桁hexの`base_oid`と、canonical diff bytesの`sha256:<64hex>`である`diff_hash`を持ち、必要なら`manifest_hash`も束縛する。両形態のfieldが混在または欠落した証跡は拒否する。' "$intent_design" "Human Review Evidenceのtarget排他schemaがない: $intent_design"
  assert_line '- canonical diff bytesは信頼済みRunnerが固定`base_oid`と対象manifestから、external diffとtextconvを無効化し、full-index、binaryを含む決定論的なpath順で生成する。対象のtracked、staged、unstaged、意図したuntracked fileをmanifestへ列挙し、同じbytesをReviewerと検証側でhashする。' "$intent_design" "Uncommitted targetのcanonical diff規則がない: $intent_design"
  assert_line '- Runnerはprovider APIの認証結果またはsignatureを検証し、issuer、subjectのrole binding、verdict、target、issued_at、evidence revisionを現在対象と照合する。取得不能、形式不正、不一致、未認証はfail-closedとする。' "$intent_design" "Human Review Evidenceのfail-closed検証がない: $intent_design"
  assert_line '- blocking修正または対象変更時は旧attestation本体を変更せずappend-onlyの失効eventを記録し、新対象に束縛されたHuman Review Evidenceを権威ある発行元から再発行する。' "$intent_design" "Human Review Evidenceのappend-only失効・再発行規則がない: $intent_design"
  assert_line '- Human Review Evidenceは品質上の完了条件であり、操作を許可するHuman Gateや新しいgate/stateを追加するものではない。' "$intent_design" "設計書でHuman Review EvidenceとHuman Gateを分離していない: $intent_design"
  assert_unique_line '### Committed target例' "$intent_design" "Committed Human Review Evidence例が一意でない: $intent_design"
  assert_unique_line '### Uncommitted target例' "$intent_design" "Uncommitted Human Review Evidence例が一意でない: $intent_design"
  assert_contains 'commit_oid: 0123456789abcdef0123456789abcdef01234567' "$intent_design" "Committed targetに完全OID例がない: $intent_design"
  assert_contains 'base_oid: 0123456789abcdef0123456789abcdef01234567' "$intent_design" "Uncommitted targetに完全base OID例がない: $intent_design"
  assert_contains 'diff_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$intent_design" "Uncommitted targetにcanonical diff hash例がない: $intent_design"
done

for intent_surface in "$ROOT_DIR/patterns/claude-code-development-harness/README.md" "$DESIGN_FILE" "$ROOT_DIR/patterns/claude-code-lightweight-feature-harness/README.md" "$LIGHTWEIGHT_DESIGN_FILE" "$ROOT_DIR/patterns/claude-code-micro-bugfix-harness/README.md" "$MICRO_DESIGN_FILE"; do
  assert_line '非自明な設計意図の正本はGit/version control内の既存成果物へ置き、PR、issue、外部文書は固定revision、commit SHAまたはimmutable snapshot付きのsource/mirrorとしてのみ参照する。' "$intent_surface" "CIR正本の配置規則が統一されていない: $intent_surface"
done

assert_line '| Human Reviewer | 固定されたコード、テスト、設計意図を理解し、責任ある人間として一致を判定 | AI/LLM ReviewerのPASSを承認根拠として代用しない |' "$DESIGN_FILE" 'Development ActorにHuman Reviewerがない'
assert_line 'Human Reviewerは`AgentDefinition`ではなく、tool権限を持たない人間Actorとする。権威ある判定は認証済みproviderまたはsigned attestationへ発行し、OrchestratorとRunnerはread-onlyで取得する。Git内にはopaqueな参照と検証結果だけを保存できるが、自己申告を承認根拠にしない。' "$DESIGN_FILE" 'DevelopmentでHuman Reviewerと証跡発行権限が分離されていない'
assert_line '| `PHASE-9` コード・セキュリティ・人間レビュー | code-review-target, test-evidence, ui-evidence-or-na | code-review, security-review, human-review-evidence-ref | `CODE_REVIEW_TARGET` | `CODE_REVIEW` | code-reviewer, security-reviewer, context-builder |' "$DESIGN_FILE" 'PHASE-9成果物にhuman review evidence refがない'
assert_line '| CODE_REVIEW | Code ReviewerとSecurity Reviewerのblocking指摘ゼロ、認証済みHuman Review Evidenceのtargetが現在対象と一致し、責任ある人間のverdictがapproved | 実装 |' "$DESIGN_FILE" 'CODE_REVIEWに認証済みHuman Review Evidenceがない'
assert_line '| COMPLETION          | 全要件・受入条件・テスト・文書と有効なHuman Review Evidenceが完了 | 該当工程               |' "$DESIGN_FILE" 'COMPLETIONにHuman Review Evidenceがない'
assert_line '- provider APIまたはsignatureで検証済みのHuman Review Evidenceが現在対象へ束縛され、責任ある人間Reviewerのverdictが`approved`である。' "$DESIGN_FILE" 'Development DoDに認証済みHuman Review Evidenceがない'
assert_line '  human_review_evidence_valid: true' "$DESIGN_FILE" '付録BにHuman Review Evidence有効性がない'
assert_line '  human_review_target_matches: true' "$DESIGN_FILE" '付録BにHuman Review Evidence対象一致がない'
assert_line '  human_review_approved: true' "$DESIGN_FILE" '付録BにHuman Review approved条件がない'
for handoff_design in "$DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE"; do
  assert_line '- Handoffには権威ある発行元のimmutable evidence URLとrevisionまたはsignature、stable subject ID、target、verdict、issued_at、およびRunnerの検証結果を含める。Git内の自己申告で代用しない。' "$handoff_design" "Handoffに認証済みHuman Review Evidenceがない: $handoff_design"
done
assert_line '- Responsible Human Reviewer、Human Review Evidence' "$ROOT_DIR/patterns/claude-code-development-harness/README.md" 'Development READMEに責任ある人間レビューがない'
assert_line '6. **2軸Review + Human Review:** `code-reviewer`が正確性・回帰を、`security-reviewer`が入力・権限・秘密情報を独立に確認する。blocking指摘の解消後、責任ある人間Reviewerが固定差分、テスト、設計意図を理解して承認する。' "$ROOT_DIR/patterns/claude-code-lightweight-feature-harness/README.md" 'Lightweight READMEのレビュー完了条件が古い'
assert_line '7. **Handoff:** 変更概要、変更ファイル、検証コマンドと終了コード、レビュー結果、Human Review Evidence、残課題を最終回答にまとめる。' "$ROOT_DIR/patterns/claude-code-lightweight-feature-harness/README.md" 'Lightweight READMEのHandoff証跡が不足'
assert_line '6. **2軸Review + Human Review:** `code-reviewer`が正確性と回帰を、`security-reviewer`が脆弱性と権限拡大を独立に確認する。blocking指摘の解消後、責任ある人間Reviewerが固定差分、テスト、設計意図を理解して承認する。' "$ROOT_DIR/patterns/claude-code-micro-bugfix-harness/README.md" 'Micro READMEのレビュー完了条件が古い'
assert_line '7. **Report:** 根本原因、変更ファイル、RED/GREENを含む検証証跡、レビュー結果、Human Review Evidence、残課題を最終回答にまとめる。' "$ROOT_DIR/patterns/claude-code-micro-bugfix-harness/README.md" 'Micro READMEのReport証跡が不足'
assert_line '| 2軸Review | 正確性とセキュリティを別観点で評価 | blocking指摘が0件、Human Review Evidenceがvalid、target一致、verdictがapproved |' "$LIGHTWEIGHT_DESIGN_FILE" 'Lightweight Review終了条件にHuman Review Evidenceがない'
assert_line '| 2軸Review | 正確性とセキュリティを独立評価 | blocking指摘が0件、Human Review Evidenceがvalid、target一致、verdictがapproved |' "$MICRO_DESIGN_FILE" 'Micro Review終了条件にHuman Review Evidenceがない'

TMP_BASE=${TMPDIR:-/tmp}
WORK_DIR=$(mktemp -d "$TMP_BASE/doc-consistency.XXXXXX") || exit 1
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

PHASES_FILE="$WORK_DIR/phases"
AGENTS_FILE="$WORK_DIR/agents"
QUALITY_FILE="$WORK_DIR/quality-gates"
STATE_FILE="$WORK_DIR/state-gates"
DIRECTORY_AGENTS_FILE="$WORK_DIR/directory-agents"
UNIT_TEST_GREEN_GATE_FILE="$WORK_DIR/unit-test-green-gate"
IMPLEMENTATION_GATE_SECTION_FILE="$WORK_DIR/implementation-gate-section"
IMPLEMENTATION_REVIEW_TARGET_FILE="$WORK_DIR/implementation-review-target"
JIRA_DEVELOPMENT_OUTBOX_FILE="$WORK_DIR/jira-development-outbox.yaml"
JIRA_INCIDENT_OUTBOX_FILE="$WORK_DIR/jira-incident-outbox.yaml"

evidence_index=0
for evidence_design in "$DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE"; do
  evidence_index=$((evidence_index + 1))
  committed_example="$WORK_DIR/human-review-committed-$evidence_index.yaml"
  uncommitted_example="$WORK_DIR/human-review-uncommitted-$evidence_index.yaml"
  awk '
    /^### Committed target例$/ { section = 1; next }
    section && /^```yaml$/ { yaml = 1; next }
    yaml && /^```$/ { exit }
    yaml { print }
  ' "$evidence_design" > "$committed_example"
  awk '
    /^### Uncommitted target例$/ { section = 1; next }
    section && /^```yaml$/ { yaml = 1; next }
    yaml && /^```$/ { exit }
    yaml { print }
  ' "$evidence_design" > "$uncommitted_example"
  if ! ruby -ryaml -rtime -e '
    expected_kind = ARGV.shift
    data = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
    evidence = data.fetch("human_review_evidence")
    %w[issuer stable_subject_id verdict target issued_at].each do |key|
      raise "missing #{key}" unless evidence[key].is_a?(String) && !evidence[key].empty? || key == "target" && evidence[key].is_a?(Hash)
    end
    raise "verdict must be approved" unless evidence["verdict"] == "approved"
    raise "stable_subject_id must be opaque" if evidence["stable_subject_id"].match?(/[@[:space:]]/)
    Time.iso8601(evidence["issued_at"])
    target = evidence["target"]
    raise "target kind mismatch" unless target["kind"] == expected_kind
    oid = /\A[0-9a-f]{40}([0-9a-f]{24})?\z/
    if expected_kind == "committed"
      raise "committed target fields invalid" unless target.keys.sort == %w[commit_oid kind] && target["commit_oid"].match?(oid)
    else
      required = %w[kind base_oid diff_hash]
      allowed = required + %w[manifest_hash]
      raise "uncommitted target fields invalid" unless (required - target.keys).empty? && (target.keys - allowed).empty?
      raise "base_oid invalid" unless target["base_oid"].match?(oid)
      raise "diff_hash invalid" unless target["diff_hash"].match?(/\Asha256:[0-9a-f]{64}\z/)
      if target["manifest_hash"]
        raise "manifest_hash invalid" unless target["manifest_hash"].match?(/\Asha256:[0-9a-f]{64}\z/)
      end
    end
    authentication_valid = lambda do |candidate|
      url_present = candidate.key?("evidence_url")
      revision_present = candidate.key?("revision")
      signature_present = candidate.key?("signature")
      complete_pair = url_present && revision_present &&
        candidate["evidence_url"].is_a?(String) && candidate["evidence_url"].start_with?("https://") &&
        candidate["revision"].is_a?(String) && !candidate["revision"].empty?
      standalone_signature = signature_present && !url_present && !revision_present &&
        candidate["signature"].is_a?(String) && !candidate["signature"].empty?
      complete_pair && !signature_present || standalone_signature
    end
    raise "complete URL/revision pair XOR standalone signature required" unless authentication_valid.call(evidence)
    negative_authentication_forms = [
      { "evidence_url" => "https://review.example.invalid/evidence" },
      { "revision" => "revision-1" },
      { "evidence_url" => "https://review.example.invalid/evidence", "signature" => "sig:invalid" },
      { "revision" => "revision-1", "signature" => "sig:invalid" },
      { "evidence_url" => "https://review.example.invalid/evidence", "revision" => "revision-1", "signature" => "sig:invalid" }
    ]
    raise "negative authentication form accepted" if negative_authentication_forms.any? { |candidate| authentication_valid.call(candidate) }
  ' committed "$committed_example"; then
    fail "Committed Human Review Evidence例のschemaが不正: $evidence_design"
  fi
  if ! ruby -ryaml -rtime -e '
    expected_kind = ARGV.shift
    data = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
    evidence = data.fetch("human_review_evidence")
    %w[issuer stable_subject_id verdict target issued_at].each do |key|
      raise "missing #{key}" unless evidence[key].is_a?(String) && !evidence[key].empty? || key == "target" && evidence[key].is_a?(Hash)
    end
    raise "verdict must be approved" unless evidence["verdict"] == "approved"
    raise "stable_subject_id must be opaque" if evidence["stable_subject_id"].match?(/[@[:space:]]/)
    Time.iso8601(evidence["issued_at"])
    target = evidence["target"]
    raise "target kind mismatch" unless target["kind"] == expected_kind
    oid = /\A[0-9a-f]{40}([0-9a-f]{24})?\z/
    required = %w[kind base_oid diff_hash]
    allowed = required + %w[manifest_hash]
    raise "uncommitted target fields invalid" unless (required - target.keys).empty? && (target.keys - allowed).empty?
    raise "base_oid invalid" unless target["base_oid"].match?(oid)
    raise "diff_hash invalid" unless target["diff_hash"].match?(/\Asha256:[0-9a-f]{64}\z/)
    if target["manifest_hash"]
      raise "manifest_hash invalid" unless target["manifest_hash"].match?(/\Asha256:[0-9a-f]{64}\z/)
    end
    authentication_valid = lambda do |candidate|
      url_present = candidate.key?("evidence_url")
      revision_present = candidate.key?("revision")
      signature_present = candidate.key?("signature")
      complete_pair = url_present && revision_present &&
        candidate["evidence_url"].is_a?(String) && candidate["evidence_url"].start_with?("https://") &&
        candidate["revision"].is_a?(String) && !candidate["revision"].empty?
      standalone_signature = signature_present && !url_present && !revision_present &&
        candidate["signature"].is_a?(String) && !candidate["signature"].empty?
      complete_pair && !signature_present || standalone_signature
    end
    raise "complete URL/revision pair XOR standalone signature required" unless authentication_valid.call(evidence)
    negative_authentication_forms = [
      { "evidence_url" => "https://review.example.invalid/evidence" },
      { "revision" => "revision-1" },
      { "evidence_url" => "https://review.example.invalid/evidence", "signature" => "sig:invalid" },
      { "revision" => "revision-1", "signature" => "sig:invalid" },
      { "evidence_url" => "https://review.example.invalid/evidence", "revision" => "revision-1", "signature" => "sig:invalid" }
    ]
    raise "negative authentication form accepted" if negative_authentication_forms.any? { |candidate| authentication_valid.call(candidate) }
  ' uncommitted "$uncommitted_example"; then
    fail "Uncommitted Human Review Evidence例のschemaが不正: $evidence_design"
  fi
done

assert_unique_line '## 6.5 REFACTOR Gate' "$DESIGN_FILE" 'Development REFACTOR節が一意でない'
assert_unique_line '## 6.1 標準サイクル' "$DESIGN_FILE" 'Development標準サイクル節が一意でない'
assert_unique_line '## 6.6 Implementation Evaluation Gate' "$DESIGN_FILE" 'Development Implementation Evaluation節が一意でない'
assert_unique_line '# 7. Integration Test方針' "$DESIGN_FILE" 'Development Integration Test節が一意でない'
assert_unique_line '# docs/status/gate-runs/gate-run-TASK-004-unit-test-green-007.yaml' "$DESIGN_FILE" 'UNIT_TEST_GREEN GateRun例が一意でない'
assert_unique_line '# docs/features/order/reviews/targets/TASK-004-implementation.yaml' "$DESIGN_FILE" 'IMPLEMENTATION_REVIEW_TARGET schema例が一意でない'
assert_unique_line '### TDDと検証証跡' "$LIGHTWEIGHT_DESIGN_FILE" 'Lightweight TDD節が一意でない'
assert_unique_line '## 4. TDDと最小修正' "$MICRO_DESIGN_FILE" 'Micro TDD節が一意でない'
assert_unique_line '## 1. 適用範囲' "$INCIDENT_DESIGN_FILE" 'Incident適用範囲節が一意でない'
assert_unique_line '## 2. 役割とsingle-writer' "$INCIDENT_DESIGN_FILE" 'Incident役割節が一意でない'
assert_unique_line '## 3. 対応フロー' "$INCIDENT_DESIGN_FILE" 'Incident対応フロー節が一意でない'
assert_unique_line '## 4. 本番操作ガードレール' "$INCIDENT_DESIGN_FILE" 'Incidentガードレール節が一意でない'
assert_unique_line '## 5. 再試行ポリシー' "$INCIDENT_DESIGN_FILE" 'Incident再試行節が一意でない'
assert_unique_line '## 6. 記録・監査・秘密情報' "$INCIDENT_DESIGN_FILE" 'Incident監査節が一意でない'
assert_unique_line '## 7. 状態ファイル' "$INCIDENT_DESIGN_FILE" 'Incident状態節が一意でない'
assert_unique_line '## 8. Handoffと事後分析' "$INCIDENT_DESIGN_FILE" 'Incident handoff節が一意でない'
assert_unique_line '## 3. Jira受付・同期エンベロープ' "$JIRA_DESIGN_FILE" 'Jira受付・同期節が一意でない'
assert_unique_line '## 4. TicketSnapshotとDefinition of Ready' "$JIRA_DESIGN_FILE" 'Jira TicketSnapshot節が一意でない'
assert_unique_line '## 5. Lease・revision・状態同期' "$JIRA_DESIGN_FILE" 'Jira排他・同期節が一意でない'
assert_unique_line '## 6. ルーティング' "$JIRA_DESIGN_FILE" 'Jiraルーティング節が一意でない'
assert_unique_line '## 7. Jira書戻し' "$JIRA_DESIGN_FILE" 'Jira書戻し節が一意でない'
assert_unique_line '## 8. 権限・不信頼入力・秘密情報' "$JIRA_DESIGN_FILE" 'Jiraセキュリティ節が一意でない'
assert_unique_line '## 9. 失敗処理と再開' "$JIRA_DESIGN_FILE" 'Jira失敗処理節が一意でない'
assert_unique_line '### 4.2 Incident Readiness Gate' "$JIRA_DESIGN_FILE" 'Incident専用readiness gate節が一意でない'

assert_line '- [Claude Code Jira Ticket Harness](patterns/claude-code-jira-ticket-harness/README.md) — Jiraチケットを安全に取り込み、適切な開発ハーネスへ振り分け、証跡をJiraへ冪等に書き戻すパターン' "$ROOT_README_FILE" 'ルート索引にJira Ticket Harnessがない'
assert_line 'Jiraを受付・同期の制御レイヤとして使う場合は、[Jira Ticket Harness](claude-code-jira-ticket-harness/README.md)でチケットを正規化し、作業の規模とリスクに応じて既存の4方式へ振り分ける。' "$PATTERNS_README_FILE" '共通適用ガイドにJira Ticket Harnessの案内がない'
assert_line '- [Claude Code Incident Response Harness](patterns/claude-code-incident-response-harness/README.md) — 本番サービス障害を、明示承認、single-writer、構造化記録、復旧検証で安全に収束させるパターン' "$ROOT_README_FILE" 'ルート索引にIncident Harnessがない'
assert_line '- [Human Gate Policy](patterns/human-gate-policy.md) — 全ハーネス共通のリスク階層、承認対象、Decision Packet、失効、役割分離を定めるポリシー' "$ROOT_README_FILE" 'ルート索引にHuman Gate Policyがない'
assert_line '| 主用途 | 原因が特定できる局所バグ | 受入条件が確定した小機能 | 要件・設計を含む開発 | 本番サービス障害の収束 |' "$PATTERNS_README_FILE" '比較表にIncident Harnessの主用途がない'
assert_line '共通の人間承認ルールは[Human Gate Policy](human-gate-policy.md)を正本とする。' "$PATTERNS_README_FILE" '共通適用ガイドにHuman Gate Policyの案内がない'

for human_gate_heading in '# Human Gate Policy' '## 2. リスク階層' '## 3. 必須ヒューマンゲート' '## 4. Decision Packet' '## 5. 承認の有効性と失効' '## 6. 役割分離と監査' '## 7. 運用評価'; do
  assert_unique_line "$human_gate_heading" "$HUMAN_GATE_POLICY_FILE" "Human Gate Policyの必須節 '$human_gate_heading' が一意でない"
done

for human_gate_term in 'Tier 0' 'Tier 1' 'Tier 2' 'Tier 3' 'Tier 4' 'Intent' 'Scope' 'Evidence' 'Risk' 'Recovery' 'fail-closed' 'break-glass' 'commit SHA' digest '承認期限' '二名承認' 'pre-authorization grant' 'private repository' 'grantee/workload identity' 'task/run ID' '明示的なPR作成Intent' '裸のdigestだけを認証根拠にしない。' '条件を一つでも満たさないPR作成はTier 2' '操作分割で降格させない。' 'read-only観測と決定論的検証はTier 0' '設計・実装前のDecision Packet:' '外部反映前のDecision Packet:' '理由付き`N/A`' 'merge先base SHA' ETag 'compare-and-swap' 'lock、lease、対象凍結' '変更作成者、提案者、Executorのいずれとも異なる' 'authority mapping' 'WORMまたはhash chain' '未実装のハーネスでは`break-glass`を禁止する。' 'AI/LLM ReviewerのPASSは人間Approverを代替しない。' 'denyまたは禁止操作を解除しない。' 'immutable intentの同一payload' 'incident-action/v1' 'Manual modeはPoC限定'; do
  assert_contains "$human_gate_term" "$HUMAN_GATE_POLICY_FILE" "Human Gate Policyに必須語 '$human_gate_term' がない"
done

for branch_design in "$DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE"; do
  if grep -Fq -- 'ユーザー承認後にfeatureブランチを作成' "$branch_design"; then
    fail "feature branch作成を一律Human Gateにする旧規則が残っている: $branch_design"
  fi
done

for human_gate_design in "$DESIGN_FILE" "$JIRA_DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE" "$INCIDENT_DESIGN_FILE"; do
  assert_contains 'Human Gate Policy' "$human_gate_design" "設計書からHuman Gate Policyを参照していない: $human_gate_design"
done
assert_line '- 障害対応または本番操作が必要になった場合は、[Incident Response Harness](../../claude-code-incident-response-harness/README.md)へ昇格する。' "$LIGHTWEIGHT_DESIGN_FILE" 'LightweightからIncidentへの昇格案内がない'
assert_line '- 障害対応または本番操作が必要になった場合は、[Incident Response Harness](../../claude-code-incident-response-harness/README.md)へ昇格する。' "$MICRO_DESIGN_FILE" 'MicroからIncidentへの昇格案内がない'

for incident_state_key in incident_id severity impact commander current_status timeline hypotheses evidence action_proposals approvals executions rollbacks next_check_at unresolved_items handoff_to; do
  assert_key_once "$incident_state_key" "$INCIDENT_STATE_TEMPLATE_FILE" "Incident状態雛形のkey '$incident_state_key' が一意でない"
done

if ! command -v ruby >/dev/null 2>&1; then
  fail 'Incident状態雛形の構文・階層検査にはRuby標準ライブラリyamlが必要'
elif ! ruby -ryaml -rjson -rdigest -rtime -e '
  data = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
  arrays = %w[timeline evidence action_proposals approvals executions rollbacks]
  common = %w[timestamp actor role session_id trace_id span_id target operation result exit_code rationale]
  arrays.each do |name|
    value = data[name]
    raise "#{name} must be a non-empty array" unless value.is_a?(Array) && !value.empty?
    value.each do |entry|
      missing = common.reject { |key| entry.key?(key) }
      raise "#{name} entry missing #{missing.join(",")}" unless missing.empty?
      timestamp = entry["timestamp"]
      raise "#{name} timestamp must be RFC3339 UTC or null" unless timestamp.nil? || timestamp.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end
  end
  %w[action_proposals approvals executions rollbacks].each do |name|
    data[name].each do |entry|
      %w[action_id revision digest].each { |key| raise "#{name} entry missing #{key}" unless entry.key?(key) }
      raise "#{name} digest invalid" unless entry["digest"].match?(/\Asha256:[0-9a-f]{64}\z/)
    end
  end
  proposals = data["action_proposals"].each_with_object({}) do |entry, index|
    key = [entry["action_id"], entry["revision"]]
    raise "duplicate proposal revision" if index.key?(key)
    canonical = JSON.generate({
      "version" => "incident-action/v1",
      "action_id" => entry["action_id"],
      "revision" => entry["revision"],
      "target" => entry["target"],
      "operation" => entry["operation"],
      "parameters" => entry["parameters"],
      "preconditions" => entry["preconditions"],
      "expected_result" => entry["expected_result"],
      "stop_condition" => entry["stop_condition"],
      "timeout_seconds" => entry["timeout_seconds"],
      "rollback_operation" => entry["rollback_operation"],
      "rollback_parameters" => entry["rollback_parameters"],
      "rollback_preconditions" => entry["rollback_preconditions"],
      "rollback_condition" => entry["rollback_condition"]
    })
    raise "proposal canonical_payload mismatch" unless entry["canonical_payload"] == canonical
    calculated = "sha256:#{Digest::SHA256.hexdigest(canonical.encode("UTF-8"))}"
    raise "proposal digest mismatch" unless entry["digest"] == calculated
    index[key] = entry["digest"]
  end
  %w[approvals executions rollbacks].each do |name|
    data[name].each do |entry|
      key = [entry["action_id"], entry["revision"]]
      raise "#{name} has no matching proposal" unless proposals[key]
      raise "#{name} digest does not bind proposal" unless proposals[key] == entry["digest"]
    end
  end
  data["approvals"].each do |entry|
    %w[approval_id identity_id authority_role expires_at].each { |key| raise "approval missing #{key}" unless entry[key].is_a?(String) && !entry[key].empty? }
    raise "approval role invalid" unless entry["role"] == "approver"
    raise "approval result invalid" unless entry["result"] == "approved" && entry["exit_code"] == 0
    raise "approval expiry invalid" unless entry["expires_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
  end
  data["executions"].each do |entry|
    raise "execution missing identity_id" unless entry["identity_id"].is_a?(String) && !entry["identity_id"].empty?
    raise "execution missing approval_refs" unless entry["approval_refs"].is_a?(Array) && entry["approval_refs"].length >= 2
  end
  approval_ids = data["approvals"].map { |entry| entry["approval_id"] }
  raise "approval_id must be unique" unless approval_ids.uniq.length == approval_ids.length
  proposals.each_key do |key|
    approvals = data["approvals"].select { |entry| [entry["action_id"], entry["revision"]] == key }
    approver_ids = approvals.map { |entry| entry["identity_id"] }.uniq
    authority_roles = approvals.map { |entry| entry["authority_role"] }.uniq
    executor_ids = data["executions"].select { |entry| [entry["action_id"], entry["revision"]] == key }.map { |entry| entry["identity_id"] }.uniq
    raise "proposal must have two distinct human approver identities" unless approver_ids.length >= 2
    raise "proposal must have two distinct authority roles" unless authority_roles.length >= 2
    raise "approver and executor identities must be separate" unless (approver_ids & executor_ids).empty?
    executions = data["executions"].select { |entry| [entry["action_id"], entry["revision"]] == key }
    approved_ids = approvals.map { |entry| entry["approval_id"] }.sort
    executions.each do |execution|
      raise "execution approval_refs mismatch" unless execution["approval_refs"].sort == approved_ids
      executed_at = Time.parse(execution["timestamp"])
      approvals.each do |approval|
        approved_at = Time.parse(approval["timestamp"])
        expires_at = Time.parse(approval["expires_at"])
        raise "approval time ordering invalid" unless approved_at < expires_at && executed_at <= expires_at
      end
    end
  end
  proposal_entries = data["action_proposals"].each_with_object({}) { |entry, index| index[[entry["action_id"], entry["revision"]]] = entry }
  data["executions"].each do |entry|
    proposal = proposal_entries[[entry["action_id"], entry["revision"]]]
    %w[target operation parameters preconditions].each do |field|
      raise "execution #{field} differs from approved proposal" unless entry[field] == proposal[field]
    end
  end
  data["rollbacks"].each do |entry|
    proposal = proposal_entries[[entry["action_id"], entry["revision"]]]
    raise "rollback target differs from approved proposal" unless entry["target"] == proposal["target"]
    raise "rollback operation differs from approved proposal" unless entry["operation"] == proposal["rollback_operation"]
    raise "rollback parameters differ from approved proposal" unless entry["parameters"] == proposal["rollback_parameters"]
    raise "rollback preconditions differ from approved proposal" unless entry["preconditions"] == proposal["rollback_preconditions"]
  end
' "$INCIDENT_STATE_TEMPLATE_FILE"; then
  fail 'Incident状態雛形のYAML構文、必須階層、entry項目、UTC時刻またはdigestが不正'
fi

assert_line '進行中の本番障害または緊急の本番操作が必要になった場合は、開発工程を停止し、[Incident Response Harness](../../claude-code-incident-response-harness/README.md)へ昇格する。復旧後の恒久修正は新しいDevelopment taskとして再開する。' "$DESIGN_FILE" 'Development設計書にIncidentへの昇格導線がない'
assert_contains '異なる二人のApprover' "$INCIDENT_DESIGN_FILE" 'Incident設計書に二名承認要件がない'
assert_contains '`break-glass`は未対応' "$INCIDENT_DESIGN_FILE" 'Incident設計書が未実装break-glassを拒否していない'
assert_contains '`preconditions`' "$INCIDENT_DESIGN_FILE" 'Incident承認digestが実行前状態を束縛していない'

for jira_term in TicketSnapshot 'Definition of Ready' lease revision stale outbox idempotency_key read_credential write_credential needs_clarification Micro Bugfix Lightweight Feature Development 'Incident Response'; do
  assert_contains "$jira_term" "$JIRA_DESIGN_FILE" "Jira設計書に必須語 '$jira_term' がない"
done
assert_contains 'Jira本文、コメント、添付ファイルは不信頼入力として扱う。' "$JIRA_DESIGN_FILE" 'Jira入力の信頼境界が定義されていない'
assert_contains '```mermaid' "$JIRA_DESIGN_FILE" 'Jira設計書にMermaid構成図がない'
assert_contains 'Incident Readinessは標準Definition of Readyより前に評価する。' "$JIRA_DESIGN_FILE" 'Incident判定が標準DoRより前に定義されていない'
for jira_safety_term in pre_writeback_revision post_writeback_revision '短期intake lease' depends_on 'outboxはAgentから書き込めない' 'Agentプロセス外' If-Match at-least-once 'Attachment Isolation Fetcher' 'private address' 'link-local' WORM 'hash chain'; do
  assert_contains "$jira_safety_term" "$JIRA_DESIGN_FILE" "Jira設計書に安全要件 '$jira_safety_term' がない"
done
assert_contains 'commentとtransitionは別々のoutbox entryにする。' "$JIRA_DESIGN_FILE" 'Jira commentとtransitionが独立outboxになっていない'
assert_contains 'development writebackでは、workerはrun、固定commit、review target、`DEVELOPMENT_COMPLETION`を独立に再検証する。' "$JIRA_DESIGN_FILE" '通常開発writeback workerの独立検証がない'
assert_contains 'incident writebackでは、workerはrun、固定incident-state revisionとdigest、`INCIDENT_READINESS`、incident lease、`INCIDENT_COMPLETION`を独立に再検証する。' "$JIRA_DESIGN_FILE" 'Incident writeback workerの独立検証がない'
assert_contains 'redirect先ごとにscheme、hostname、解決後IPを再検査する。' "$JIRA_DESIGN_FILE" 'Jira添付redirectの再検査がない'
assert_contains 'ACL、retention、redaction' "$JIRA_DESIGN_FILE" 'Jira監査ログの保護・保存・秘匿要件がない'
for jira_final_term in INCIDENT_READINESS ROUTE_READINESS 'incident lease' '選択routeのreadiness gate' 'pre_writeback_revisionと意味field digestがTicketSnapshotと一致' 'post_writeback_revisionがdelivery eventへ記録' '中央outbox store' 'outbox-refs/'; do
  assert_contains "$jira_final_term" "$JIRA_DESIGN_FILE" "Jira設計書に最終整合性要件 '$jira_final_term' がない"
done
assert_contains 'Incident Readinessを標準Definition of Readyより先に判定する。' "$JIRA_README_FILE" 'Jira READMEでIncident判定が先行していない'
assert_contains '選択候補ごとのreadinessを検査する。' "$JIRA_README_FILE" 'Jira READMEにroute別readinessがない'
assert_contains 'routeに対応するleaseを取得する。' "$JIRA_README_FILE" 'Jira READMEにroute別leaseがない'
assert_order_in_file "$JIRA_README_FILE" '2. Incident Readinessを標準Definition of Readyより先に判定する。' '3. 選択候補ごとのreadinessを検査する。' 'Jira READMEのIncident判定とroute別readinessの順序が不正'
assert_order_in_file "$JIRA_README_FILE" '3. 選択候補ごとのreadinessを検査する。' '4. routeに対応するleaseを取得する。' 'Jira READMEのreadinessとleaseの順序が不正'
assert_order_in_file "$JIRA_README_FILE" '4. routeに対応するleaseを取得する。' '5. 非Incidentチケットを、再現性、規模、リスクから既存の3方式へ振り分ける。' 'Jira READMEのleaseとrouteの順序が不正'
if grep -Fq -- 'TicketSnapshotと完了時Jira revisionが一致する。' "$JIRA_DESIGN_FILE"; then
  fail 'Jira DoDでwriteback後revisionとTicketSnapshotの一致を要求してはならない'
fi
if grep -Fq -- '├─ outbox/' "$JIRA_DESIGN_FILE"; then
  fail 'Git管理下のdocs/statusへ中央outbox本体を配置してはならない'
fi
for jira_completion_term in INCIDENT_COMPLETION incident_state_revision incident_state_digest 'DEVELOPMENT_COMPLETIONはMicro Bugfix、Lightweight Feature、Developmentだけ' 'Incidentへbranch、commit、review target、PRを要求しない。' 'development writeback' 'incident writeback' '固定incident-state revisionとdigest'; do
  assert_contains "$jira_completion_term" "$JIRA_DESIGN_FILE" "Jira設計書にroute別完了要件 '$jira_completion_term' がない"
done
assert_contains 'Incidentは影響回復、観測窓、handoff、恒久修正follow-upを完了条件とする。' "$JIRA_README_FILE" 'Jira READMEにIncident固有完了条件がない'
if grep -Fq -- 'issue typeだけで方式を決めず、Definition of Ready後に次の優先順で判定する。' "$JIRA_DESIGN_FILE"; then
  fail '標準DoR後にIncidentを含む4方式を判定する旧routingを残してはならない'
fi
if grep -Fq -- '既存の4方式へ振り分ける。' "$JIRA_README_FILE"; then
  fail 'Jira READMEでIncidentを通常3方式と同じ後段routingへ含めてはならない'
fi
assert_contains 'route別固定証跡またはgateがschemaと一致しなければfail-closedで拒否する。' "$JIRA_DESIGN_FILE" 'Jira outboxのroute別fail-closed規則がない'
for jira_route_comment_term in 'development結果commentはPR、verification、review' 'incident結果commentはimpact、recovery、mitigation、observation window、handoff、permanent fix follow-up' 'state runnerはACLで許可されたidentityとしてintent、route別固定証跡、gate結果を検証する。' 'route別固定証跡/gate不一致'; do
  assert_contains "$jira_route_comment_term" "$JIRA_DESIGN_FILE" "Jira設計書にroute別comment/固定証跡要件 '$jira_route_comment_term' がない"
done
if grep -Fq -- '完了コメントには概要、PR' "$JIRA_DESIGN_FILE"; then
  fail 'IncidentにもPRを要求する旧完了コメント文言を残してはならない'
fi
if grep -Fq -- '固定commit/gate不一致' "$JIRA_DESIGN_FILE"; then
  fail 'Incidentにもfixed commitを要求するworker共通表現を残してはならない'
fi

for outbox_kind in development incident; do
  output_file="$WORK_DIR/jira-$outbox_kind-outbox.yaml"
  awk -v marker="# $outbox_kind writeback example" '
    $0 == marker { in_block = 1 }
    in_block && $0 == "```" { exit }
    in_block { print }
  ' "$JIRA_DESIGN_FILE" > "$output_file"
done

if ! command -v ruby >/dev/null 2>&1; then
  fail 'Jira outbox schema検査にはRuby標準ライブラリyamlが必要'
elif ! ruby -ryaml -e '
  common = %w[schema_version outbox_id issue_id issue_key run_id snapshot_revision pre_writeback_revision post_writeback_revision route operation expected_status lease_ref depends_on idempotency_key payload_digest payload required_gates signature]
  definitions = {
    "development" => {
      required: %w[fixed_commit review_target],
      forbidden: %w[incident_state_ref incident_state_revision incident_state_digest],
      gates: %w[ROUTE_READINESS LEASE DEVELOPMENT_COMPLETION JIRA_REVISION],
      payload: %w[kind summary pull_request verification review],
      forbidden_payload: %w[impact recovery mitigation observation_window handoff permanent_fix_follow_up]
    },
    "incident" => {
      required: %w[incident_state_ref incident_state_revision incident_state_digest],
      forbidden: %w[fixed_commit review_target],
      gates: %w[INCIDENT_READINESS LEASE INCIDENT_COMPLETION JIRA_REVISION],
      payload: %w[kind impact recovery mitigation observation_window handoff permanent_fix_follow_up],
      forbidden_payload: %w[pull_request verification review]
    }
  }
  ARGV.each_slice(2) do |kind, file|
    data = YAML.safe_load(File.read(file), permitted_classes: [], aliases: false)
    raise "#{kind} outbox must be a mapping" unless data.is_a?(Hash)
    definition = definitions.fetch(kind)
    missing = (common + definition[:required]).reject { |key| data.key?(key) }
    raise "#{kind} outbox missing #{missing.join(",")}" unless missing.empty?
    present_forbidden = definition[:forbidden].select { |key| data.key?(key) }
    raise "#{kind} outbox forbids #{present_forbidden.join(",")}" unless present_forbidden.empty?
    raise "#{kind} route mismatch" unless data["route"] == kind
    gates = data["required_gates"]
    raise "#{kind} gates mismatch" unless gates.is_a?(Array) && gates.sort == definition[:gates].sort
    payload = data["payload"]
    raise "#{kind} payload must be a mapping" unless payload.is_a?(Hash)
    missing_payload = definition[:payload].reject { |key| payload.key?(key) }
    raise "#{kind} payload missing #{missing_payload.join(",")}" unless missing_payload.empty?
    forbidden_payload = definition[:forbidden_payload].select { |key| payload.key?(key) }
    raise "#{kind} payload forbids #{forbidden_payload.join(",")}" unless forbidden_payload.empty?
    raise "#{kind} payload kind mismatch" unless payload["kind"] == kind
  end
' development "$JIRA_DEVELOPMENT_OUTBOX_FILE" incident "$JIRA_INCIDENT_OUTBOX_FILE"; then
  fail 'Jira Development/Incident outboxの共通envelopeまたはroute別oneOf schemaが不正'
fi
if [ -e "$ROOT_DIR/patterns/claude-code-jira-ticket-harness/docs/images/overview.png" ]; then
  fail 'Jira Ticket Harnessは旧Development overview.pngを複製してはならない'
fi

if [ "$(grep -Fxc -- '# docs/status/gate-runs/gate-run-TASK-004-unit-test-green-007.yaml' "$DESIGN_FILE")" -eq 1 ]; then
  awk '
    $0 == "# docs/status/gate-runs/gate-run-TASK-004-unit-test-green-007.yaml" { in_block = 1 }
    in_block { print }
    in_block && $0 == "```" { exit }
  ' "$DESIGN_FILE" > "$UNIT_TEST_GREEN_GATE_FILE"
else
  : > "$UNIT_TEST_GREEN_GATE_FILE"
fi

if [ "$(grep -Fxc -- '## 6.6 Implementation Evaluation Gate' "$DESIGN_FILE")" -eq 1 ] && [ "$(grep -Fxc -- '# 7. Integration Test方針' "$DESIGN_FILE")" -eq 1 ]; then
  awk '
    $0 == "## 6.6 Implementation Evaluation Gate" { in_section = 1 }
    in_section { print }
    in_section && $0 == "# 7. Integration Test方針" { exit }
  ' "$DESIGN_FILE" > "$IMPLEMENTATION_GATE_SECTION_FILE"
else
  : > "$IMPLEMENTATION_GATE_SECTION_FILE"
fi

if [ "$(grep -Fxc -- '# docs/features/order/reviews/targets/TASK-004-implementation.yaml' "$DESIGN_FILE")" -eq 1 ]; then
  awk '
    $0 == "# docs/features/order/reviews/targets/TASK-004-implementation.yaml" { in_block = 1 }
    in_block { print }
    in_block && $0 == "```" { exit }
  ' "$DESIGN_FILE" > "$IMPLEMENTATION_REVIEW_TARGET_FILE"
else
  : > "$IMPLEMENTATION_REVIEW_TARGET_FILE"
fi

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

while IFS='|' read -r agent allowed_phases _profile; do
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

while IFS='|' read -r agent allowed_phases _profile; do
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
if grep -Fxq 'POST_REFACTOR_GREEN' "$QUALITY_FILE" || grep -Fxq 'post_refactor_green|passed' "$STATE_FILE"; then
  fail 'POST_REFACTOR_GREENを新しい正式ゲートとして追加してはならない'
fi
assert_line '| UNIT_TEST_GREEN     | `POST_REFACTOR_GREEN`完了、対象・関連・全UT成功、テスト弱体化なし、result_commitに証跡を束縛 | 実装 |' "$DESIGN_FILE" '正式UNIT_TEST_GREENがPOST完了専用になっていない'
if grep -Fq 'PREPARATORY_REFACTOR_REVIEW_TARGET' "$DESIGN_FILE"; then
  fail 'PREPARATORY_REFACTOR専用の新しいレビューゲートを追加してはならない'
fi
assert_line 'stage: POST_REFACTOR_GREEN' "$UNIT_TEST_GREEN_GATE_FILE" 'UNIT_TEST_GREEN GateRunにPOST完了段階がない'
assert_line 'evaluated_commit: abc123def456' "$UNIT_TEST_GREEN_GATE_FILE" 'POST完了証跡のevaluated_commit束縛がない'
assert_line 'result_commit: abc123def456' "$UNIT_TEST_GREEN_GATE_FILE" 'POST完了証跡のresult_commit束縛がない'
assert_line 'test_evidence_refs:' "$UNIT_TEST_GREEN_GATE_FILE" 'POST完了証跡にtest evidence参照がない'
assert_line 'command: ./gradlew test' "$UNIT_TEST_GREEN_GATE_FILE" 'POST完了証跡に実行commandがない'
assert_line 'exit_code: 0' "$UNIT_TEST_GREEN_GATE_FILE" 'POST完了証跡にexit codeがない'
assert_line 'result_summary: 既存を含む対象・関連・全UT成功' "$UNIT_TEST_GREEN_GATE_FILE" 'GateRun schemaに結果summaryがない'
if ! grep -Eq '^test_artifact_hash: sha256:[0-9a-f]{64}$' "$UNIT_TEST_GREEN_GATE_FILE"; then
  fail 'POST完了証跡のtest artifact hashがSHA-256形式でない'
fi
assert_line 'preparatory_refactor_used: true' "$UNIT_TEST_GREEN_GATE_FILE" 'preparatory_refactor_used宣言がない'
assert_line '  characterization_tests_locked_after_green_confirmation: true' "$UNIT_TEST_GREEN_GATE_FILE" 'characterization test集合の固定状態がない'
assert_line '  before_command: ./gradlew characterizationTest' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY前のcommandがない'
assert_line '  after_command: ./gradlew characterizationTest' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY前後で同一commandでない'
assert_line '  before_exit_code: 0' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY前のexit codeが0でない'
assert_line '  after_exit_code: 0' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY後のexit codeが0でない'
assert_line '  before_test_evidence_ref: docs/status/test-evidence/TASK-004-preparatory-before.yaml' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY前のtest evidence参照がない'
assert_line '  after_test_evidence_ref: docs/status/test-evidence/TASK-004-preparatory-after.yaml' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY後のtest evidence参照がない'
assert_line '  preparatory_result_summary: 前後でcharacterization test集合とartifact hashが一致' "$UNIT_TEST_GREEN_GATE_FILE" 'PREPARATORY結果summaryがない'
before_hash=$(sed -n 's/^  before_test_artifact_hash: sha256:\([0-9a-f][0-9a-f]*\)$/\1/p' "$UNIT_TEST_GREEN_GATE_FILE")
after_hash=$(sed -n 's/^  after_test_artifact_hash: sha256:\([0-9a-f][0-9a-f]*\)$/\1/p' "$UNIT_TEST_GREEN_GATE_FILE")
if ! printf '%s\n' "$before_hash" | grep -Eq '^[0-9a-f]{64}$' || [ "$before_hash" != "$after_hash" ]; then
  fail 'PREPARATORY前後のtest artifact hashが完全一致するSHA-256でない'
fi
before_command=$(sed -n 's/^  before_command: //p' "$UNIT_TEST_GREEN_GATE_FILE")
after_command=$(sed -n 's/^  after_command: //p' "$UNIT_TEST_GREEN_GATE_FILE")
if [ -z "$before_command" ] || [ "$before_command" != "$after_command" ]; then
  fail 'PREPARATORY前後のcommandが同一でない'
fi
for singleton_key in gate_run_id gate_definition stage phase_run_id task input_revision evaluated_commit result_commit status test_evidence_refs test_artifact_hash command exit_code result_summary preparatory_refactor_used preparatory_refactor checkpoint_ref checkpoint_artifact_hash baseline_commit preparatory_result_commit diff_base before_diff_hash after_diff_hash characterization_tests_locked_after_green_confirmation before_command before_exit_code before_test_evidence_ref before_test_artifact_hash after_command after_exit_code after_test_evidence_ref after_test_artifact_hash preparatory_result_summary; do
  assert_key_once "$singleton_key" "$UNIT_TEST_GREEN_GATE_FILE" "UNIT_TEST_GREEN GateRunのsingleton key '$singleton_key' が一意でない"
done
assert_line '  preparatory_refactor_used: true' "$IMPLEMENTATION_REVIEW_TARGET_FILE" 'review targetにPREPARATORY使用宣言がない'
assert_line '  preparatory_checkpoint_ref: docs/status/checkpoints/TASK-004-preparatory-refactor.yaml' "$IMPLEMENTATION_REVIEW_TARGET_FILE" 'review targetにPREPARATORY checkpoint参照がない'
assert_line '    docs/status/checkpoints/TASK-004-preparatory-refactor.yaml: sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' "$IMPLEMENTATION_REVIEW_TARGET_FILE" 'review targetのartifact_hashesにcheckpoint hashがない'
for review_target_singleton_key in preparatory_refactor_used preparatory_checkpoint_ref docs/status/checkpoints/TASK-004-preparatory-refactor.yaml; do
  assert_key_once "$review_target_singleton_key" "$IMPLEMENTATION_REVIEW_TARGET_FILE" "IMPLEMENTATION_REVIEW_TARGETのsingleton key '$review_target_singleton_key' が一意でない"
done
assert_line '`IMPLEMENTATION_REVIEW_TARGET` blockでは`preparatory_refactor_used`、`preparatory_checkpoint_ref`、checkpoint artifact mappingをsingleton keyとし、各出現回数が1でなければfail-closedとする。' "$DESIGN_FILE" 'IMPLEMENTATION_REVIEW_TARGET singleton key規則がない'
gate_checkpoint_hash=$(sed -n 's/^  checkpoint_artifact_hash: sha256:\([0-9a-f][0-9a-f]*\)$/\1/p' "$UNIT_TEST_GREEN_GATE_FILE")
target_checkpoint_hash=$(sed -n 's/^    docs\/status\/checkpoints\/TASK-004-preparatory-refactor.yaml: sha256:\([0-9a-f][0-9a-f]*\)$/\1/p' "$IMPLEMENTATION_REVIEW_TARGET_FILE")
if ! printf '%s\n' "$gate_checkpoint_hash" | grep -Eq '^[0-9a-f]{64}$' || [ "$gate_checkpoint_hash" != "$target_checkpoint_hash" ]; then
  fail 'GateRunとIMPLEMENTATION_REVIEW_TARGETのcheckpoint hashが一致するSHA-256でない'
fi
assert_line '`preparatory_refactor_used: true`の場合、`IMPLEMENTATION_REVIEW_TARGET`のreview target schemaに`preparatory_checkpoint_ref`を必須とし、`artifact_hashes`のcheckpoint hashをGateRunの`checkpoint_artifact_hash`と一致させる。欠落・不一致・形式不正はfail-closedとする。' "$DESIGN_FILE" 'PREPARATORY checkpointのreview target fail-closed規則がない'
assert_order_in_file "$IMPLEMENTATION_GATE_SECTION_FILE" 'POST_REFACTOR_GREEN' 'IMPLEMENTATION_REVIEW_TARGET' 'PHASE-7のPOST_REFACTOR_GREENとレビュー対象固定の順序が不正'
assert_line 'PHASE-7では、`GREEN_CONFIRMATION`の後にREFACTORを完了し、`POST_REFACTOR_GREEN`として`UNIT_TEST_GREEN` GateRunをPASSさせてから`IMPLEMENTATION_REVIEW_TARGET`を固定する。同じ対象を独立したImplementation Evaluatorが評価し、`IMPLEMENTATION_EVALUATION`がPASSするまでPHASE-8へ進まない。' "$DESIGN_FILE" 'Developmentの規範フローが不正'
assert_line '- `PREPARATORY_REFACTOR`では、characterization test集合を`GREEN_CONFIRMATION`後に固定し、前後で同一commandを実行する。固定後のテスト削除・変更・skip、assertion弱体化を禁止し、前後のtest artifact hashが完全一致しなければ失敗とする。' "$DESIGN_FILE" '準備的リファクタリングのテスト固定規則が不十分'
assert_line '- `PREPARATORY_REFACTOR`のcheckpoint evidenceは最終的な`IMPLEMENTATION_REVIEW_TARGET`へ含める。独立レビューが必要、複数責務・複数component、architecture判断、または大規模変更なら別Development taskへ昇格する。' "$DESIGN_FILE" '準備的リファクタリングのレビュー対象と昇格条件が不十分'
assert_line '- `PREPARATORY_REFACTOR`では公開API、永続化形式、認証・認可、監査、秘密情報境界を変更しない。必要な場合は機能実装と分離した独立Development taskへ昇格する。' "$DESIGN_FILE" '準備的リファクタリングの禁止境界が不十分'
assert_line '- テストの削除・変更・skip、assertionの弱体化でGREENにしない。' "$LIGHTWEIGHT_DESIGN_FILE" 'Lightweight Harnessのテスト保護規則が不十分'
assert_line '- production codeは回帰テストのRED後にだけ変更する。RED前のproduction差分を禁止し、例外は実装しない。' "$MICRO_DESIGN_FILE" 'Micro HarnessのRED前production変更禁止が不明確'
assert_line '| TDD | RED → GREEN_CONFIRMATION → REFACTOR → POST_REFACTOR_GREENを小さく反復 | POST_REFACTOR_GREENを確認済み |' "$LIGHTWEIGHT_DESIGN_FILE" 'LightweightのTDDフローが不正'
assert_line '- REFACTOR後に新規・関連テストを再実行し、終了コード0の`POST_REFACTOR_GREEN`を確認してからVerifyとレビューへ進む。' "$LIGHTWEIGHT_DESIGN_FILE" 'LightweightのPOST完了条件が不十分'
assert_line '- `PREPARATORY_REFACTOR`が必要なら実装せず、別Development taskへ昇格する。' "$LIGHTWEIGHT_DESIGN_FILE" 'LightweightのPREPARATORY昇格条件が不十分'
assert_line '| Fix | 根本原因への最小差分を実装 | 回帰テストが成功（GREEN_CONFIRMATION） |' "$MICRO_DESIGN_FILE" 'MicroのFixフローが不正'
assert_line '- REFACTOR後に回帰・関連テストを再実行し、終了コード0の`POST_REFACTOR_GREEN`を確認してからVerifyとレビューへ進む。' "$MICRO_DESIGN_FILE" 'MicroのPOST完了条件が不十分'
assert_line '- `PREPARATORY_REFACTOR`が必要なら実装せず、Development Harnessの別taskへ昇格する。' "$MICRO_DESIGN_FILE" 'MicroのPREPARATORY昇格条件が不十分'
assert_line '- PHASE-7の`POST_REFACTOR_GREEN`はUTだけを対象とし、Integration Testの作成・更新・実行はPHASE-8で行う。' "$DESIGN_FILE" 'PHASE-7とPHASE-8のテスト責務が不明確'
assert_line '- PHASE-7の出口を`IMPLEMENTATION_EVALUATION`へ統一し、`GREEN_CONFIRMATION → REFACTOR → POST_REFACTOR_GREEN（UNIT_TEST_GREEN GateRun PASS）→ IMPLEMENTATION_REVIEW_TARGET → IMPLEMENTATION_EVALUATION`の順序を明記した。' "$DESIGN_FILE" '現行版変更履歴のPHASE-7順序が古い'
assert_line '`gate_definition: UNIT_TEST_GREEN`の場合、runtimeは`stage: POST_REFACTOR_GREEN`とPOST完了証跡の全fieldを必須とし、欠落・不一致をfail-closedにする。' "$DESIGN_FILE" 'UNIT_TEST_GREENのruntime fail-closed規則がない'
assert_line '`preparatory_refactor_used`はbooleanの必須fieldとする。`true`なら`preparatory_refactor` objectと前後各exit code 0、test evidence参照、完全一致するartifact hash、同一commandを必須とする。`false`ならRED前のproduction diffがないことを機械確認する。' "$DESIGN_FILE" 'PREPARATORY条件分岐schemaが不十分'
assert_line 'Implementation Evaluatorはproduction diffと`preparatory_refactor_used`宣言の一致を検査し、不一致ならfail-closedで差し戻す。' "$DESIGN_FILE" 'PREPARATORY宣言とdiffのEvaluator検査がない'
if grep -Eq 'docs/(requirements|design|plans|tests|reviews|handoffs)/' "$DESIGN_FILE"; then
  fail '機能固有成果物がdocs/features/<feature-id>/外の旧global pathを参照している'
fi

if [ "$ERRORS" -ne 0 ]; then
  printf '%s\n' "Document consistency validation failed with $ERRORS error(s)." >&2
  exit 1
fi

printf '%s\n' 'Document consistency validation passed.'
