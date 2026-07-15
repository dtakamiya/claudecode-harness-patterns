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

for design_path in "$DESIGN_FILE" "$JIRA_DESIGN_FILE" "$LIGHTWEIGHT_DESIGN_FILE" "$MICRO_DESIGN_FILE" "$INCIDENT_DESIGN_FILE"; do
  if [ ! -f "$design_path" ] || [ ! -r "$design_path" ] || [ -L "$design_path" ]; then
    printf '%s\n' "FAIL: 設計書が通常の読取り可能ファイルではない: $design_path" >&2
    exit 1
  fi
done

for required_path in "$JIRA_README_FILE" "$INCIDENT_README_FILE" "$INCIDENT_STATE_TEMPLATE_FILE" "$ROOT_README_FILE" "$PATTERNS_README_FILE" "$HUMAN_GATE_POLICY_FILE"; do
  if [ ! -f "$required_path" ] || [ ! -r "$required_path" ] || [ -L "$required_path" ]; then
    printf '%s\n' "FAIL: 必須文書が通常の読取り可能ファイルではない: $required_path" >&2
    exit 1
  fi
done

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
