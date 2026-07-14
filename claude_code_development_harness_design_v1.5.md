# Claude Code 開発ハーネス設計書

> 要件定義から実装完了までを、工程・成果物・品質ゲートで制御する
>
> **方式:** UT駆動TDD + Integration Test  
> **対象外:** Contract Test（現時点）  
> **状態:** 公式情報照合・拡張ハーネスアーキテクチャ・独立レビュー反映済み

| 文書種別 | 基本設計・運用設計                                 |
|----------|----------------------------------------------------|
| 対象     | Claude Codeを利用したシステム開発                  |
| 対象工程 | 要件定義〜実装完了                                 |
| 版       | Version 1.5 / 2026-07-14（Hooks非依存フォールバック対応版） |

# 1. 文書の目的

本書は、Claude Codeをシステム開発の実行環境として利用し、要件定義から実装完了までを再現性高く進めるためのハーネス設計を定義する。長時間・複数セッションにまたがる開発でも、判断基準、成果物、進捗、品質を失わないことを目的とする。

> **設計の中核**
>
> 工程別ワークフロー、専門エージェント、成果物ハンドオフ、自動品質ゲート、状態管理を組み合わせる。さらに、Initializer／Continuation、Context Builder、Permission Boundary、Harness Evalsを設け、長時間・複数セッション・複数エージェントでの安定性を確保する。実装はUTを主軸としたTDDで進め、機能単位の成立をIntegration Testで保証する。

## 1.1 対象範囲

- 要件定義、要件レビュー、基本設計、詳細設計、実装計画、テスト設計、TDD実装、Integration Test、コードレビュー、完了監査

- Claude Codeのプロジェクト指示、サブエージェント、Skills、Hooks、permissions、sandbox、外部Runner、スクリプト、進捗ファイルの役割分担

- セッション初期化・再開、タスク別コンテキスト編成、権限制御、外部ツール接続、ハーネス評価

- 工程間のハンドオフ形式と品質ゲート

## 1.2 現時点で対象外

- Contract Test

- 本番リリース、デプロイ、運用監視、障害対応の詳細設計

- 特定プロジェクト固有の技術スタックへの完全な最適化

# 2. 基本方針

| **原則**             | **内容**                                                                   |
|----------------------|----------------------------------------------------------------------------|
| 成果物主義           | 会話履歴ではなく、リポジトリ内の文書と状態ファイルを正とする。             |
| 工程分離             | 要件、設計、実装、レビューを分け、各工程の開始条件と終了条件を定義する。   |
| 作成とレビューの分離 | 同一エージェントの自己確認だけに依存せず、独立したEvaluatorを置く。       |
| TDD                  | 細粒度の設計・実装はUTのRED-GREEN-REFACTORで駆動する。                     |
| 結合保証             | 実際のSpring Context、DB、トランザクション等はIntegration Testで検証する。 |
| 決定論的ゲート       | テスト、静的解析、フォーマット等はコマンドの終了コードで判定する。         |
| 推測禁止             | 未確定事項は質問・課題として記録し、重大なものは次工程をブロックする。     |
| トレーサビリティ     | 要件ID、受入条件ID、タスクID、UT、ITを追跡可能にする。                     |

# 3. 全体アーキテクチャ

```text
人間 / プロダクト責任者
          │
          ▼
Development Orchestrator
          │
          ├─ Session Controller
          │    ├─ Initializer Agent
          │    └─ Continuation Agent
          │
          ├─ Context Builder / State Manager
          │
          ├─ Planner
          │       ↓
          ├─ Generator
          │       ↓
          ├─ Deterministic Guardrail
          │    ├─ Capability Profile
          │    ├─ Hooks（利用可能時）
          │    ├─ External Harness Runner（代替）
          │    ├─ Tests / Static Analysis
          │    └─ Permission / Sandbox Boundary
          │       ↓
          ├─ Independent Evaluator
          │    ├─ PASS → 次工程
          │    └─ FAIL → Generatorへ差し戻し
          │
          ├─ Completion Auditor
          └─ Harness Evals
```

オーケストレーターは、すべての作業を自ら実行する万能エージェントではない。現在工程の判定、セッション状態の復元、必要コンテキストの選定、専門エージェントへの委譲、権限適用、ゲート判定、ハンドオフ生成、進捗更新に責務を限定する。

本設計では、LLMによる判断と決定論的な制御を分離する。設計妥当性や要件漏れはEvaluatorが評価し、テスト実行、禁止操作、成果物存在確認など例外なく守る規則は、利用可能なHooks、permissions、sandbox、CI、外部Harness Runner、スクリプトの組合せで機械的に強制する。Hooksは実装手段の一つであり、必須の単一依存点にはしない。

## 3.1 十層モデル

| 層 | 構成要素 | 主な責務 |
|---|---|---|
| 1. プロジェクト規約 | `CLAUDE.md`、`docs/project` | 全工程で守る制約、規約、参照先を定義 |
| 2. セッション制御 | Initializer、Continuation | 初回準備と継続セッションの再開を分離 |
| 3. コンテキスト編成 | Context Builder、context manifest | 各エージェントへ必要最小限の情報を供給 |
| 4. 工程ワークフロー | `.claude/workflows` | 工程ごとの入力、手順、成果物、ゲートを定義 |
| 5. 専門エージェント | `.claude/agents` | Planner、Generator、Evaluatorを工程別に分担 |
| 6. 成果物・ハンドオフ | `docs/*` | 判断と進捗を永続化し、次工程へ引き継ぐ |
| 7. 決定論的ガードレール | Capability Profile、Hooks、External Runner、CI、scripts | 環境能力に応じてテスト、静的解析、禁止操作、終了ゲートを強制 |
| 8. 権限・隔離境界 | permissions、sandbox、worktree | 書込み・シェル・ネットワーク範囲を限定 |
| 9. ツール接続境界 | Tool Gateway、MCP | 外部ツールを用途別・最小権限で公開 |
| 10. ハーネス評価 | `evals/`、grader | 成果物だけでなくハーネス自体の品質を測定 |

## 3.2 Initializer / Continuationアーキテクチャ

長時間開発では、初回セッションと継続セッションを別の役割として扱う。

```text
Initializer Agent
  ├─ リポジトリと既存ドキュメントを調査
  ├─ ビルド・UT・IT・静的解析コマンドを実測
  ├─ 初期ベースラインを記録
  ├─ progress.yamlとfeature/task一覧を初期化
  └─ 初回ハンドオフを作成
          ↓
Continuation Agent
  ├─ progress.yamlを読む
  ├─ 最新ハンドオフと未解決事項を読む
  ├─ リポジトリ状態とテスト状態を再検証
  ├─ 一度に一つのタスクを実行
  └─ 状態・成果物・次アクションを更新
```

### 初期化の終了条件

- 開発・UT・IT・静的解析コマンドが実際に動作する。
- 現在のテスト結果と既知の失敗が記録されている。
- プロジェクト構造、主要モジュール、制約、未解決事項が記録されている。
- 次のContinuation Agentが会話履歴なしで再開できる。

## 3.3 Context Builderアーキテクチャ

すべての文書やコードを毎回読み込ませず、タスクごとに必要な情報を選択する。Context Builderは成果物を作成するエージェントではなく、入力集合を編成する制御コンポーネントとする。

Context manifestは、エージェントが最初に読むべき権威ある入力と探索範囲を指定する。**Context manifest自体はアクセス制御ではない。** 実際の読取り・書込み・Shell・Network制限は、Claude Codeのpermissions、エージェント定義、PreToolUse Hook、sandboxで別途強制する。

```yaml
# docs/context/manifests/TASK-004.context.yaml
schema_version: 1
task: TASK-004
phase: tdd_implementation

context:
  authoritative_inputs:
    - docs/plans/tasks/TASK-004.md
    - docs/requirements/order.md
    - docs/design/order-component.md
    - docs/decisions/ADR-003.md
    - docs/reviews/TASK-004-latest.md
  optional_inputs:
    - docs/project/coding-standards.md
  discovery_roots:
    - src/main/java/com/example/order/
    - src/test/java/com/example/order/
  excluded_from_context:
    - docs/archive/
    - docs/design/payment-component.md

access_policy:
  readable:
    - docs/requirements/**
    - docs/design/**
    - docs/decisions/**
    - docs/plans/tasks/TASK-004.md
    - src/main/java/com/example/order/**
    - src/test/java/com/example/order/**
  writable:
    - src/main/java/com/example/order/**
    - src/test/java/com/example/order/**
    - docs/status/agent-runs/TASK-004/**
  denied:
    - .env
    - .env.*
    - secrets/**
    - docs/archive/**

context_budget:
  source_files: 12
  max_large_documents: 3
```

### コンテキスト選定原則

- Authoritative inputを優先し、会話要約を正本にしない。
- 現在タスクに関係しない文書は除外する。
- 大きなファイルは必要なシンボル・範囲を先に探索する。
- ADR、未解決事項、最新レビュー指摘を必ず含める。
- エージェント終了時に、新たに必要となったコンテキストを記録する。
- `access_policy`は宣言だけで終わらせず、permissionsとPreToolUse Hookへ変換して強制する。
- manifest外の探索が必要になった場合は、理由と追加範囲をagent-run成果物へ記録し、Orchestratorが承認後にmanifestを更新する。

## 3.4 Planner / Generator / Evaluator適用モデル
Anthropicの長時間アプリケーション開発ハーネスで示された3役を、本設計では以下のように適用する。全工程に同数のサブエージェントを機械的に配置するのではなく、判断の大きさと作業粒度に応じて3層または2層を選択する。

```text
Planner
  ├─ 上流成果物と開始条件を確認
  ├─ 作業を検証可能な単位へ分解
  └─ Generatorへの入力・成果物・禁止事項を定義
       ↓
Generator
  ├─ 要件書、設計書、UT、コード、ITを作成
  └─ 機械チェックを実行
       ↓
Evaluator
  ├─ 作成者とは独立したコンテキストで評価
  ├─ blocking / non-blocking指摘を記録
  └─ PASSまたはGeneratorへの差し戻しを判定
```

### 適用原則

