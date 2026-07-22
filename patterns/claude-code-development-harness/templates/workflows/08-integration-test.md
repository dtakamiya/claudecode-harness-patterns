# PHASE-8: Integration Test・UI検証・最終対象固定

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §7):
  id: PHASE-8
  inputs: production-code, integration-test-plan
  outputs: integration-tests, test-evidence, ui-evidence-or-na, code-review-target
  entry_gate: IMPLEMENTATION_EVALUATION
  exit_gate: CODE_REVIEW_TARGET
  allowed_agents: integration-test-engineer, integration-test-reviewer, ui-verifier,
                  context-builder
-->

## 目的

実連携をIntegration Testで保証し、UI変更を実ブラウザで検証し、コードレビュー用の最終対象を固定する（設計書 §7、§7.2）。

## 開始条件

`IMPLEMENTATION_EVALUATION`がPASSしていることをOrchestratorが検証する。

## 入力

- プロダクションコード（PHASE-7で評価済み）
- Integration Test計画

## 担当Agent

| 役割 | Agent | profile | Skill |
|---|---|---|---|
| Generator | `integration-test-engineer` | generator / `integration_test_engineer_write_allowlist`のみwrite | `tdd-development@1` |
| Evaluator | `integration-test-reviewer` | evaluator | — |
| UI検証 | `ui-verifier` | ui_verifier | — |
| コンテキスト編成 | `context-builder` | context_builder | — |

## 完了順序（設計書 §7.2）

```text
INTEGRATION_TEST
  ↓
UI_VERIFICATION（PASSまたは検証済みnot applicable）
  ↓
CODE_REVIEW_TARGET
  ↓
PHASE-9 ready
```

Integration TestまたはUI検証後にコード・テスト・証跡が変わった場合は、それ以前の結果を必要な範囲で再実行してから最終対象を固定する。

## 手順 1: Integration Test

Integration Testの方針（設計書 §7）。技術スタックに依存しない規範とし、具体的なフレームワークはプロジェクトprofileで定義する。

| 項目 | 方針 |
|---|---|
| Runtime Context | 実際の構成を使用 |
| Datastore | 本番と互換性のある隔離環境を使用 |
| Persistence Adapter | 実実装を使用 |
| Transaction | 実際のコミット、ロールバック境界を検証 |
| Serialization | 実際のデータ・メッセージ変換を使用 |
| 内部Service | 原則としてモックしない |
| 外部システム | Stubまたは隔離コンテナ等で制御 |

確認する代表項目（設計書 §7.1）:

- 入力境界 → Application Service → Persistence Adapter → Datastoreの連携
- データマッピング、クエリ、制約、ロック、トランザクション
- 認証・認可、バリデーション、例外ハンドリング
- メッセージ送受信、シリアライズ、イベント発行条件
- 外部APIアダプターの要求・応答変換と障害時挙動

### write範囲（設計書 §3.6.6）

`integration_test_engineer_write_allowlist`をIntegration Test Engineerの唯一のwrite profileとする。許可するのは、context manifestが**個別のcanonical pathで列挙した**Integration Testコード、テストfixture、ローカルstub定義、隔離container定義、テスト専用profile、および`docs/status/agent-runs/<current-task>/<new-run-id>.yaml`の新規作成だけである。

**含めないもの**: production code、PHASE-7のUnit Test、本番接続設定、ビルド設定、CI設定、依存定義、他taskまたは既存のagent-run。

- ディレクトリprefixで広く許可しない。
- stdout / stderrのraw logはIntegration Test Engineerへ書かせず、信頼済みRunnerがcapture・redactionしてimmutableな参照を返す。**ログ用prefixをallowlistへ追加してはならない。**

### テスト支援設定を変更した場合（設計書 §3.6.6、§3.6.4）

同一runで自らが書いた設定を自らの権限で実行するため、次を必須とする。

- agent-runへ`test_support_configuration_changed`、`independent_reaudit_required`、`independent_reaudit_status`、`independent_reaudit_evidence_ref`を記録する。
- 設定変更時は独立再監査のstatusが`passed`で証跡参照が検証できるまでITを実行せず、`INTEGRATION_TEST`をrequestしない。
- **未監査の設定変更を含むrunの証跡を`INTEGRATION_TEST`ゲートの根拠にしない。**

## 手順 2: UI検証（設計書 §7.2）

`ui_change`はPlannerがタスクへ記録し、Context Builderがcontext manifestへ転記した値を使う。**Generatorの自己申告だけでnot applicableにしてはならない。** Orchestratorと独立Reviewerは、固定されたreview targetのchanged files manifest、route・component・style・template等のUI資産規約から値を再検証する。未指定、判定不一致、対象SHA不一致はfail-closedでゲート判定を拒否する。

実行者は専用`ui-verifier`とする。固定review targetをread-onlyで受け取り、ローカルpreviewへのBrowser / Preview操作とUI証跡の書込みだけを許可する。

`ui_change: true`の場合、通常のtest・typecheck・buildに加えて次を**同じcommit SHAへ結び付けた**証跡とする。

- 対象画面を実際に表示したスクリーンショット
- 受入条件に関係する操作結果
- 変更に関係するnarrow / wide等のviewport確認
- browser consoleの新規errorが0件であること

GateRunには`ui_change`、判定者、判定根拠、review targetのcommit SHAを必ず記録する。

### Browser / Previewの供給（設計書 §3.6.5）

**`Browser / Preview`は本書の論理モデルであり、実在のtool名ではない。** Agent定義へそう記述しても`ui-verifier`はブラウザを操作できない。導入時に次のいずれかで供給し、`ui-verifier`へscopeする。

