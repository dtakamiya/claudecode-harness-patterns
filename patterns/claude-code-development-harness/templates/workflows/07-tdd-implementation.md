# PHASE-7: TDD実装

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §6):
  id: PHASE-7
  inputs: task-plan, test-plan, context-manifest
  outputs: unit-tests, production-code, implementation-review-target,
           implementation-review, agent-run
  entry_gate: TEST_DESIGN
  exit_gate: IMPLEMENTATION_EVALUATION
  allowed_agents: continuation, tdd-generator, implementation-evaluator, context-builder
-->

## 目的

UTのRED-GREEN-REFACTORで実装を駆動し、レビュー対象を固定したうえで独立Evaluatorの評価を通す（設計書 §6、§6.6）。

## 開始条件

`TEST_DESIGN`がPASSしていることをOrchestratorが検証する。

## 入力

- タスク計画（`docs/features/<feature-id>/plans/tasks/TASK-XXX.md`）
- テスト計画
- context manifest

## 担当Agent

| 役割 | Agent | profile | Skill |
|---|---|---|---|
| セッション制御 | `continuation` | control / `progress.yaml`直接write禁止 | — |
| Generator | `tdd-generator` | generator | `tdd-development@1` |
| Evaluator | `implementation-evaluator` | evaluator | — |
| コンテキスト編成 | `context-builder` | context_builder | — |

RED-GREEN-REFACTORの短い反復を維持するため、TDD GeneratorがUT作成と最小実装を同一ワークユニットで行い、反復完了後に独立Evaluatorが評価する2層反復構成とする（設計書 §3.4 適用原則）。

## セッション再開

Continuation Agentは`progress.yaml`、最新handoff、未解決事項、context manifest、Git差分、テスト結果を確認してから、**一度に一つのタスク**を実行する。agent-runを出力し、`progress.yaml`の更新はOrchestratorへ要求する（設計書 §3.2、§5.0）。

## 手順（設計書 §6.1 標準サイクル）

1. 要件・受入条件・詳細設計を確認する。
2. UTケースを設計する。
3. UTを作成し、REDを確認する → `UNIT_TEST_RED`
4. 最小実装を行う → `GREEN_CONFIRMATION`
5. REFACTORする。
6. 対象UT・関連UT・全UTを再実行する → `POST_REFACTOR_GREEN`（`UNIT_TEST_GREEN` GateRunのstage）
7. レビュー対象を固定する → `IMPLEMENTATION_REVIEW_TARGET`
8. 独立Evaluatorが評価する → `IMPLEMENTATION_EVALUATION`

**PHASE-7の`POST_REFACTOR_GREEN`はUTだけを対象とし、Integration Testの作成・更新・実行はPHASE-8で行う**（設計書 §6.5）。

### RED Gate（設計書 §6.3）

- テストコードが作成済みで、実行可能である。
- 失敗が、未実装または期待する振る舞いとの差によって起きている。
- **単なるコンパイルエラーだけでRED完了としない。** 必要なら最小の型・インターフェースを用意する。
- 失敗理由をタスクまたは状態ファイルへ記録する。

### GREEN_CONFIRMATION（設計書 §6.4）

- 対象UT、関連UT、全UTが成功している。
- テストの削除、無効化、assertion弱体化を行っていない。
- 対象タスク外の先行実装をしていない。
- 最小限の実装で受入条件を満たしている。

### REFACTOR Gate（設計書 §6.5）

- 重複、責務、命名、例外、トランザクション境界、パッケージ構造を改善する。
- リファクタリング中もUTを短い間隔で実行する。
- `POST_REFACTOR_GREEN`は、リファクタリング後の対象・関連・全UTが成功し、コマンド、終了コード、結果要約を記録した状態とする。**これを満たすまでレビュー対象を固定しない。**

### PREPARATORY_REFACTOR（例外、設計書 §6.5）

通常のREDを安全に書けない構造の場合に限り許可する。

1. baseline GREENを確認する。
2. 既存挙動をcharacterization testで保護し、`GREEN_CONFIRMATION`を記録する。
3. characterization test集合を`GREEN_CONFIRMATION`後に**固定する**。
4. 振る舞いを変えない最小の構造整理を行う。
5. 前後で**同一command**を実行し、同じテストの成功を再確認してから通常のREDへ進む。

制約:

- 固定後のテスト削除・変更・skip、assertion弱体化を禁止し、前後のtest artifact hashが完全一致しなければ失敗とする。
- `baseline_commit`、`result_commit`、`diff_base`、前後の`diff_hash`、同一の`test_command`、各`test_artifact_hash`、結果要約をcheckpointへ記録する。
- 公開API、永続化形式、認証・認可、監査、秘密情報境界を変更しない。必要な場合は独立Development taskへ昇格する。
- 独立レビューが必要、複数責務・複数component、architecture判断、または大規模変更なら別Development taskへ昇格する。
- checkpoint evidenceは最終的な`IMPLEMENTATION_REVIEW_TARGET`へ含める。

## レビュー対象の固定（設計書 §3.8）

`kind: implementation_review`のtargetを作成する。

```yaml
# docs/features/<feature-id>/reviews/targets/TASK-XXX-implementation.yaml
review_target:
  kind: implementation_review
  task: TASK-XXX
  commit_sha: <レビュー対象コードを固定したcheckpoint commit>
  diff_base_sha: <diff base>
  changed_files_manifest: docs/status/changes/TASK-XXX.yaml
  preparatory_refactor_used: true | false
  preparatory_checkpoint_ref: docs/status/checkpoints/TASK-XXX-preparatory-refactor.yaml
  artifact_hashes:
    <path>: sha256:...
  worktree_source_verified: true
```