- 要件定義、基本設計、実装計画のように影響範囲が大きい工程は、Planner・Generator・Evaluatorを独立させる。
- 詳細設計、Integration Testなど、上流計画が十分に具体化されている工程は、Generatorが局所計画を内包し、Evaluatorを独立させる。
- TDD実装はRED-GREEN-REFACTORの短い反復を維持するため、TDD GeneratorがUT作成と最小実装を同一ワークユニットで行い、反復完了後に独立Evaluatorが評価する。
- 完了監査はEvaluator専用工程とし、実装者による自己判定を完了根拠にしない。
- Evaluatorは原則read-onlyとし、直接修正ではなく指摘と必須変更を成果物に記録する。

### 工程別の適用レベル

| 工程 | Planner | Generator | Evaluator | 推奨構成 |
|---|---|---|---|---|
| 要件定義 | 独立必須 | Requirements Analyst | Requirements Reviewer | 3層 |
| 基本設計 | 独立必須 | Architect | Design Reviewer | 3層 |
| 詳細設計 | Generator内または独立 | Detailed Designer | Design Reviewer | 2〜3層 |
| 実装計画 | 独立必須 | Implementation Planner | Plan Reviewer | 3層 |
| テスト設計 | Generator内 | Test Designer / TDD Generator | Test Reviewer | 2層 |
| TDD実装 | タスク計画をGenerator内包 | TDD Generator | Implementation Evaluator | 2層反復 |
| Integration Test | Generator内 | Integration Test Engineer | Integration Test Reviewer | 2層 |
| コードレビュー | 不要 | 不要 | Code Reviewer | Evaluator専用 |
| 完了監査 | 不要 | 不要 | Completion Auditor | Evaluator専用 |

### 3.4.1 実行メタモデル

本節は工程、エージェント、Skillの共通構造と実行時の関係だけを定義する。工程一覧と終了条件は§5、エージェント一覧と責務は§8、実行状態の永続化形式は§10を正本とし、本節では重複して列挙しない。

#### 定義モデル

| モデル | 必須属性 | 内容 |
|---|---|---|
| `PhaseDefinition` | `id`, `name`, `inputs`, `outputs`, `entry_gate`, `exit_gate`, `allowed_agents` | 工程の静的定義。具体値は§5を参照する |
| `AgentDefinition` | `id`, `layer`, `responsibilities`, `allowed_phases`, `allowed_skills`, `tools`, `access_policy`, `completion_condition` | エージェントの責務と実行境界。具体値は§8および§3.6を参照する |
| `SkillDefinition` | `id`, `version`, `description`, `triggers`, `applicable_phases`, `allowed_agents`, `inputs`, `outputs`, `prerequisites`, `tools` | 再利用可能な手順の静的定義。本文は各`SKILL.md`を正本とする |

静的定義の最小カタログは次のとおりとする。ここにないIDは未定義として扱い、追加時は本表と参照先を同時に更新する。

| モデル | IDと正本 |
|---|---|
| `PhaseDefinition` | `PHASE-0`〜`PHASE-10`。名称、成果物、終了条件、Agent構成は§5の同番号Phaseを正本とする |
| `AgentDefinition` | 後掲のAgentDefinition実値表に記載したID。責務と禁止事項は§8、権限の基準は§3.6を正本とする |
| `SkillDefinition` | `tdd-development@1`（`applicable_phases`: `PHASE-6`, `PHASE-7`, `PHASE-8`、`allowed_agents`: `tdd-generator`, `integration-test-engineer`）。構成とロード規則は§3.7、工程手順は§6〜§7を正本とする。その他のSkillは各`SKILL.md`の追加だけでは登録されず、本表へのID追加を要する |

`PhaseDefinition`の実値は次のとおりとする。`—`は入力または開始ゲートを必要としないことを表す。

| id / name | inputs | outputs | entry_gate | exit_gate | allowed_agents |
|---|---|---|---|---|---|
| `PHASE-0` 初期化 | repository | baseline, commands, progress, handoff | — | `INITIALIZATION` | initializer, harness-reviewer |
| `PHASE-1` 要件定義 | baseline, stakeholder-input | requirements, acceptance-criteria, open-items | `INITIALIZATION` | `REQUIREMENTS_DRAFT` | requirements-planner, requirements-analyst |
| `PHASE-2` 要件レビュー | requirements | requirements-review | `REQUIREMENTS_DRAFT` | `REQUIREMENTS_REVIEW` | requirements-reviewer |
| `PHASE-3` 基本設計 | approved-requirements | basic-design, ADR | `REQUIREMENTS_REVIEW` | `BASIC_DESIGN` | architecture-planner, architect, design-reviewer |
| `PHASE-4` 詳細設計 | basic-design, ADR | detailed-design | `BASIC_DESIGN` | `DETAILED_DESIGN` | detailed-designer, design-reviewer |
| `PHASE-5` 実装計画 | detailed-design | task-plans | `DETAILED_DESIGN` | `IMPLEMENTATION_PLAN` | implementation-planner, task-generator, plan-reviewer |
| `PHASE-6` テスト設計 | task-plans, acceptance-criteria | unit-test-plan, integration-test-plan, test-data | `IMPLEMENTATION_PLAN` | `TEST_DESIGN` | tdd-generator, test-reviewer |
| `PHASE-7` TDD実装 | task-plan, test-plan, context-manifest | unit-tests, production-code, agent-run | `TEST_DESIGN` | `UNIT_TEST_GREEN` | continuation, tdd-generator, implementation-evaluator |
| `PHASE-8` Integration Test | production-code, integration-test-plan | integration-tests, test-evidence | `UNIT_TEST_GREEN` | `INTEGRATION_TEST` | integration-test-engineer, integration-test-reviewer |
| `PHASE-9` コードレビュー | fixed-review-target, test-evidence | code-review | `INTEGRATION_TEST` | `CODE_REVIEW` | code-reviewer |
| `PHASE-10` 完了監査 | all-artifacts, traceability, reviews | completion-audit, final-handoff | `CODE_REVIEW` | `COMPLETION` | completion-auditor |

Agentの`tools`、`access_policy`、`completion_condition`は次の共通profileで解決する。

| profile | tools | access_policy | completion_condition |
|---|---|---|---|
| `control` | Read, Search, state-runner | project read、`progress.yaml` single-writer | 状態・handoff・次actionを原子的に更新 |
| `planner` | Read, Search, Write | inputs read、計画成果物のみwrite、Network原則なし | 入力・範囲・終了条件・禁止事項が定義済み |
| `generator` | Read, Search, Write, Bash | manifestと§3.6の積集合 | 必須成果物・コマンド証跡・agent-runが揃う |
| `evaluator` | Read, Search, Bash | 対象read、review/agent-runのみwrite、Networkなし | blocking分類とPASS/FAILが記録済み |

| AgentDefinition id | layer | allowed_phases | allowed_skills | profile / 例外 |
|---|---|---|---|---|
| development-orchestrator | control | PHASE-0..10 | — | control |
| initializer | generator | PHASE-0 | — | generator / production code write禁止 |
| continuation | control | PHASE-7 | — | control / `progress.yaml`直接write禁止 |
| requirements-planner | planner | PHASE-1 | — | planner |
| requirements-analyst | generator | PHASE-1 | — | generator / docs/requirementsのみwrite |
| requirements-reviewer | evaluator | PHASE-2 | — | evaluator |
| architecture-planner | planner | PHASE-3 | — | planner |
| architect | generator | PHASE-3 | — | generator / docs/design, docs/decisionsのみwrite |
| design-reviewer | evaluator | PHASE-3, PHASE-4 | — | evaluator |
| detailed-designer | generator | PHASE-4 | — | generator / docs/designのみwrite |
| implementation-planner | planner | PHASE-5 | — | planner |
| task-generator | generator | PHASE-5 | — | generator / docs/plansのみwrite |
| plan-reviewer | evaluator | PHASE-5 | — | evaluator |
| tdd-generator | generator | PHASE-6, PHASE-7 | tdd-development@1 | generator |
| test-reviewer | evaluator | PHASE-6 | — | evaluator |
| implementation-evaluator | evaluator | PHASE-7 | — | evaluator |
| integration-test-engineer | generator | PHASE-8 | tdd-development@1 | generator / test codeのみwrite |
| integration-test-reviewer | evaluator | PHASE-8 | — | evaluator |
| code-reviewer | evaluator | PHASE-9 | — | evaluator |
| completion-auditor | evaluator | PHASE-10 | — | evaluator |
| harness-reviewer | evaluator | PHASE-0 | — | evaluator |

`tdd-development@1`は次の実値を持つ。

| 属性 | 値 |
|---|---|
| description | UT駆動TDDとIntegration Testを、検証証跡付きで実行する手順 |
| triggers | test-plan作成、RED-GREEN-REFACTOR、Integration Test作成 |
| applicable phase-agent pairs | `PHASE-6:tdd-generator`, `PHASE-7:tdd-generator`, `PHASE-8:integration-test-engineer` |
| inputs | task-plan, acceptance-criteria, test-policy, context-manifest |
| outputs | test-planまたはtest-code、test-evidence、agent-run |
| prerequisites | 対象Phaseのentry gate PASS、context manifest検証済み、テストコマンド実測済み |
| tools | Read, Search, Write, Bash（Agent・manifest・sandboxとの積集合に限定） |

#### 関係と多重度

```text
PhaseDefinition 1 ── 0..* PhaseRun
PhaseRun       1 ── 0..* AgentRun
AgentDefinition 1 ── 0..* AgentRun
AgentRun       1 ── 0..* SkillUse
SkillDefinition 1 ── 0..* SkillUse
PhaseRun       1 ── 1..* GateRun
GateRun        1 ── 0..* Artifact
GateRun        1 ── 0..* TestEvidence
```

`GateRun`は一つのゲート判定実行を表し、ArtifactまたはTestEvidenceを少なくとも一つ必要とする。`PhaseDefinition`と`AgentDefinition`、`AgentDefinition`と`SkillDefinition`は多対多であり、Phase側の`allowed_agents`とAgent側の`allowed_phases`、Agent側の`allowed_skills`とSkill側の`allowed_agents`が相互に許可した場合だけ有効とする。片側の記載欠落、不一致、未定義IDはfail-closedで拒否する。実行時の割当は`PhaseRun`、`AgentRun`、`SkillUse`として記録する。

#### 実行状態と遷移

