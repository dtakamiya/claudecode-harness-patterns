# PHASE-4: 詳細設計

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §5.3):
  id: PHASE-4
  inputs: basic-design, ADR
  outputs: detailed-design
  entry_gate: BASIC_DESIGN
  exit_gate: DETAILED_DESIGN
  allowed_agents: detailed-designer, design-reviewer, context-builder
-->

## 目的

モジュール責務、データモデル、例外、トランザクション境界を定義し、実装とテスト設計が可能な状態にする（設計書 §5.3、§5 工程表）。

## 開始条件

`BASIC_DESIGN`がPASSしていることをOrchestratorが検証する。

## 入力

- PHASE-3の基本設計
- ADR

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Generator | `detailed-designer` | generator / `docs/features/<feature-id>/design`のみwrite |
| Evaluator | `design-reviewer` | evaluator |
| コンテキスト編成 | `context-builder` | context_builder |

上流計画が十分に具体化されている工程のため、Generatorが局所計画を内包し、Evaluatorを独立させる2〜3層構成とする（設計書 §3.4 適用原則、工程別の適用レベル）。

## 手順

1. Detailed Designerがモジュール責務、データモデル、バリデーション、例外、トランザクション境界、ログ、テスト観点を定義する（設計書 §5.3）。
2. 重要な技術判断が生じた場合はADRとして分離する。
3. Design Reviewerが要件適合性、責務、ADR、実装可能性を独立評価する（設計書 §8.4）。

## 成果物

- `docs/features/<feature-id>/design/<name>.md`
- `docs/features/<feature-id>/reviews/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `DETAILED_DESIGN` | exit gate | データ、例外、Tx、実装・テスト観点が定義（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

詳細設計（設計書 §11）。

## 注意事項

- コードの写経設計にしない（設計書 §8.3）。
- Design Reviewerは設計者と同一コンテキストで承認しない（設計書 §8.4）。
- 未確定事項は推測せず、質問・課題として記録する（設計書 §2）。

## 次工程

`DETAILED_DESIGN`がPASSした場合だけPHASE-5を`ready`へ遷移させる。
