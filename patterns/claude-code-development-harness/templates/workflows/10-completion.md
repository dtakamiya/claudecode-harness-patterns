# PHASE-10: 完了監査

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §12, §15, 付録B):
  id: PHASE-10
  inputs: all-artifacts, traceability, reviews
  outputs: completion-audit, final-handoff
  entry_gate: CODE_REVIEW
  exit_gate: COMPLETION
  allowed_agents: completion-auditor, context-builder
-->

## 目的

要件〜設計〜タスク〜UT〜IT〜実装の追跡を検証し、Definition of Doneと全品質ゲートの充足を独立に判定する（設計書 §8.4、§15）。

## 開始条件

`CODE_REVIEW`がPASSしていることをOrchestratorが検証する。

## 入力

- 全成果物
- トレーサビリティ
- 各レビュー結果

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Evaluator | `completion-auditor` | evaluator |
| コンテキスト編成 | `context-builder` | context_builder |

Evaluator専用工程とし、**実装者による自己判定を完了根拠にしない**（設計書 §3.4 適用原則）。

## 手順

1. トレーサビリティを検証する（設計書 §12）。

```yaml
requirements:
  REQ-F-003:
    acceptance_criteria:
      - AC-003-01
      - AC-003-02
    implementation_tasks:
      - TASK-004
    unit_tests:
      - UT-ORDER-001
      - UT-ORDER-002
    integration_tests:
      - IT-ORDER-001
      - IT-ORDER-002
    status: implemented
```

2. Definition of Doneの各条件を検証する（設計書 §15）。
3. 全品質ゲートの状態を検証する。**cross-cutting gateは反復評価の結果であり、過去にPASSしたことは現在のPASSを意味しない**（設計書 §11.0）。
4. 完了判定を記録する。
5. 最終handoffを作成する（設計書 §9.1）。

## Definition of Done（設計書 §15）

- 対象要件と受入条件が確定し、blockingの未解決事項がない。
- 詳細設計とADRが更新されている。
- UTのRED-GREEN-REFACTORを完了している。
- 必要なIntegration Testが作成され、成功している。
- 全UT、全対象IT、静的解析、フォーマットが成功している。
- テストの削除・無効化・弱体化がない。
- Code ReviewとSecurity Reviewのblocking指摘がゼロである。
- provider APIまたはsignatureで検証済みのHuman Review Evidenceが現在対象へ束縛され、責任ある人間Reviewerのverdictが`approved`である。
- UI変更では`UI_VERIFICATION`が成功し、非UI変更ではnot applicableである。
- 要件IDからタスク、UT、IT、実装への追跡が成立している。
- statusとhandoffが最新である。
- Implementation Evaluatorが`IMPLEMENTATION_REVIEW_TARGET`を検証し、Code ReviewerとSecurity Reviewerが同一の`CODE_REVIEW_TARGET`を検証している。
- context manifestのアクセス方針が、FullまたはCompatibleのenforcement profileにより機械的に強制されている。
- `progress.yaml`がOrchestratorのsingle writer方式で更新され、revisionとGit SHAが一致している。

## 成果物

- 完了監査結果
- 最終handoff
- `docs/status/agent-runs/<task>/<run-id>.yaml`

完了判定の記録形式（設計書 付録B）:

```yaml
gate: COMPLETION
conditions:
  all_requirements_implemented: true
  all_acceptance_criteria_covered: true
  unit_tests_passed: true
  integration_tests_passed: true
  ui_verification_passed_or_not_applicable: true
  static_analysis_passed: true
  tests_not_weakened: true
  blocking_code_review_findings: 0
  blocking_security_review_findings: 0
  code_review_passed: true
  security_review_passed: true
  human_review_evidence_valid: true
  human_review_target_matches: true
  human_review_approved: true
  traceability_complete: true
  documentation_updated: true
  handoff_updated: true
  implementation_review_target_verified: true
  code_review_target_verified: true
  access_policy_enforced: true
  state_revision_consistent: true
  progress_single_writer_verified: true
result: PASS
```

## 最終handoffの必須項目（設計書 §9.1）

- 完了した作業と未完了の作業
- 次工程が参照すべき権威ある成果物
- 確定した判断とADR
- 制約、禁止事項、スコープ外
- 未解決事項とblocking判定
- 次に実行可能なタスク
- Human Review Evidenceの権威ある発行元のimmutable evidence URLとrevisionまたはsignature、stable subject ID、target、verdict、issued_at、およびRunnerの検証結果。**Git内の自己申告で代用しない。**

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `COMPLETION` | exit gate | 全要件・受入条件・テスト・文書と有効なHuman Review Evidenceが完了（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

該当工程（設計書 §11）。未充足条件が属する工程へ差し戻す。

## 注意事項

- **未解決の重大事項を見逃さない**（設計書 §8.4）。
- Completion Auditorは成果物を自己修正せず、`progress.yaml`も直接更新しない。書込みはレビュー成果物とagent-runだけとする（設計書 §3.6）。
- **Cross-cutting gateを「完了時に一度だけ確認する項目」として実装してはならない。** 予防制御を事後確認へ格下げすることになる（設計書 §11.0）。ここでの検証は反復評価済みGateRunの集計であり、初回評価ではない。
- 変更範囲や越権書込みの「無いことの証明」は機械的検査の証跡を入力とする。証跡が無い場合はPASSとせず、`residual_risks`へ記録してOrchestratorへ機械的検証を要求する（設計書 §11.1）。
- 失敗事例はそのまま新しいevalケースへ追加し、ハーネス変更による回帰を検出する（設計書 §3.10）。