| 実行モデル | 状態 | 許可する主な遷移 |
|---|---|---|
| `PhaseRun` | `pending`, `ready`, `in_progress`, `blocked`, `review`, `passed`, `failed` | `pending → ready → in_progress → review → passed/failed`、未解決事項は`in_progress/review → blocked`、blocking解消時は`blocked → in_progress/review` |
| `AgentRun` | `queued`, `running`, `awaiting_review`, `passed`, `failed`, `aborted` | `queued → running → awaiting_review → passed/failed`、中止時は`queued/running → aborted` |
| `SkillUse` | `eligible`, `selected`, `loaded`, `running`, `completed`, `failed` | `eligible → selected → loaded → running → completed/failed` |

`PhaseRun`の`passed/failed`、`AgentRun`の`passed/failed/aborted`、`SkillUse`の`completed/failed`を終端状態とする。差し戻しや再試行では既存runを遷移・上書きせず、失敗runを`parent_run_id`で参照する新しい`PhaseRun`、`AgentRun`または`SkillUse`を作成する。永続化するフィールドと楽観ロックは§10に従う。

`blocked → in_progress/review`は、全blocking issueの解消証跡をOrchestratorが検証した場合だけ許可し、遷移の実行者もOrchestratorに限定する。

#### 実行規則

1. Development Orchestratorは§5の現在工程とタスクから、`allowed_agents`を満たすAgentを選択する。
2. AgentとSkillは前述の双方向許可を満たした候補だけを選ぶ。Skillはさらに`triggers`、`applicable_phases`、`prerequisites`をすべて満たす場合に選択し、選択後に`SKILL.md`、必要な参照資料の順で読み込む。
3. 実効権限と利用可能toolsは、Agent定義、Skill定義、context manifest、実行環境のpermissions／sandboxの全制約の積集合とする。未指定または競合時はfail-closedとし、Skillによって権限を拡張しない。
4. 一つの`AgentRun`は一つの工程・タスクを対象とし、使用Skill、入力revision、成果物、コマンド証跡、結果を§10のagent-run成果物へ記録する。証跡へsecretの値を保存してはならず、コマンド引数・標準出力・標準エラー・成果物パスを保存前にredactionする。secret検出時はrunを`failed`にし、安全な証跡へ置換するまでゲート判定に利用しない。
5. GeneratorとEvaluatorは別の`AgentRun`とし、Evaluatorは作成対象を直接修正しない。ゲート不合格時は現在の`PhaseRun`を終端状態`failed`とし、指摘と失敗runへの親参照を持つ新規runを同じ工程のGeneratorへ差し戻す。
6. `progress.yaml`と集約された`PhaseRun`状態の更新者はDevelopment Orchestratorだけとする。AgentとSkillは更新を要求できるが、直接更新しない。
7. `exit_gate`がPASSし、blocking issueがなく、必須成果物と証跡が揃った場合だけ次の工程を`ready`へ遷移させる。

## 3.5 Deterministic Guardrailアーキテクチャ

必ず実行すべき処理を、LLMの自主判断に任せない。ガードレールは、予防・検知・復旧の3段階に分離する。

| 種別 | タイミング | 強制処理の例 |
|---|---|---|
| Preventive | permissions / `PreToolUse` | 保護ファイルへの読書き拒否、危険コマンド拒否、対象外ディレクトリ変更の遮断、Bashリダイレクト先の検査 |
| Context injection | `SubagentStart` | 許可された工程、タスク、権威ある入力、書込み範囲、禁止事項の注入 |
| Detective | `PostToolUse` / FileChanged | formatter、lint、変更ファイル記録、秘密情報スキャン、不要変更検出 |
| Completion check | `SubagentStop` | 必須成果物、レビュー対象SHA、テスト証跡、agent-run結果の存在確認 |
| State commit | `Stop` | Orchestratorによる`progress.yaml`更新、revision整合、未解決ブロッカー、全ゲート状態の確認 |
| Recovery | Hook / script | 秘密情報検出時のタスクFAIL化、自動コミット禁止、チェックポイントへの復旧、人間へのエスカレーション |
| CI | CI | 全UT、全IT、静的解析、依存脆弱性検査、アーキテクチャテスト |

`PostToolUse`は操作後の検知であり、秘密情報の書込み自体を予防できない。機密パスと危険操作はpermissionsおよび`PreToolUse`で遮断し、`PostToolUse`は差分検査と復旧判断に使用する。

Hooksは利用可能な場合、補助的な注意喚起ではなく、失敗時に処理を停止できる終了コードを持つガードレールとして設計する。ただしHookだけをサンドボックスやpermissionsの代替にしない。Hooksを利用できない環境では、同等の効果をExternal Harness Runner、permissions、sandbox、CIへ移管する。

## 3.5.1 Capability ProfileとHooks非対応フォールバック

ハーネスは起動時に実行環境の能力を検出し、`docs/project/harness-capabilities.yaml`へ記録する。品質ゲートは特定の機能名ではなく、禁止操作と終了条件が機械的に強制されるという効果を要求する。

```yaml
profile: compatible_no_hooks
capabilities:
  hooks:
    available: false
  permissions:
    available: true
  sandbox:
    available: true
  ci:
    available: true
  worktree:
    available: true
  external_runner:
    available: true

fallbacks:
  pre_tool_guard: permissions_and_sandbox
  post_tool_validation: explicit_quality_script
  subagent_stop_gate: orchestrator_verification
  stop_gate: external_runner
  state_update: orchestrator_single_writer
```

### 実行モード

| モード | 構成 | 利用判定 |
|---|---|---|
| Full | Hooks＋permissions＋sandbox＋CI | 本格運用可能 |
| Compatible | permissions＋sandbox＋External Runner＋CI | 本格運用可能 |
| Manual | permissionsのみ、終了確認は人間 | PoC限定 |

Hooksが使えないだけでは設計をFAILにしない。`Compatible`モードで、事前制御、終了検証、状態更新、CIゲートが外部Runnerを含む機械的な仕組みで成立している場合は次工程へ進める。プロンプトによる禁止指示だけに依存する`Manual`モードは本格運用に使用しない。

### Hooksと代替手段の対応

| Hooks利用時 | Hooks非対応時 |
|---|---|
| `PreToolUse` | permissions、sandbox、専用コマンド、OS権限 |
| `PostToolUse` | Agent終了後の`quality-gate.sh`、Git diff検査 |
| `SubagentStop` | Orchestratorによるagent-runと成果物検証 |
| `Stop` | External Harness Runnerの終了ゲート |
| FileChanged | Git diffベースの変更範囲・secret scan |
| WorktreeCreate | `create-task-worktree.sh`による明示生成 |

### External Harness Runnerの標準フロー

```text
External Harness Runner
  ↓ Capability Profile検証
  ↓ Agent起動
  ↓ agent-run.yaml出力
  ↓ quality-gate.sh実行
  ↓ 成果物・テスト・SHA・変更範囲を検証
  ↓ Independent Evaluator起動
  ↓ verify-agent-result.sh実行
  ↓ Orchestratorだけがprogress.yamlを更新
  ↓ PASS時のみ次工程へ進む
```

## 3.6 Permission Boundary / Sandboxアーキテクチャ

エージェントごとにツール権限と編集範囲を限定する。エージェント定義に記載したWrite範囲は論理ルールであり、記述しただけではファイルACLにならない。Fullモードでは`tools`／`disallowedTools`／`permissionMode`とagent-scoped `PreToolUse` Hookを使用する。Compatibleモードではpermissions、sandbox、作業ディレクトリ分離、専用コマンド、External Runnerによる事後検証を組み合わせて同等の効果を強制する。

| エージェント | 論理Write範囲 | Shell / Network | 強制手段 | 禁止事項 |
|---|---|---|---|---|
| Requirements Analyst | `docs/requirements/**` | Shell原則なし、調査時のみNetwork | tools制限＋Hook、またはsandbox＋Runner検証 | ソースコード編集 |
| Architect | `docs/design/**`, `docs/decisions/**` | 読取系のみ、調査時のみNetwork | tools制限＋Hook、またはsandbox＋Runner検証 | 実装変更 |
| TDD Generator | 対象モジュール、テスト、agent-run成果物 | build/test限定、Network原則なし | permissions＋sandbox＋Bash allowlist＋HookまたはRunner検証 | 対象外タスク、秘密情報、CI無効化 |
| Integration Test Engineer | ITとテスト支援設定 | test/container限定、ローカルスタブのみ | permissions＋接続先allowlist | 本番環境接続 |
| Evaluator | `docs/reviews/**`, `docs/status/agent-runs/**` | test/static analysis、Network原則なし | 原則Read-only＋レビュー出力のみ許可 | プロダクションコード直接修正 |
| Completion Auditor | `docs/reviews/**`, `docs/status/agent-runs/**` | 検証コマンドのみ、Networkなし | Read-only＋監査結果のみ許可 | 成果物の自己修正、`progress.yaml`直接更新 |

```yaml
# .claude/agents/architect.md の概念例
---
name: architect
tools: [Read, Grep, Glob, Edit, Write]
disallowedTools: [Bash]
permissionMode: dontAsk
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: .claude/hooks/enforce-agent-write-scope.sh architect
---
```

Evaluatorは原則read-onlyで評価し、修正はGeneratorへ差し戻す。例外的にレビュー文書とagent-run結果のみ書込みを許可する。`progress.yaml`はOrchestratorだけが更新する。

## 3.7 Progressive Disclosure Skills

Skillは一つの巨大な`SKILL.md`に全情報を詰め込まず、短い入口、参照資料、テンプレート、実行スクリプトに分割する。

```text
.claude/skills/tdd-development/
├─ SKILL.md
├─ references/
│  ├─ unit-test-policy.md
│  ├─ integration-test-policy.md
│  ├─ java-testing-patterns.md
│  └─ testcontainers-guide.md
├─ templates/
│  ├─ task-template.md
│  └─ test-plan-template.md
└─ scripts/
   ├─ run-unit-tests.sh
   └─ run-integration-tests.sh
```

`SKILL.md`には、利用条件、標準手順、必要時に読む参照先だけを置く。技術固有ノウハウは`references/`へ分離し、必要な場合だけ読み込む。

## 3.8 Worktree Isolationとレビュー対象固定

並列実行は依存関係の薄い作業だけに限定し、各GeneratorへGit worktreeを割り当てる。ただし、worktreeを作成しただけでは親セッションの未コミット変更や意図したタスク状態が自動的にレビュー側へ引き継がれるとは限らない。