- `commit_sha`は**レビュー対象のコード（production codeとテスト）を固定したcommit**を指し、review target成果物そのものを含まない。targetファイルは自身を含むcommitのSHAを自身へ記載できない（設計書 §3.8、§10.1）。
- `preparatory_refactor_used: true`の場合、`preparatory_checkpoint_ref`を必須とし、`artifact_hashes`のcheckpoint hashをGateRunの`checkpoint_artifact_hash`と一致させる。欠落・不一致・形式不正はfail-closedとする。
- `preparatory_refactor_used`、`preparatory_checkpoint_ref`、checkpoint artifact mappingはsingleton keyとし、各出現回数が1でなければfail-closedとする。
- **対応する不変なレビュー対象が存在しない場合、`IMPLEMENTATION_EVALUATION`ゲートを開始してはならない**（設計書 §3.8）。

## 成果物

- Unit Test
- プロダクションコード
- `docs/features/<feature-id>/reviews/targets/TASK-XXX-implementation.yaml`
- `docs/features/<feature-id>/reviews/TASK-XXX-implementation.md`
- `docs/status/changes/TASK-XXX.yaml`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `UNIT_TEST_RED` | intra-phase | UTが意図した理由で失敗（設計書 §11） |
| `UNIT_TEST_GREEN` | intra-phase | `POST_REFACTOR_GREEN`完了、対象・関連・全UT成功、テスト弱体化なし、result_commitに証跡を束縛 |
| `IMPLEMENTATION_REVIEW_TARGET` | intra-phase | PHASE-7のcommit SHA、diff base、変更一覧・成果物ハッシュが実装評価用に固定済み |
| `IMPLEMENTATION_EVALUATION` | exit gate | 固定されたreview targetを独立Evaluatorが評価し、テスト弱体化なし、最小実装、受入条件充足 |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

評価順序は`UNIT_TEST_RED` → `UNIT_TEST_GREEN` → `IMPLEMENTATION_REVIEW_TARGET` → `IMPLEMENTATION_EVALUATION`とする（設計書 §11.0、§6.6）。

`UNIT_TEST_RED`と`UNIT_TEST_GREEN`はRED-GREEN-REFACTORの反復ごとに評価する。一つのPhaseRunが複数のGateRunを持つため、`progress.yaml.gates`の値は当該Phaseにおける**最新のGateRun**の結果を表す（設計書 §11.0）。

`gate_definition: UNIT_TEST_GREEN`の場合、runtimeは`stage: POST_REFACTOR_GREEN`とPOST完了証跡の全fieldを必須とし、欠落・不一致をfail-closedにする（設計書 §10.1）。

## ブロック時の戻り先

`UNIT_TEST_RED`はUT作成、`UNIT_TEST_GREEN`は実装、`IMPLEMENTATION_REVIEW_TARGET`はGenerator / Orchestrator、`IMPLEMENTATION_EVALUATION`はTDD実装（設計書 §11）。

## Evaluatorの注意事項

- Implementation Evaluatorは、UTの妥当性、テスト弱体化、最小実装、過剰実装、回帰を評価する。**テスト成功だけで承認しない**（設計書 §8.4）。
- production diffと`preparatory_refactor_used`宣言の一致を検査し、不一致ならfail-closedで差し戻す（設計書 §6.6）。
- **変更範囲の逸脱のような「無いことの証明」は、変更前の状態を持たないAgentには原理的に判定できない。** Runnerまたは`PostToolUse`が生成した変更一覧の証跡を入力として与える。証跡が無い場合、「読んだ限り見当たらない」を根拠にPASSとせず、`residual_risks`へ独立検証できていない旨を記録し、Orchestratorへ機械的検証を要求する（設計書 §11.1）。
- **テスト弱体化の検出は差分の読解であり、再実行に依存しない**（設計書 §3.6.3、§6.4、§8.4）。
- Evaluatorは対象を直接修正しない。review結果とagent-runだけを書く（設計書 §3.6、§3.4.1 実行規則5）。
- evaluator profileのagent-runはログファイルを作成せず、コマンド出力を`summary`へ要約する（設計書 §10.1）。

## commit境界（設計書 §10.1）

review targetを伴う評価では、コード、評価入力、評価出力を三つの境界へ分離する。

- `evaluated_code_commit`: `review_target.commit_sha`と一致。Evaluatorが実際にコードを読み、テストを実行したcommit。
- `evaluated_commit`: review targetと`changes/<task>.yaml`を含む、Evaluator開始前の不変な入力checkpoint。
- `evaluation_step_input_commit`: 当該Evaluatorが開始する時点のcheckpoint。
- `evaluation_output_commit`: review結果とagent-run追加後に**信頼済みRunnerが作る**出力checkpoint。**Evaluator自身が自己申告しない。**

許可差分:

- `evaluated_code_commit` → `evaluated_commit`: review targetと`docs/status/changes/<task>.yaml`の**正確な2パスだけ**。
- `evaluation_step_input_commit` → `evaluation_output_commit`: 当該Evaluatorが新規作成するreview結果とagent-runの**正確な2パスだけ**。

どちらかの差分にproduction codeまたはテストコード、他taskの成果物、既存証跡の変更が含まれる場合はfail-closedで拒否する。

## 次工程

`IMPLEMENTATION_EVALUATION`がPASSするまでPHASE-8へ進まない（設計書 §6.6）。
