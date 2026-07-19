# PHASE-2: 要件レビュー

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §5.2):
  id: PHASE-2
  inputs: requirements
  outputs: requirements-review
  entry_gate: REQUIREMENTS_DRAFT
  exit_gate: REQUIREMENTS_REVIEW
  allowed_agents: requirements-reviewer, context-builder
-->

## 目的

要件を作成者とは独立したコンテキストで評価し、曖昧性・矛盾・漏れを設計工程へ持ち込ませない（設計書 §5.2、§3.4）。

## 開始条件

`REQUIREMENTS_DRAFT`がPASSしていることをOrchestratorが検証する。

## 入力

- PHASE-1の要件成果物
- 受入条件、未解決事項

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Evaluator | `requirements-reviewer` | evaluator |
| コンテキスト編成 | `context-builder` | context_builder |

Evaluator専用工程とし、作成者の自己確認を承認根拠にしない（設計書 §3.4 適用原則）。

## 手順

1. 曖昧性、矛盾、漏れ、テスト不能な表現、権限・監査・セキュリティ観点を検査する（設計書 §5.2）。
2. 各指摘をblocking / non-blockingへ分類する。
3. blockingが残る場合は設計へ進めない。
4. 指摘と必須変更をレビュー成果物へ記録する。Evaluatorは対象を直接修正せず、Generatorへ差し戻す（設計書 §3.4 適用原則、§3.6）。

## 成果物

- `docs/features/<feature-id>/reviews/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

ゲート結果の記録形式（設計書 §5.2）:

```yaml
gate: REQUIREMENTS_REVIEW
status: FAIL
blocking_findings:
  - REV-REQ-003
non_blocking_findings:
  - REV-REQ-007
```

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `REQUIREMENTS_REVIEW` | exit gate | blocking指摘ゼロ（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

要件定義（PHASE-1）（設計書 §11）。

## 注意事項

- 作成者の前提を無批判に引き継がない（設計書 §8.4）。
- Evaluatorは原則read-onlyとし、書込みはレビュー成果物とagent-runだけとする（設計書 §3.6）。
- evaluator profileのagent-runはログファイルを作成せず、コマンド出力を`summary`へ要約する。要約も保存前にredactionし、secret検出時はrunを`failed`とする（設計書 §10.1）。
- 回復可能なゲート不合格では、PhaseRunを`blocked`としてGeneratorへ差し戻す。`failed`は同じrunで回復できない場合だけ使う（設計書 §3.4.1 実行状態と遷移、実行規則5）。

## 次工程

`REQUIREMENTS_REVIEW`がPASSした場合だけPHASE-3を`ready`へ遷移させる。