```text
repository/
├─ main
└─ .worktrees/
   ├─ TASK-101/
   ├─ TASK-102/
   └─ REVIEW-201/
```

### レビュー開始の必須条件

Evaluatorは、作成者の作業ディレクトリ名ではなく、不変なレビュー対象を受け取る。

```yaml
review_target:
  task: TASK-004
  commit_sha: abc123def456
  diff_base_sha: 789xyz000111
  changed_files_manifest: docs/status/changes/TASK-004.yaml
  artifact_hashes:
    docs/design/order-component.md: sha256:...
  worktree_source_verified: true
```

次のいずれかを採用する。

1. Generatorがチェックポイントコミットを作成し、そのcommit SHAからReviewer用worktreeを作成する。
2. Reviewerを現在のcheckout上でread-only実行し、未コミット差分を直接レビューさせる。
3. `WorktreeCreate` Hookまたは専用スクリプトで分岐元SHAを明示する。
4. パッチと成果物ハッシュを生成し、Reviewer環境へ適用・検証する。

`commit_sha`または同等の不変なレビュー対象が存在しない場合、`IMPLEMENTATION_EVALUATION`と`CODE_REVIEW`ゲートを開始してはならない。

### 並列化できる作業

- 異なるモジュールの独立タスク
- 対象commitが固定された読み取り専用レビュー
- 異なる文書の作成
- 競合しないテスト追加

### 並列化しない作業

- 同一クラス、同一設定、同一DBスキーマの変更
- 前後依存のあるタスク
- 一つのRED-GREEN-REFACTORサイクル内部
- 同一成果物に対する複数Generatorの直接編集
- 未コミット変更を暗黙に引き継ぐ前提のReviewer worktree起動

## 3.9 Tool Gateway / MCPアーキテクチャ

Jira、GitHub、仕様管理、Slack、データベースなどの外部機能は、汎用APIをそのまま大量公開せず、用途別の狭いツールとして公開する。

```text
Agent
  ↓
Tool Gateway
  ├─ 入力検証
  ├─ 権限判定
  ├─ 情報量削減
  ├─ 冪等性・現在状態確認
  └─ 監査ログ
  ↓
MCP Server / External System
```

推奨インターフェース例:

```text
get_task_requirements(task_id)
get_open_questions(task_id)
publish_review_result(task_id, result)
update_task_status(task_id, expected_status, new_status)
get_pull_request_diff(pr_number)
```

書込み系ツールには`expected_status`や対象IDを必須とし、曖昧な自然言語だけで更新しない。

## 3.10 Harness Evalsアーキテクチャ

成果物の品質だけでなく、プロンプト、エージェント構成、Hooks、コンテキスト選定が安定して機能するかを継続評価する。

```text
evals/
├─ requirements/
│  ├─ ambiguous-requirement/
│  └─ conflicting-requirement/
├─ planning/
│  ├─ oversized-task/
│  └─ hidden-dependency/
├─ implementation/
│  ├─ weakened-test/
│  ├─ transaction-boundary/
│  └─ unnecessary-file-change/
└─ review/
   ├─ false-pass/
   └─ missing-requirement-coverage/
```

### Grader構成

- Code-based grader: テスト結果、変更範囲、必須ファイル、禁止操作を判定。
- Model-based grader: 要件漏れ、設計妥当性、レビュー品質を評価。
- Human grader: 高リスク判断、曖昧な仕様、誤検知・見逃しをサンプリング評価。

### 主要メトリクス

```yaml
requirement_coverage: 1.0
acceptance_criteria_coverage: 1.0
blocking_defect_escape_rate: 0
reviewer_false_pass_rate: 0
unnecessary_file_changes: 0
handoff_recovery_success_rate: 1.0
human_rework_count: 0
```

失敗事例は、そのまま新しいevalケースへ追加し、ハーネス変更による回帰を検出する。

# 4. 推奨ディレクトリ構成

```text
CLAUDE.md
.claude/
├─ agents/
│  ├─ development-orchestrator.md
│  ├─ project-initializer.md
│  ├─ continuation-worker.md
│  ├─ context-builder.md
│  ├─ requirements-planner.md
│  ├─ requirements-analyst.md
│  ├─ requirements-reviewer.md
│  ├─ architecture-planner.md
│  ├─ architect.md
│  ├─ detailed-designer.md
│  ├─ design-reviewer.md
│  ├─ implementation-planner.md
│  ├─ plan-reviewer.md
│  ├─ tdd-generator.md
│  ├─ implementation-evaluator.md
│  ├─ integration-test-engineer.md
│  ├─ integration-test-reviewer.md
│  ├─ code-reviewer.md
│  ├─ harness-reviewer.md
│  └─ completion-auditor.md
├─ rules/
│  ├─ testing.md
│  ├─ security.md
│  ├─ permissions.md
│  └─ worktree-isolation.md
├─ workflows/                 # 独自工程文書。Skill/CLAUDE.mdから参照
│  ├─ 00-initialization.md
│  ├─ 01-requirements.md
│  ├─ 02-requirements-review.md
│  ├─ 03-basic-design.md
│  ├─ 04-detailed-design.md
│  ├─ 05-implementation-plan.md
│  ├─ 06-test-design.md
│  ├─ 07-tdd-implementation.md
│  ├─ 08-integration-test.md
│  ├─ 09-code-review.md
│  └─ 10-completion.md
├─ skills/
│  ├─ requirements/
│  │  ├─ SKILL.md
│  │  ├─ references/
│  │  └─ templates/
│  ├─ design/
│  ├─ tdd-development/
│  ├─ integration-testing/
│  ├─ review/
│  └─ handoff/
├─ hooks/
│  ├─ pre-tool-use.sh
│  ├─ post-tool-use.sh
│  ├─ subagent-stop.sh
│  └─ stop-gate.sh
├─ settings.json
└─ settings.local.json         # 個人用・Git管理外

docs/
├─ project/
├─ requirements/
├─ design/
├─ plans/tasks/
├─ decisions/
├─ tests/
├─ reviews/
├─ handoffs/
├─ context/
│  ├─ manifests/
│  └─ summaries/
└─ status/
   ├─ progress.yaml
   ├─ baseline.yaml
   └─ agent-runs/

evals/
├─ cases/
├─ graders/
├─ fixtures/
└─ reports/

scripts/
├─ initialize-project.sh
├─ build-context-manifest.sh
├─ validate-requirements.sh
├─ run-unit-tests.sh
├─ run-integration-tests.sh
├─ quality-gate.sh
├─ verify-permissions.sh
├─ create-task-worktree.sh
├─ run-harness-evals.sh
└─ verify-completion.sh
```

# 5. 工程設計

| **Phase** | **工程**         | **エージェント構成** | **主要成果物**                     | **終了条件**                     |
|-----------|------------------|----------------------|------------------------------------|----------------------------------|
| 0 | 初期化 | Initializer → Harness Reviewer | baseline、commands、progress、初回handoff | 継続Agentが履歴なしで再開できる |
| 1 | 要件定義 | Planner → Analyst → Reviewer | 要件、受入条件、未解決事項 | 要件IDと検証可能な受入条件がある |
| 2 | 要件レビュー | Requirements Reviewer | レビュー結果、修正版要件 | 重大な曖昧性・矛盾が解消 |
| 3 | 基本設計 | Planner → Architect → Reviewer | 構成、境界、データフロー、ADR | 非機能要件を含む方式が確定 |
| 4 | 詳細設計 | Designer → Design Reviewer | 責務、API、データ、例外、Tx | 実装とテスト設計が可能 |
| 5 | 実装計画 | Planner → Task Generator → Plan Reviewer | 独立した実装タスク群 | 各タスクが小さく検証可能 |
| 6 | テスト設計 | TDD Generator → Test Reviewer | UT観点、IT観点、テストデータ | 正常・異常・境界が定義 |
| 7 | TDD実装 | Continuation + TDD Generator ↔ Evaluator | UT、プロダクションコード、context manifest | UT RED→GREEN→REFACTOR完了 |
| 8 | Integration Test | IT Engineer → IT Reviewer | ITコード、実行結果 | 実連携・DB・Tx等が成功 |
| 9 | コードレビュー | Code Reviewer | レビュー指摘と対応 | ブロッキング指摘ゼロ |
| 10 | 完了監査 | Completion Auditor | トレーサビリティ、完了判定 | DoDと全品質ゲートを満たす |

## 5.0 Phase 0: 初期化と継続準備

Initializer Agentは、実装を開始する前に実行環境と既存状態を検証する。

- リポジトリ構造、主要モジュール、既存ドキュメントを調査する。
- ビルド、UT、IT、静的解析のコマンドを推測せず実行して確認する。
- 既知の失敗、環境依存、必要なサービスを`baseline.yaml`へ記録する。
- `progress.yaml`、タスク一覧、最初のcontext manifest、agent-runディレクトリを作成する。
- Harness Reviewerが、継続セッションから再開可能かを評価する。

以降のセッションはContinuation Agentが開始し、必ず最新の状態、ハンドオフ、context manifest、Git差分、テスト結果を確認してから一つの作業単位を選択する。Continuation Agentはagent-runを出力し、`progress.yaml`の更新はOrchestratorへ要求する。

## 5.1 Phase 1: 要件定義

- 機能要件と非機能要件に一意なIDを付与する。例: REQ-F-001、REQ-NF-001

- 各要件に検証可能な受入条件を付与する。例: AC-001-01

- 前提、制約、スコープ外、未解決事項を明示する。

- 設計・実装上の手段を早期に固定しすぎない。

## 5.2 Phase 2: 要件レビュー

- 曖昧性、矛盾、漏れ、テスト不能な表現、権限・監査・セキュリティ観点を検査する。

- 指摘をblocking / non-blockingに分類し、blockingが残る場合は設計へ進めない。

```yaml
gate: REQUIREMENTS_REVIEW
status: FAIL
blocking_findings:
- REV-REQ-003
non_blocking_findings:
- REV-REQ-007
```

## 5.3 Phase 3〜4: 基本設計・詳細設計

- 基本設計ではシステム境界、コンポーネント、データフロー、外部連携、セキュリティ、障害方針を定義する。

- 詳細設計ではモジュール責務、データモデル、バリデーション、例外、トランザクション境界、ログ、テスト観点を定義する。

- 重要な技術判断はADRとして分離し、理由・代替案・影響を残す。

## 5.4 Phase 5: 実装計画

