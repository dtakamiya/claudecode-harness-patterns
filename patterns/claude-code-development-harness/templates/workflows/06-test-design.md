# PHASE-6: テスト設計

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §6, §7):
  id: PHASE-6
  inputs: task-plans, acceptance-criteria
  outputs: unit-test-plan, integration-test-plan, test-data
  entry_gate: IMPLEMENTATION_PLAN
  exit_gate: TEST_DESIGN
  allowed_agents: tdd-generator, test-reviewer, context-builder
-->

## 目的

UT観点とIT観点を、正常・異常・境界を網羅する形で定義し、テストデータを用意する（設計書 §5 工程表）。

## 開始条件

`IMPLEMENTATION_PLAN`がPASSしていることをOrchestratorが検証する。

## 入力

- PHASE-5のタスク計画
- 受入条件
- context manifest

## 担当Agent

| 役割 | Agent | profile | Skill |
|---|---|---|---|
| Generator | `tdd-generator` | generator | `tdd-development@1` |
| Evaluator | `test-reviewer` | evaluator | — |
| コンテキスト編成 | `context-builder` | context_builder | — |

Generatorが局所計画を内包する2層構成とする（設計書 §3.4 工程別の適用レベル）。

## Skill

`tdd-development@1`を使用する。適用可能な組は`PHASE-6:tdd-generator`であり、`triggers`、`applicable_phases`、`prerequisites`をすべて満たす場合だけ選択する。選択後に`SKILL.md`、必要な参照資料の順で読み込む（設計書 §3.4.1 実行規則2）。

`prerequisites`: 対象Phaseのentry gate PASS、context manifest検証済み、テストコマンド実測済み（設計書 §3.4.1）。

## 手順

1. タスクの受入条件からUT観点を設計する。UTの目的はドメインロジック、状態遷移、条件分岐、計算、例外、境界値を高速に検証することとする（設計書 §6.2）。
2. IT観点を設計する。実ランタイム、永続化層、トランザクション、シリアライズ、メッセージングの実連携を機能単位で保証する範囲とする（設計書 §7、§7.1）。
3. UTとITの振り分けを明示する。UTはRuntime Contextを原則起動せず、DB・Repositoryをインターフェース境界で代替する（設計書 §6.2）。
4. テストデータを定義する。
5. Test ReviewerがUT/IT観点、正常・異常・境界の網羅、テストデータ、UT/IT振り分けを独立評価する。**境界を突いていない境界値、理由の無い分類欠落を承認しない**（設計書 §8.4）。

## 成果物

- Unit Test計画
- Integration Test計画
- テストデータ定義
- `docs/features/<feature-id>/reviews/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `TEST_DESIGN` | exit gate | UT/IT観点、正常・異常・境界、データが定義（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

テスト設計（設計書 §11）。

## 注意事項

- **PHASE-6ではコードを書かない**（設計書 §8.3 TDD Generator行）。テストコードの作成はPHASE-7以降で行う。
- テストの削除・弱体化をしない（設計書 §8.3）。
- 実効権限と利用可能toolsは、Agent定義、Skill定義、context manifest、実行環境のpermissions／sandboxの全制約の積集合とする。Skillによって権限を拡張しない（設計書 §3.4.1 実行規則3）。

## 次工程

`TEST_DESIGN`がPASSした場合だけPHASE-7を`ready`へ遷移させる。