- Browser操作を提供するMCP serverをTool Gateway経由で接続し、`ui-verifier`の`tools`へ当該tool名を明示的に追加する。
- または、信頼済みRunnerがブラウザ操作を実行し、証跡を`ui-verifier`へ渡す。この場合`ui-verifier`は証跡の記録と判定だけを行う。

- **`ui-verifier`にBashを与えてブラウザ操作を代替してはならない。** 与えると禁止事項（ソースコード修正、外部サイト・本番接続）が構造的に迂回可能になる。
- previewの起動は強制側の責務とし、`ui-verifier`は起動しない。**previewは固定されたreview targetのcommitからビルドする。**
- いずれの供給も無い環境では、`ui_change: true`のtaskを検証できない。**未検証として完了をブロックする。not applicableへ読み替えてはならない。**
- `ui_change: false`の場合だけ`UI_VERIFICATION`をnot applicableとして扱う。

### 外部更新の境界（設計書 §3.6.7）

- **隔離されたローカルpreview環境の内部で完結する操作**は、受入条件の証跡として実行する。
- **外部サイト、本番、ステージング、共有環境、第三者APIへ到達する更新**は禁止する。
- この切り分けをAgentの判断だけに依存させない。接続先allowlistでpreview origin以外を遮断する。
- UI証跡のスクリーンショットは**画像でありredactionが効かない**。preview環境へ本番データ・実PIIを載せない構成が一次的な対処である。画面へ秘密情報が表示された場合、当該証跡を保存せずrunを`failed`とする。

## 手順 3: 最終対象の固定

PHASE-8完了後に`kind: code_review`のreview targetを作成する（設計書 §3.8）。PHASE-8までのコード、テスト、UI証跡を含むcommit SHA、diff base、変更一覧・成果物ハッシュを固定する。

PHASE-8以後にファイルまたは証跡が変わった場合は`CODE_REVIEW_TARGET`とCode/Security Reviewをstale化し、新しいcommit SHA、diff base、変更一覧、成果物ハッシュで再固定する。変更がPHASE-7の実装前提、受入条件、production code、Unit Testを変える場合は`IMPLEMENTATION_REVIEW_TARGET`とImplementation Evaluationもstale化してPHASE-7から再評価する。

## PHASE-8途中のレビュー対象解決（設計書 §3.8）

`INTEGRATION_TEST`は不変なtargetの対象に**含まれない**。`kind: code_review`のtargetはPHASE-8完了後に固定されるため、Integration Test ReviewerとUI Verifierの実行時点では存在しない。両者は次の手順で対象を解決し、結果をレビュー成果物とagent-runへ記録する。**解決できない場合はゲートを開始せずfail-closedとする。**

- PHASE-7の`kind: implementation_review` targetを読み、`commit_sha`を**評価済みproduction codeの基準点**として得る。allowlist外の変更がないことの検証はこの基準点との差分で行う。
- 評価するITコードはIntegration Test Engineerのagent-runの`result_commit`から読み、それがPHASE-7の`commit_sha`の**子孫であること**を検証する。子孫でなければ拒否する。
- 現在のcheckout上でread-only実行する構成では、base commitと変更ファイル一覧をレビュー成果物へ明記し、working treeがdirtyであることを記録する。**何を読んだかを特定できない状態で評価を開始してはならない。**
- UI Verifierのpreviewは固定commitからビルドし、証跡を当該commit SHAへ束縛する。

## 成果物

- Integration Testコード
- `docs/status/test-evidence/<task>-*.yaml`
- `docs/features/<feature-id>/tests/ui-evidence/**` またはnot applicable判定
- `docs/features/<feature-id>/reviews/targets/TASK-XXX-code-review.yaml`
- `docs/features/<feature-id>/reviews/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `INTEGRATION_TEST` | intra-phase | 必要ITが成功、実ランタイム・永続化層・Tx・設定を検証（設計書 §11） |
| `UI_VERIFICATION` | intra-phase | UI変更時に表示・操作・viewport・console errorを実ブラウザで検証。非UI変更はnot applicable |
| `CODE_REVIEW_TARGET` | exit gate | PHASE-8までのコード、テスト、UI証跡を含むcommit SHA、diff base、変更一覧・成果物ハッシュが固定済み |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

`INTEGRATION_TEST`は実装またはIT、`UI_VERIFICATION`は実装またはUI検証、`CODE_REVIEW_TARGET`はOrchestrator（設計書 §11）。

## 注意事項

- Integration Test Engineerは内部を過剰にモックせず、本番環境へ接続しない（設計書 §8.3、§3.6）。
- Integration Test Reviewerは実装者の説明のみを根拠にしない（設計書 §8.4）。**設定による静かなフォールバック**（サービス未起動時にインメモリ等の代替へ切り替わる構成）は、ITが実構成を検証していないことを隠すためblockingとする（設計書 §3.6.6）。
- 評価対象コードを実行するAgentには実行時要件が適用される。allowlist登録済みコマンドに限り、Network遮断・secret非搭載の隔離環境で実行する。**対象の差分がビルド設定、テストハーネス設定、CI設定、依存定義を変更している場合、監査済み前提は失効する**（設計書 §3.6.4）。
- 進行中の本番障害または緊急の本番操作が必要になった場合は、開発工程を停止しIncident Response Harnessへ昇格する。復旧後の恒久修正は新しいDevelopment taskとして再開する（設計書 §7）。

## 次工程

`CODE_REVIEW_TARGET`がPASSした場合だけPHASE-9を`ready`へ遷移させる。