実装タスクは、一つのClaude Codeセッションまたは一つのワークユニットで完了できる大きさに分割する。各タスクは要件、受入条件、想定変更範囲、UT、IT、依存関係、スコープ外を持つ。

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

# 6. TDD実装方針

> **テストの役割分担**
>
> UTは細粒度・高速なTDDループで設計と実装を駆動する。Integration Testは、Spring Context、DB、トランザクション、シリアライズ、メッセージング等の実連携を機能単位で保証する。

## 6.1 標準サイクル

```
要件・受入条件・詳細設計を確認
↓
UTケース設計
↓
UT作成 → RED確認
↓
最小実装 → GREEN確認
↓
REFACTOR
↓
関連UT・全UT
↓
Integration Test作成・更新
↓
Integration Test実行
↓
レビュー・完了判定
```

## 6.2 Unit Testポリシー

| **項目**       | **方針**                                                             |
|----------------|----------------------------------------------------------------------|
| 目的           | ドメインロジック、状態遷移、条件分岐、計算、例外、境界値を高速に検証 |
| Spring Context | 原則として起動しない                                                 |
| DB・Repository | インターフェース境界で代替し、テスト対象を小さく保つ                 |
| 外部API        | モックまたはスタブ                                                   |
| 実行速度       | 頻繁に全関連UTを実行できる速度を維持                                 |
| 命名           | 振る舞いと期待結果が分かる名前にする                                 |
| 対象           | 一つのクラス、関数、または小さな協調単位                             |

## 6.3 RED Gate

- テストコードが作成済みで、実行可能である。

- 失敗が、未実装または期待する振る舞いとの差によって起きている。

- 単なるコンパイルエラーだけでRED完了としない。必要なら最小の型・インターフェースを用意する。

- 失敗理由をタスクまたは状態ファイルへ記録する。

## 6.4 GREEN Gate

- 対象UT、関連UT、全UTが成功している。

- テストの削除、無効化、assertion弱体化を行っていない。

- 対象タスク外の先行実装をしていない。

- 最小限の実装で受入条件を満たしている。

## 6.5 REFACTOR Gate

- 重複、責務、命名、例外、トランザクション境界、パッケージ構造を改善する。

- リファクタリング中もUTを短い間隔で実行する。

- リファクタリング後に全UTと必要なIntegration Testを再実行する。

# 7. Integration Test方針

| **項目**       | **方針**                               |
|----------------|----------------------------------------|
| Spring Context | 実際の構成を使用                       |
| Database       | Testcontainers等で本番に近いDBを使用   |
| Repository     | 実実装を使用                           |
| Transaction    | 実際のコミット、ロールバック境界を検証 |
| Serialization  | 実際のJSON/メッセージ変換を使用        |
| 内部Service    | 原則としてモックしない                 |
| 外部システム   | Stub、WireMock、コンテナ等で制御       |
| 実行タイミング | 機能単位の節目、PR/CI、完了ゲート      |

## 7.1 Integration Testで確認する代表項目

- Controller → Application Service → Repository → Databaseの連携

- JPAマッピング、SQL、制約、ロック、トランザクション

- Spring Security、バリデーション、例外ハンドリング

- Kafka等のメッセージ送受信、シリアライズ、イベント発行条件

- 外部APIアダプターの要求・応答変換と障害時挙動

# 8. エージェント設計

## 8.1 制御層

| エージェント | 役割 | 禁止・注意事項 |
|---|---|---|
| Development Orchestrator | 現在工程、入力、呼び出すPlanner/Generator/Evaluator、ゲート、差し戻し、handoff、progressを管理 | 成果物を直接作成しない。品質ゲートを自己判断で省略しない |

## 8.2 Planner層

| エージェント | 主責務 | 適用工程 |
|---|---|---|
| Requirements Planner | 調査範囲、ステークホルダー、論点、必要成果物、質問事項を計画 | 要件定義 |
| Architecture Planner | 設計論点、非機能要件、代替案、ADR候補、調査順序を計画 | 基本設計 |
| Implementation Planner | 設計を小さく検証可能なタスクへ分解し、依存関係と実行順を決定 | 実装計画 |

Plannerは成果物本文を完成させず、Generatorが迷わず作業できる入力、範囲、終了条件、禁止事項を定義する。

## 8.3 Generator層

| エージェント | 主責務 | 禁止・注意事項 |
|---|---|---|
| Requirements Analyst | 要求構造化、要件ID、受入条件、未解決事項 | 実装方式を推測で決めない |
| Architect | 構成、境界、非機能方式、ADR | 詳細実装へ踏み込みすぎない |
| Detailed Designer | 責務、データ、例外、Tx、テスト観点 | コードの写経設計にしない |
| TDD Generator | UT設計、RED確認、最小実装、GREEN、REFACTORを短い反復で実施 | テスト削除・弱体化、対象外実装、RED前の本実装をしない |
| Integration Test Engineer | 実連携、DB、Tx、設定、メッセージングを検証 | 内部を過剰にモックしない |

## 8.4 Evaluator層

| エージェント | 主責務 | 禁止・注意事項 |
|---|---|---|
| Requirements Reviewer | 曖昧性、矛盾、漏れ、テスト可能性の検査 | 作成者の前提を無批判に引き継がない |
| Design Reviewer | 要件適合性、非機能要件、責務、ADR、実装可能性の検査 | 設計者と同一コンテキストで承認しない |
| Plan Reviewer | タスク粒度、依存関係、受入条件、UT/IT、スコープの検査 | 巨大タスクや検証不能タスクを承認しない |
| Implementation Evaluator | UTの妥当性、テスト弱体化、最小実装、過剰実装、回帰を評価 | テスト成功だけで承認しない |
| Integration Test Reviewer | ITの実構成性、テストデータ、障害系、Tx、モック境界を評価 | 実装者の説明のみを根拠にしない |
| Code Reviewer | 要件適合性、ロジック、保守性、セキュリティ、回帰を検査 | 機械テスト成功だけで承認しない |
| Completion Auditor | 要件〜設計〜タスク〜UT〜IT〜実装の追跡と完了判定 | 未解決の重大事項を見逃さない |
| Harness Reviewer | ハーネス自体の公式仕様適合性、工程整合性、実行可能性を評価 | 作成エージェントの説明ではなく成果物と一次資料を確認する |

## 8.5 TDD実装における役割統合

TDDではUT作成者と実装者を完全に別サブエージェントへ分割すると、RED-GREEN-REFACTORの反復が遅くなりやすい。そのため、標準構成ではTDD Generatorが一つのタスク内でUT作成と最小実装を担当し、独立したImplementation Evaluatorが反復完了後に評価する。

```text
Implementation Planner
  ↓
TDD Generator
  ├─ UT作成
  ├─ RED確認
  ├─ 最小実装
  ├─ GREEN確認
  └─ REFACTOR
  ↓
Implementation Evaluator
  ├─ 要件・受入条件の充足
  ├─ UTの妥当性と弱体化の有無
  ├─ 過剰実装・回帰リスク
  └─ PASS / 差し戻し
```

高リスクなドメインロジックでは、UT設計担当と実装担当をさらに分離してよい。ただし、その場合もRED結果とテスト意図を構造化成果物として引き渡す。

# 9. ハンドオフ設計

工程間は会話の要約だけでつながず、標準化されたハンドオフ文書を作成する。次工程のエージェントは、ハンドオフに列挙された権威ある入力だけを起点に作業する。

```markdown
# Handoff: Design to Implementation
## Completed
- REQ-F-001〜REQ-F-012の設計完了
## Authoritative inputs
- docs/requirements/requirements.md
- docs/design/architecture.md
- docs/design/detailed-design.md
## Decisions
- ADR-001
- ADR-002
## Constraints
- Java 21 / Spring Boot 3.x
- 公開API互換性を維持
## Unresolved items
- QUESTION-004（blocking）
## Ready tasks
- TASK-001
- TASK-002
## Do not do
- QUESTION-004を推測で実装しない
```

## 9.1 ハンドオフの必須項目

- 完了した作業と未完了の作業

- 次工程が参照すべき権威ある成果物

- 確定した判断とADR

- 制約、禁止事項、スコープ外

- 未解決事項とblocking判定

- 次に実行可能なタスク

# 10. 状態管理

`docs/status/progress.yaml`をハーネスの集約状態とする。ただし、複数Agentが直接更新する共有メモリにはしない。**Development Orchestratorだけをsingle writer**とし、Generator、Evaluator、Auditorは実行結果を`docs/status/agent-runs/`へ追記する。Orchestratorはagent-run成果物を検証した後、楽観ロック付きで`progress.yaml`を更新する。

```text
Generator / Evaluator / Auditor
  └─ docs/status/agent-runs/<task>/<run-id>.yaml へ結果を追記
                         ↓
Development Orchestrator
  ├─ schema、commit SHA、テスト証跡、ゲート結果を検証
  ├─ expected_previous_revisionを確認
  └─ progress.yamlを原子的に更新
```

```yaml
schema_version: 1
revision: 42
expected_previous_revision: 41
updated_at: 2026-07-14T22:00:00+09:00
updated_by: development-orchestrator
project: order-service
session_mode: continuation
current_phase: tdd_implementation
current_phase_run_ref: docs/status/phase-runs/phase-run-TASK-004-007.yaml
current_task: TASK-004
context_manifest: docs/context/manifests/TASK-004.context.yaml
worktree: .worktrees/TASK-004
current_commit: abc123def456
baseline_verified_at: 2026-07-14T22:00:00+09:00

gates:
  requirements: passed
  requirements_review: passed
  basic_design: passed
  detailed_design: passed
  implementation_plan: passed
  test_design: passed
  unit_test_red: passed
  unit_test_green: in_progress
  review_target_fixed: pending
  integration_test: pending
  implementation_evaluation: pending
  code_review: pending
  harness_eval: pending
  completion: pending

blocking_issues: []

latest_agent_runs:
  tdd_generator: docs/status/agent-runs/TASK-004/run-20260714T215500.yaml

next_action:
  agent: tdd-generator
  task: TASK-004
  instruction: RED-GREEN-REFACTORを実行し、チェックポイントcommitとagent-run結果を作成する
```

## 10.1 Agent-run成果物

