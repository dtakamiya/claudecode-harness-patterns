# PHASE-3: 基本設計

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §5.3):
  id: PHASE-3
  inputs: approved-requirements
  outputs: basic-design, ADR
  entry_gate: REQUIREMENTS_REVIEW
  exit_gate: BASIC_DESIGN
  allowed_agents: architecture-planner, architect, design-reviewer, context-builder
-->

## 目的

システム境界、コンポーネント、データフロー、非機能方式を確定し、重要な技術判断をADRとして残す（設計書 §5.3）。

## 開始条件

`REQUIREMENTS_REVIEW`がPASSしていることをOrchestratorが検証する。

## 入力

- 承認済み要件（PHASE-2でblocking指摘ゼロになったもの）

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Planner | `architecture-planner` | planner |
| Generator | `architect` | generator / `docs/features/<feature-id>/design`, `decisions`のみwrite |
| Evaluator | `design-reviewer` | evaluator |
| コンテキスト編成 | `context-builder` | context_builder |

影響範囲が大きい工程のため3層構成とする（設計書 §3.4 適用原則）。

## 手順

1. Architecture Plannerが設計論点、非機能要件、代替案、ADR候補、調査順序を計画する（設計書 §8.2）。
2. `ARCHITECTURE_PLAN`をintra-phase gateとして評価する（設計書 §11.0）。
3. Architectがシステム境界、コンポーネント、データフロー、外部連携、セキュリティ、障害方針を定義する（設計書 §5.3）。
4. 重要な技術判断はADRとして分離し、理由・代替案・影響を残す。
5. 非自明なAI支援変更はChange Intent Recordに従い、目的、対象外、理由、制約と、要件・コード・テスト・ADRへの参照を機能固有の既存成果物へ記録する。CIRのために新しい状態遷移や品質ゲートを追加しない（設計書 §5.3）。
6. Design Reviewerが要件適合性、非機能要件、責務、ADR、実装可能性を独立評価する（設計書 §8.4）。

## 成果物

- `docs/features/<feature-id>/design/<name>.md`
- `docs/features/<feature-id>/decisions/ADR-XXX.md`
- `docs/features/<feature-id>/reviews/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `ARCHITECTURE_PLAN` | intra-phase | 設計論点、代替案、非機能観点、ADR候補が定義（設計書 §11） |
| `BASIC_DESIGN` | exit gate | システム境界、非機能方式、責務、ADRが定義（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

評価順序は`ARCHITECTURE_PLAN` → `BASIC_DESIGN`とする（設計書 §11.0）。

## ブロック時の戻り先

`ARCHITECTURE_PLAN`はArchitecture Planner、`BASIC_DESIGN`は基本設計（設計書 §11）。

## 注意事項

- Architectは詳細実装へ踏み込みすぎない（設計書 §8.3）。
- 実装変更を行わない（設計書 §3.6 Permission Boundary表）。
- Design Reviewerは設計者と同一コンテキストで承認しない（設計書 §8.4）。
- 非自明な設計意図の正本はGit内の既存成果物へ置く。PR、issue、外部文書は固定revision、commit SHAまたはimmutable snapshot付きのsource/mirrorとしてのみ参照する（設計書 §5.3）。
- AIの内部思考や完全な会話transcriptは保存せず、採用した判断と検証可能な根拠だけを残す（設計書 §5.3）。

## 次工程

`BASIC_DESIGN`がPASSした場合だけPHASE-4を`ready`へ遷移させる。
