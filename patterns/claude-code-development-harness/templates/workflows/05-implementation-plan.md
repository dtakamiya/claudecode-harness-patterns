# PHASE-5: 実装計画

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §5.4):
  id: PHASE-5
  inputs: detailed-design
  outputs: task-plans
  entry_gate: DETAILED_DESIGN
  exit_gate: IMPLEMENTATION_PLAN
  allowed_agents: implementation-planner, task-generator, plan-reviewer, context-builder
-->

## 目的

設計を、一つのセッションまたは一つのワークユニットで完了できる大きさの、独立して検証可能な実装タスクへ分解する（設計書 §5.4）。

## 開始条件

`DETAILED_DESIGN`がPASSしていることをOrchestratorが検証する。

## 入力

- PHASE-4の詳細設計

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Planner | `implementation-planner` | planner |
| Generator | `task-generator` | generator / `docs/features/<feature-id>/plans`のみwrite |
| Evaluator | `plan-reviewer` | evaluator |
| コンテキスト編成 | `context-builder` | context_builder |

影響範囲が大きい工程のため3層構成とする（設計書 §3.4 適用原則）。

## 手順

1. Implementation Plannerが設計を小さく検証可能なタスクへ分解し、依存関係と実行順を決定する（設計書 §8.2）。
2. Task GeneratorがPlannerの分解を自己完結したタスク文書へ展開し、UT/IT IDと受入条件を写像する。**分解・依存・実行順を再決定せず、テストケースを設計しない**（設計書 §8.3）。
3. 各タスクへ`ui_change: true|false`を記録する。Generatorの自己申告だけでnot applicableにしてはならない（設計書 §7.2）。
4. Plan Reviewerがタスク粒度、依存関係、受入条件、UT/IT、スコープを独立評価する。巨大タスクや検証不能タスクを承認しない（設計書 §8.4）。

## 成果物

- `docs/features/<feature-id>/plans/tasks/TASK-XXX.md`
- `docs/features/<feature-id>/reviews/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

タスク文書の形式（設計書 §5.4）:

```markdown
# TASK-004: 注文登録
## 対象要件
- REQ-F-003
## 受入条件
- AC-003-01
- AC-003-02
## Unit Tests
- UT-ORDER-001
- UT-ORDER-002
## Integration Tests
- IT-ORDER-001
- IT-ORDER-002
## Out of scope
- 決済処理
```

各タスクは要件、受入条件、想定変更範囲、UT、IT、依存関係、スコープ外を持つ（設計書 §5.4）。

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `IMPLEMENTATION_PLAN` | exit gate | タスク粒度、依存、UT/IT、DoDがレビュー済み（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

実装計画（設計書 §11）。

## 注意事項

- タスクは一つのClaude Codeセッションまたは一つのワークユニットで完了できる大きさに分割する（設計書 §5.4）。
- 並列化できるのは、異なるモジュールの独立タスク、対象commitが固定された読み取り専用レビュー、異なる文書の作成、競合しないテスト追加に限る。同一クラス・同一設定・同一DBスキーマの変更、前後依存のあるタスクは並列化しない（設計書 §3.8）。

## 次工程

`IMPLEMENTATION_PLAN`がPASSした場合だけPHASE-6を`ready`へ遷移させる。