`PhaseRun`は`docs/status/phase-runs/<phase-run-id>.yaml`、`GateRun`は`docs/status/gate-runs/<gate-run-id>.yaml`へ保存し、`progress.yaml.current_phase_run_ref`から現在のPhaseRunを参照する。PhaseRunの`gate_run_refs`にはGateRun IDではなく保存パスを列挙し、その参照だけで全GateRunを一意に復元できなければ更新を拒否する。次の最小schemaで永続化する。

```yaml
phase_run:
  phase_run_id: phase-run-TASK-004-007
  parent_run_id: null
  phase_definition: PHASE-7
  task: TASK-004
  status: passed
  started_at: 2026-07-14T21:50:00+09:00
  finished_at: 2026-07-14T22:00:00+09:00
  agent_run_refs:
    - docs/status/agent-runs/TASK-004/run-20260714T215500.yaml
  gate_run_refs:
    - docs/status/gate-runs/gate-run-TASK-004-unit-test-green-007.yaml

gate_runs:
  - gate_run_id: gate-run-TASK-004-unit-test-green-007
    parent_run_id: null
    gate_definition: UNIT_TEST_GREEN
    phase_run_id: phase-run-TASK-004-007
    status: passed
    started_at: 2026-07-14T21:59:31+09:00
    finished_at: 2026-07-14T22:00:00+09:00
    artifact_refs:
      - docs/status/changes/TASK-004.yaml
    test_evidence_refs:
      - docs/status/agent-runs/TASK-004/run-20260714T215500.stdout.redacted.log
```

```yaml
schema_version: 1
run_id: run-20260714T215500
parent_run_id: null
phase_run_id: phase-run-TASK-004-007
agent: tdd-generator
task: TASK-004
status: passed
started_at: 2026-07-14T21:55:00+09:00
finished_at: 2026-07-14T22:00:00+09:00
input_revision: 41
context_manifest: docs/context/manifests/TASK-004.context.yaml
source_commit: 789xyz000111
result_commit: abc123def456
changed_files_manifest: docs/status/changes/TASK-004.yaml
skill_uses:
  - skill_use_id: skill-use-TASK-004-007-01
    parent_run_id: null
    skill: tdd-development@1
    status: completed
    started_at: 2026-07-14T21:55:00+09:00
    finished_at: 2026-07-14T21:59:30+09:00
commands:
  - command: ./gradlew test --tests OrderServiceTest
    exit_code: 0
    stdout: docs/status/agent-runs/TASK-004/run-20260714T215500.stdout.redacted.log
    stderr: docs/status/agent-runs/TASK-004/run-20260714T215500.stderr.redacted.log
evidence_redacted: true
secret_detected: false
result: PASS
requested_gate_transition:
  gate: unit_test_green
  from: in_progress
  to: passed
```

## 10.2 競合・破損時の扱い

- `expected_previous_revision`が現在値と一致しない場合は更新を拒否し、最新状態から再評価する。
- `progress.yaml`は一時ファイルへ書き、schema検証後にatomic renameする。
- worktree内のAgentは中央の`progress.yaml`を直接編集しない。
- agent-run成果物は追記専用とし、既存runを書き換えない。
- 状態ファイルとGitの`current_commit`が一致しない場合は、次工程をブロックする。

# 11. 品質ゲート

| **ゲート**          | **主な条件**                                 | **ブロック時の戻り先** |
|---------------------|----------------------------------------------|------------------------|
| REQUIREMENTS_PLAN | Plannerが範囲、論点、成果物、終了条件を定義 | 要件Planner |
| REQUIREMENTS | 要件ID、受入条件、未解決事項、スコープが明確 | 要件定義 |
| REQUIREMENTS_REVIEW | blocking指摘ゼロ                             | 要件定義               |
| ARCHITECTURE_PLAN | 設計論点、代替案、非機能観点、ADR候補が定義 | Architecture Planner |
| DESIGN | 非機能・例外・Tx・責務・ADRが定義 | 基本/詳細設計 |
| IMPLEMENTATION_PLAN | タスク粒度、依存、UT/IT、DoDがレビュー済み | 実装計画 |
| TEST_DESIGN | UT/IT観点、正常・異常・境界、データが定義 | テスト設計 |
| UT_RED              | UTが意図した理由で失敗                       | UT作成                 |
| UT_GREEN            | 対象・関連・全UT成功、テスト弱体化なし       | 実装                   |
| REVIEW_TARGET | commit SHA、diff base、変更一覧・成果物ハッシュが固定済み | Generator / Orchestrator |
| ACCESS_POLICY | manifestのaccess policyが、許可されたenforcement profileで機械的に強制されている | Context Builder / Orchestrator |
| STATE_REVISION | progress revisionとGit SHAが一致し、single writer更新に成功 | Orchestrator |
| INTEGRATION         | 必要ITが成功、DB/Tx/設定を検証               | 実装またはIT           |
| IMPLEMENTATION_EVALUATION | 固定されたreview targetを独立Evaluatorが評価し、テスト弱体化なし、最小実装、受入条件充足 | TDD実装 |
| CODE_REVIEW | blocking指摘ゼロ、回帰リスク評価済み | 実装 |
| COMPLETION          | 全要件・受入条件・テスト・文書が完了         | 該当工程               |

## 11.1 機械判定とLLM判定の分離

| **機械判定にするもの**                                       | **LLMレビューにするもの**                              |
|--------------------------------------------------------------|--------------------------------------------------------|
| コンパイル、UT、IT、静的解析、フォーマット、依存関係スキャン | 要件の曖昧性、設計妥当性、責務分離、保守性、回帰リスク |
| ファイル存在、ID重複、テンプレート必須欄、終了コード         | 要件と実装の意味的な対応、例外・境界ケースの漏れ       |

# 12. トレーサビリティ

```
REQ-F-003
├─ AC-003-01
├─ AC-003-02
├─ TASK-004
├─ UT-ORDER-001
├─ UT-ORDER-002
├─ IT-ORDER-001
└─ IT-ORDER-002
```

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

# 13. CLAUDE.mdの責務

CLAUDE.mdは詳細な設計書の置き場ではなく、常に守る短い指示と参照先を定義する。長大化を避け、工程固有の手順はworkflowsやskillsへ分離する。 ファイル種別やパス別の規則は `.claude/rules/*.md` に分割し、手順型の知識は `.claude/skills/<skill-name>/SKILL.md` に配置する。

```markdown
# Project Instructions
## Development process
- Follow `.claude/workflows/development.md`.
- Do not implement before design and test-design gates pass.
- Use Unit Test driven RED-GREEN-REFACTOR.
- Run required Integration Tests before completion.
- Record important decisions in `docs/decisions/`.
- Agents write run results under `docs/status/agent-runs/`; only the Development Orchestrator updates `docs/status/progress.yaml`.
## Engineering rules
- Never delete or weaken tests merely to make them pass.
- Do not invent business rules.
- Do not change public APIs without explicit approval.
- Treat documents listed in the current handoff as authoritative.
```

# 14. ガードレール実装：Hooks・External Runner・スクリプト

| **タイミング** | **実行内容**                                       | **目的**           |
|----------------|----------------------------------------------------|--------------------|
| セッション開始 | progress.yaml、current handoff、対象taskの存在確認 | 現在地の復元       |
| 実装前         | 設計・Test Design・UT REDゲート確認                | 早すぎる実装を防止 |
| ツール実行前   | write scope、保護パス、危険Bash、リダイレクト先検査 | 禁止操作を予防 |
| ファイル編集後 | format、lint、secret scan、変更一覧記録             | 検知と復旧判断 |
| タスク終了前   | 対象UT、関連UT、静的解析、agent-run出力             | GREEN維持と証跡化 |
| 機能完了前     | 全UT、Integration Test                             | 回帰と結合保証     |
| レビュー開始前 | commit SHA、diff base、変更一覧、成果物ハッシュ確認 | 誤った対象のレビュー防止 |
| 完了監査前     | トレーサビリティ、未解決事項、文書更新、state revision | 未完了と競合の見逃し防止 |


## 14.1 Fullモード：権限とHooksの適用順序

```text
Agent起動
  ↓ SubagentStart: role/task/context/permissionを注入
Tool実行要求
  ↓ Permission Boundary
  ↓ PreToolUse Hook
Tool実行
  ↓ PostToolUse Hook
Agent終了要求
  ↓ SubagentStop Hook
工程終了要求
  ↓ Stop Gate
```

権限設定で広いカテゴリを拒否し、Hooksでプロジェクト固有の条件を追加する。Hooksだけでサンドボックスの代替をしない。Hooksを利用できない場合は14.2のCompatibleモードへ切り替える。

## 14.2 Compatibleモード：External Runnerの適用順序

```text
Runner起動
  ↓ Capability Profile検証
  ↓ permissions / sandbox / worktree準備
Agent起動
  ↓ Agentがagent-run.yamlを出力
Agent終了
  ↓ quality-gate.sh
  ↓ verify-access-policy.sh
  ↓ verify-review-target.sh
  ↓ verify-agent-result.sh
Evaluator起動・終了
  ↓ Orchestratorがsingle writerでprogress.yamlを更新
  ↓ CIまたは完了ゲート
```

RunnerはAgentの自然言語による完了宣言を信用せず、終了コード、成果物、Git diff、レビュー対象SHA、agent-run、未解決blocking findingを検査する。禁止パスへの変更があればタスクをFAILとし、自動コミットと次工程への遷移を拒否する。

## 14.3 Context manifest検証

各Generator開始時に、対象タスク、権威ある入力、探索範囲、論理的な読書き範囲、禁止事項がcontext manifestに含まれていることを検証する。さらに、`access_policy`が選択されたenforcement profileへ反映されていることを機械確認する。Fullモードではpermissions、agent tools、PreToolUse Hookを検証し、Compatibleモードではpermissions、sandbox、worktree、専用コマンド、Runnerの変更範囲検査を検証する。manifestがない場合、または宣言と実効制御が一致しない場合は実装へ進まない。

# 15. Definition of Done

- 対象要件と受入条件が確定し、blockingの未解決事項がない。

- 詳細設計とADRが更新されている。

- UTのRED-GREEN-REFACTORを完了している。

- 必要なIntegration Testが作成され、成功している。

- 全UT、全対象IT、静的解析、フォーマットが成功している。

- テストの削除・無効化・弱体化がない。

- コードレビューのblocking指摘がゼロである。

- 要件IDからタスク、UT、IT、実装への追跡が成立している。

