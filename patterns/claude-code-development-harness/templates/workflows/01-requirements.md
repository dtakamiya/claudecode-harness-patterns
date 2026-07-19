# PHASE-1: 要件定義

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §5.1):
  id: PHASE-1
  inputs: baseline, stakeholder-input
  outputs: requirements, acceptance-criteria, open-items
  entry_gate: INITIALIZATION
  exit_gate: REQUIREMENTS_DRAFT
  allowed_agents: requirements-planner, requirements-analyst, context-builder
-->

## 目的

要求を構造化し、一意なIDと検証可能な受入条件を持つ要件へ落とす（設計書 §5.1）。

## 開始条件

`INITIALIZATION`がPASSしていることをOrchestratorが検証する（設計書 §3.4.1 実行状態と遷移）。

## 入力

- `docs/status/baseline.yaml`
- ステークホルダー入力

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Planner | `requirements-planner` | planner |
| Generator | `requirements-analyst` | generator / `docs/features/<feature-id>/requirements`のみwrite |
| コンテキスト編成 | `context-builder` | context_builder |

影響範囲が大きい工程のため、Planner・Generator・Evaluatorを独立させる3層構成とする（設計書 §3.4 適用原則）。Evaluatorの`requirements-reviewer`はPHASE-2で実行する。

## 手順

1. Requirements Plannerが調査範囲、ステークホルダー、論点、必要成果物、質問事項を計画する（設計書 §8.2）。Plannerは成果物本文を完成させず、Generatorが迷わず作業できる入力、範囲、終了条件、禁止事項を定義する。
2. `REQUIREMENTS_PLAN`をintra-phase gateとして評価する（設計書 §11.0）。
3. Requirements Analystが要求を構造化する。
   - 機能要件と非機能要件に一意なIDを付与する（例: `REQ-F-001`、`REQ-NF-001`）。
   - 各要件に検証可能な受入条件を付与する（例: `AC-001-01`）。
   - 受入条件はEARSの5文型（Ubiquitous / Event-driven / State-driven / Unwanted behavior / Optional feature）で記述する（設計書 §5.1.1）。
   - 前提、制約、スコープ外、未解決事項を明示する。
4. 設計・実装上の手段を早期に固定しすぎない（設計書 §5.1）。
5. 未確定事項は推測せず、質問・課題として記録し、重大なものはblockingとして次工程をブロックする（設計書 §2 推測禁止）。

## 成果物

- `docs/features/<feature-id>/requirements/<name>.md`
- 受入条件（要件IDへ紐付ける）
- 未解決事項（blocking判定付き）
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `REQUIREMENTS_PLAN` | intra-phase | Plannerが範囲、論点、成果物、終了条件を定義（設計書 §11） |
| `REQUIREMENTS_DRAFT` | exit gate | 要件ID、受入条件、未解決事項、スコープが明確（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

評価順序は`REQUIREMENTS_PLAN` → `REQUIREMENTS_DRAFT`とする。exit gateは、当該Phaseのintra-phase gateがすべてPASSした場合だけPASSし得る（設計書 §11.0）。

## ブロック時の戻り先

`REQUIREMENTS_PLAN`は要件Planner、`REQUIREMENTS_DRAFT`は要件定義（設計書 §11）。

## 注意事項

- Requirements Analystは実装方式を推測で決めない（設計書 §8.3）。
- ソースコードを編集しない（設計書 §3.6 Permission Boundary表）。
- Shellは原則なし、Networkは調査時のみ。既定では与えない（設計書 §3.6）。

## 次工程

`REQUIREMENTS_DRAFT`がPASSした場合だけPHASE-2を`ready`へ遷移させる。