- statusとhandoffが最新である。

- レビュー対象のcommit SHA、diff base、変更ファイル一覧が固定され、Evaluatorが同一対象を検証している。

- context manifestのアクセス方針が、FullまたはCompatibleのenforcement profileにより機械的に強制されている。

- `progress.yaml`がOrchestratorのsingle writer方式で更新され、revisionとGit SHAが一致している。

# 16. 導入ステップ

1. `project-initializer`を作成し、リポジトリ構造、ビルド、UT、IT、静的解析のベースラインを記録する。
2. `CLAUDE.md`、`docs/project`、権限境界、禁止操作を定義する。
3. `progress.yaml`、`baseline.yaml`、ハンドオフ、context manifestのテンプレートを作成する。
4. 要件定義、設計、実装、レビューの最小ワークフローを作成する。
5. Development Orchestrator、Continuation Agent、Context Builderを作成する。
6. 主要Planner、TDD Generator、Integration Test Engineer、各Evaluatorを作成する。
7. UT・IT・静的解析を実行するスクリプトを統一する。
8. Capability Profileを作成し、Hooks利用可能時は`PreToolUse`、`SubagentStop`、`Stop`を実装し、Hooks非対応時はExternal Runnerと検証スクリプトを実装する。
9. 小さな機能一つで試行し、成果物量、コンテキスト量、タスク粒度、テスト速度を調整する。
10. 代表的な失敗事例からHarness Evalsを作成し、回帰検知を開始する。
11. 並列化が必要になった時点でworktree隔離を導入する。
12. 外部システム連携が必要になった時点でTool Gateway／MCPを導入する。

# 17. 最小導入構成

> **最初に必要なもの**
>
> `CLAUDE.md`、Project Initializer、Continuation Agent、Context Builder、Development Orchestrator、Implementation Planner、TDD Generator、Implementation Evaluator、Integration Test Engineer、Completion Auditor、`progress.yaml`、`baseline.yaml`、context manifest、Capability Profile、task・handoffテンプレート、UT/IT実行スクリプト、およびFullモードのHooks群またはCompatibleモードのExternal Runner。

Worktree、MCP Tool Gateway、広範なHarness Evalsは段階導入できる。ただし、セッション再開性、コンテキスト選定、権限制御、終了ゲートは最小構成から外さない。Hooksは必須ではないが、Hooksを使わない場合はpermissions、sandbox、External Runner、CIによるCompatibleモードを必須とする。

# 18. 設計上の決定事項

| **ID**  | **決定**                                 | **理由**                                               |
|---------|------------------------------------------|--------------------------------------------------------|
| DEC-001 | 実装はUT駆動TDDとする                    | 高速なフィードバックで細粒度の設計・実装を制御するため |
| DEC-002 | Integration Testを必須とする             | UTでは保証できない実構成、DB、Tx、設定を確認するため   |
| DEC-003 | Contract Testは一旦除外する              | 現在の導入範囲を抑え、UT・ITの基盤確立を優先するため   |
| DEC-004 | 成果物によるハンドオフを採用する         | セッションやエージェントが変わっても判断を失わないため |
| DEC-005 | TDD Generatorと独立Evaluatorを分離する | RED-GREEN-REFACTORの速度を維持しつつ自己評価の甘さを抑えるため |
| DEC-006 | 大規模判断工程のみ独立Plannerを必須化する | 全工程一律3層による過剰なコストと調整負荷を避けるため |
| DEC-007 | InitializerとContinuationを分離する | 初回準備と継続作業の責務を分け、セッション間の再開性を高めるため |
| DEC-008 | タスク別context manifestを必須化する | 不要な情報を抑え、権威ある入力と禁止範囲を明確にするため |
| DEC-009 | Evaluatorと決定論的ゲートを分離する | 判断が必要な評価と、必ず守る機械判定を混同しないため |
| DEC-010 | エージェント別権限境界を設ける | 自律性を維持しつつ誤操作・越権・情報漏えいを抑えるため |
| DEC-011 | Hooksを単一必須依存にせずCapability Profileで実行方式を選択する | Hooks非対応環境でも決定論的ゲートを維持するため |
| DEC-012 | Hooks非対応時はExternal Runnerを終了ゲートとする | Agentの自己申告ではなく成果物と終了コードで遷移を判定するため |
| DEC-011 | ハーネス変更をEvalsで回帰検証する | プロンプトや構成変更による品質劣化を定量的に検出するため |

# 19. 段階導入方針

| 機能 | 導入タイミング | 必須度 |
|---|---|---|
| Initializer / Continuation | 最初から | 必須 |
| Context Builder / manifest | 最初から | 必須 |
| Deterministic Guardrail | 最初から | 必須 |
| Permission Boundary | 最初から | 必須 |
| Progressive Disclosure Skills | Skill作成時 | 推奨 |
| Harness Evals | 試行導入開始時 | 本格運用前に必須 |
| Worktree Isolation | 並列実行開始時 | 条件付き必須 |
| Tool Gateway / MCP | 外部システム連携時 | 条件付き必須 |
| Contract Test | API・イベント互換性保証が必要になった時点 | 将来拡張 |
| デプロイ・運用ハーネス | 実装完了後の対象範囲拡張時 | 将来拡張 |

最初から全機能を最大構成で実装する必要はない。ただし、Initializer／Continuation、Context Builder、決定論的ゲート、権限制御は後付けすると成果物形式と運用手順の変更が大きいため、初期設計に含める。

# 付録A. タスク状態テンプレート

```markdown
# TASK-XXX
## 対象要件
- REQ-F-XXX
## 受入条件
- AC-XXX-01
## Unit Tests
- UT-XXX-001
## Integration Tests
- IT-XXX-001
## TDD Status
- Test Design: PASS
- UT RED: PASS
- UT GREEN: PENDING
- Refactor: PENDING
- Integration Test: PENDING
- Review: PENDING
## Completion Criteria
- 対象UT、関連UT、全UTが成功
- 必要なIntegration Testが成功
- テスト弱体化なし
- blockingレビュー指摘ゼロ
```

# 付録B. 完了判定テンプレート

```yaml
gate: COMPLETION
conditions:
  all_requirements_implemented: true
  all_acceptance_criteria_covered: true
  unit_tests_passed: true
  integration_tests_passed: true
  static_analysis_passed: true
  tests_not_weakened: true
  blocking_review_findings: 0
  traceability_complete: true
  documentation_updated: true
  handoff_updated: true
  review_target_fixed: true
  review_target_verified: true
  access_policy_enforced: true
  state_revision_consistent: true
  progress_single_writer_verified: true
result: PASS
```

# 付録C. 公式情報に基づくレビュー結果

> 本付録の情報源は、Claude Code公式ドキュメントおよびAnthropic Engineeringの一次情報です。参照先は運用時に最新版を再確認してください。

本付録は、2026年7月14日時点のClaude Code公式ドキュメントおよびAnthropic Engineeringの記事と本設計書を照合し、独立したレビュアー観点で評価した結果である。

| 評価項目              | 判定   | レビュー結果                                                                                                                                            | 反映内容                                                   |
|-----------------------|--------|---------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| 工程分解と状態永続化  | PASS   | 小さな作業単位、構造化成果物、進捗ファイルによるセッション間ハンドオフは公式の長時間エージェント設計と整合する。                                        | 現行方針を維持。progress.yamlとhandoffを必須成果物とする。 |
| サブエージェント分離 | PASS | 専用コンテキスト、専用プロンプト、ツール権限を持つ専門サブエージェントの利用は公式仕様と整合する。 | Planner / Generator / Evaluatorの責務と独立性を明確化。 |
| 3層エージェント適用 | PASS | Anthropicの長時間開発ハーネスで示されたplanner/generator/evaluatorを、大規模判断工程では3層、短いTDD反復ではGenerator+Evaluatorとして適用する。 | 3.2、工程表、エージェント設計、ゲートへ反映。 |
| Skills配置            | 要修正 | Skillはディレクトリだけでは成立せず、各SkillにSKILL.mdが必要。本文の旧ディレクトリ例は不十分だった。                                                    | `.claude/skills/<name>/SKILL.md`へ修正。               |
| workflowsディレクトリ | 注意   | `.claude/workflows`は公式の自動読込プリミティブではない。本設計独自の文書置き場としては有効だが、CLAUDE.mdまたはSkillから明示的に参照する必要がある。 | ディレクトリ例と運用ルールへ注記。                         |
| Hooks設計             | 要補強 | Hooksはイベント名とブロック可否を踏まえて設計する必要がある。SubagentStart/Stop、PreToolUse、PostToolUse、Stop、SessionEnd等を使い分ける。              | 付録Dに推奨イベント割当を追加。                            |
| 設定・権限管理        | 要補強 | 共有設定、個人設定、管理設定には優先順位があり、機密ファイルはpermissions.denyで保護できる。                                                            | settings.local.jsonと機密ファイル拒否ルールを追加。        |
| 並列作業              | 要補強 | 並列セッションや複数エージェントの編集衝突を防ぐため、worktree等による作業領域分離が有効。                                                              | 並列レビュー・実装時の作業ツリー分離を推奨事項に追加。     |
| TDD/IT品質ゲート      | PASS   | UTで高速なRED-GREEN-REFACTORを回し、実構成をIntegration Testで保証する役割分担は実務上妥当。                                                            | 現行方針を維持。テスト弱体化検査をレビュー必須項目にする。 |

## C.1 Version 1.3で追加した主要アーキテクチャ

- Initializer AgentとContinuation Agentを分離し、長時間・複数セッションの再開性を強化した。
- Context Builderとタスク別context manifestを追加した。
- Hooks、CI、権限設定を決定論的ガードレールとして統合した。
- エージェント別の書込み・シェル・ネットワーク境界を定義した。
- Progressive Disclosure形式のSkills構成を追加した。
- 並列実行時のGit worktree隔離を追加した。
- MCP接続前のTool Gatewayを追加した。
- Code-based、Model-based、Human graderを組み合わせたHarness Evalsを追加した。

## C.2 既存設計からの主要な修正点

- `.claude/workflows`を公式機能として扱わず、SkillまたはCLAUDE.mdから参照される本設計独自の工程文書として位置付けた。

- 各Skillの配置を `.claude/skills/<skill-name>/SKILL.md` として明示した。

- Planner / Generator / Evaluatorの適用ルールを追加し、工程ごとの2層・3層の使い分けを明示した。

- 成果物完成後に独立評価を行うHarness Reviewerを追加した。

- サブエージェントレビューをSubagentStart/Stop等のHooksで観測・強制できる構成を追加した。

- 共有設定 `.claude/settings.json`、個人設定 `.claude/settings.local.json`、機密ファイル拒否設定の役割を補足した。

- 並列作業時はGit worktree等で編集領域を分離する方針を追加した。


## C.3 Version 1.4で解消したBlocking findings

- Reviewer用worktreeの暗黙的な状態継承を禁止し、commit SHA、diff base、変更ファイル一覧、成果物ハッシュによるレビュー対象固定を必須化した。
- Context manifestを「権威ある入力・探索範囲」と「access policy」に分離し、manifest自体はアクセス制御ではないことを明記した。
- エージェント別Write範囲を、tools／permissions／agent-scoped PreToolUse Hookで強制する実装方式へ修正した。
- ガードレールをPreventive／Detective／Recoveryに分離し、PostToolUseのsecret scanを予防制御として扱わないよう修正した。
- `progress.yaml`をDevelopment Orchestratorのみが更新するsingle writer方式へ変更し、agent-run追記、revision、atomic updateを導入した。
- 完了判定テンプレートのYAMLインデントを修正し、新しいゲート条件を追加した。

# 付録D. 作成後サブエージェントレビュー手順

要件書、設計書、実装計画、テスト、コードなどの主要成果物を作成した直後は、作成エージェントとは別のサブエージェントによるレビューを必須とする。レビューがPASSになるまで、次工程の品質ゲートを通過させない。

## D.1 標準フロー

```
成果物作成
↓
作成者による機械チェック
↓
Harness Reviewer / 専門Reviewerを起動
↓
公式資料・プロジェクト規約・上流成果物と照合
↓
blocking / non-blocking指摘を記録
↓
作成者または修正担当が対応
↓
別コンテキストで再レビュー
↓
PASS後にhandoffとagent-runを出力し、Orchestratorがprogress.yamlを更新
```

## D.2 レビュアーの入力

- レビュー対象となる成果物のパス

- 上流工程の権威ある成果物と現在のhandoff

- 適用するプロジェクト規約、CLAUDE.md、rules、Skills

- 品質ゲートとDefinition of Done

- 必要に応じてClaude Code公式ドキュメントおよびAnthropic Engineeringの一次情報

## D.3 レビュアーへの標準指示

```
あなたは作成者から独立したHarness Reviewerです。
レビュー対象を直接読み、作成者の説明を根拠にせず評価してください。
確認項目:
1. 上流要件・受入条件との整合性
2. 工程の開始条件・終了条件・戻り先の完全性
3. Claude Code公式仕様との適合性
4. 実際に実行可能なファイル配置・コマンド・Hook構成か
5. TDD順序、UT/ITの役割、テスト弱体化防止が明確か
6. ハンドオフ、状態管理、トレーサビリティに欠落がないか
7. セキュリティ、権限、機密ファイル、並列編集のリスク
出力:
- gate: PASS または FAIL
- blocking_findings
- non_blocking_findings
- evidence
- required_changes
- residual_risks
```

## D.4 推奨Hooks割当

| イベント                          | 用途                                             | ブロック方針                       | 例                                   |
|-----------------------------------|--------------------------------------------------|------------------------------------|--------------------------------------|
| SessionStart / InstructionsLoaded | progress、handoff、規約の読込確認                | 不足時はコンテキスト追加または警告 | 現在工程・対象Taskを注入             |
| PreToolUse                        | 実装前ゲート、危険なBash、保護ファイル編集の検査 | 条件不成立ならブロック             | UT RED未通過時のmainコード編集を拒否 |
| PostToolUse                       | 編集後のformat/lint/secret scan                  | 失敗内容を即時フィードバック       | 変更ファイルに限定して高速検査       |
| SubagentStart                     | レビュアーへ規約と評価基準を注入                 | 生成自体は原則許可                 | Harness ReviewerにDoDを追加          |
| SubagentStop                      | レビュー出力形式とblocking指摘解消を検査         | 不十分なら継続させる               | gate未記載なら再評価を要求           |
| Stop                              | タスク終了前のUT、agent-run、handoff確認          | 不備なら終了をブロック             | agent-run未出力またはOrchestrator更新失敗を拒否 |
| SessionEnd                        | ログ・メトリクス・一時資源の整理                 | 原則ブロックしない                 | レビュー回数とゲート滞留を記録       |

## D.5 レビュー成果物

```yaml
review_id: REVIEW-HARNESS-001
reviewer: harness-reviewer
reviewed_artifacts:
- docs/design/harness-design.md
sources_checked:
- official_claude_code_docs
- anthropic_engineering
result: FAIL
blocking_findings:
- id: HR-001
issue: SkillディレクトリにSKILL.mdが定義されていない
required_change: 各Skillのエントリポイントを追加する
non_blocking_findings: []
residual_risks: []
reviewed_at: 2026-07-14
```

## D.6 並列レビュー時の安全策

- 実装者とレビュアーが同時にファイルを変更する場合は、別Git worktreeまたは別ブランチを使用する。

- レビュアーは原則read-onlyとし、修正案はレビュー成果物へ記録する。自動修正を許す場合も対象範囲を限定する。

- 複数レビュー結果を統合する担当を一つに定め、同じ指摘の重複、矛盾、優先度を整理する。

- レビュー完了時点のcommit SHAまたは成果物ハッシュを記録し、レビュー後の変更による陳腐化を検知する。

# 付録E. 公式参照情報

本設計で特に参照したAnthropic公式資料:

- Claude Code documentation overview: https://code.claude.com/docs/ja/overview
- Effective harnesses for long-running agents: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Harness design for long-running application development: https://www.anthropic.com/engineering/harness-design-long-running-apps
- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Building effective agents: https://www.anthropic.com/engineering/building-effective-agents
- Demystifying evals for AI agents: https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
- Writing effective tools for AI agents: https://www.anthropic.com/engineering/writing-tools-for-agents
- Code execution with MCP: https://www.anthropic.com/engineering/code-execution-with-mcp
- Equipping agents for the real world with Agent Skills: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- How we built our multi-agent research system: https://www.anthropic.com/engineering/multi-agent-research-system

> 公式資料のアーキテクチャをそのまま複製するのではなく、要件定義から実装完了までの工程、UT駆動TDD、Integration Test、Java/Spring系プロジェクトを想定して適用範囲を調整している。

# 付録F. 今回のレビュー判定

判定: PASS（修正反映後）

- 全体の工程分解、成果物主義、状態永続化、UT駆動TDD、Integration Test、Planner/Generator/Evaluatorによる独立レビューという中核設計は妥当。

- 公式仕様との不整合になり得たSkills配置とworkflowsの位置付けを修正済み。

- 要件定義・基本設計・実装計画は3層、詳細設計・TDD・Integration Testは原則2層、完了監査はEvaluator専用として明確化済み。

- Hooks、設定スコープ、機密ファイル保護、並列作業の安全策を補強済み。

- 残余リスクは、実プロジェクトのビルドツール・CI・テスト速度に応じたコマンドと閾値の具体化である。


# 付録G. Version 1.3独立レビュー観点

## G.1 アーキテクチャ整合性

- Planner／Generator／Evaluatorは維持し、Session、Context、Guardrail、Permission、Evalを直交する制御層として追加した。
- 工程ごとにエージェントを過剰分割せず、TDDの短い反復は一つのGenerator内で維持した。
- Evaluatorによる判断と、Hooks／CIによる決定論的判定を重複させず役割分担した。

## G.2 運用上の注意

- Context Builderが作るmanifestを過度に静的化すると必要情報を欠くため、Generatorは不足コンテキストを申告できること。
- Hooksを増やしすぎると開発速度が落ちるため、停止させるルールと警告に留めるルールを区別すること。
- Harness Evalsはテスト件数ではなく、実際に発生した失敗と高リスク経路を優先して増やすこと。
- Worktree並列化は、依存関係解析と統合責任者が存在する場合だけ有効化すること。

## G.3 判定

**PASS（導入可能）**。ただし、初期導入ではInitializer、Context manifest、権限境界、機械的な終了ゲートを優先する。終了ゲートはFullモードではHooks、CompatibleモードではExternal Runnerで実装し、WorktreeとMCPは必要になった時点で有効化する。

# 付録H. Version 1.4独立レビュー判定

```yaml
review:
  target_version: 1.4
  previous_blocking_findings:
    worktree_review_target: resolved
    context_manifest_access_boundary: resolved
    agent_write_scope_enforcement: resolved
    preventive_detective_guardrails: resolved
    progress_state_concurrency: resolved
    yaml_template_syntax: resolved
  result: PASS_FOR_POC
  production_condition:
    - Hookとpermission設定を実プロジェクトでE2E検証する
    - state revision競合テストをHarness Evalsへ追加する
    - Reviewerが指定commit以外を評価した場合にFAILとなるevalを追加する
```


# 付録I. Version 1.5変更点と判定

## I.1 変更点

- Hooksの有無を起動時に判定するCapability Profileを追加した。
- Full／Compatible／Manualの3モードを定義した。
- Hooks非対応環境ではExternal Harness RunnerがAgent終了後の品質ゲートを担当する。
- `ACCESS_POLICY`とDefinition of DoneをHooks名ではなく、機械的に強制された効果で判定するよう変更した。
- Hooks非対応時のPreToolUse、PostToolUse、SubagentStop、Stop相当の代替手段を定義した。
- ManualモードはPoC限定とし、本格運用を禁止した。

## I.2 独立レビュー判定

```yaml
review:
  target_version: 1.5
  hooks_required: false
  supported_modes:
    full: production_ready
    compatible_no_hooks: production_ready
    manual: poc_only
  mandatory_effects:
    prohibited_operations_machine_enforced: true
    completion_gate_machine_enforced: true
    state_single_writer: true
    review_target_immutable: true
    ci_gate_available: true
  result: PASS_FOR_POC
  production_condition:
    - 選択したCapability ProfileのE2Eテストを行う
    - Hooksなし環境で禁止パス変更がRunnerによりFAILになることを確認する
    - agent-run欠落時にprogress.yamlが更新されないことを確認する
    - Runner失敗時に次工程へ遷移しないことを確認する
```
