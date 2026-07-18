<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/rules/`が配布元であり、
利用者の`.claude/rules/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

正本: 設計書 §6（TDD実装方針）, §7（Integration Test方針）,
      §11（品質ゲート）, §11.1（機械判定とLLM判定の分離）, §15（DoD）

--- 設計書が対象外とするもの ---

設計書 §1.2はContract Testを現時点の対象外と定める。本規則も扱わない。

--- 技術スタック非依存 ---

設計書 §7冒頭は「以下は技術スタックに依存しない規範とし、具体的な
フレームワークやテスト基盤はプロジェクトprofileで定義する」と定める。
本規則も同様に非依存とし、Java / Spring等の具体例は
設計書 §7.1.1のreference profile（非規範例）を参照する。
利用者はプロジェクトのtest runnerを`baseline.yaml`へ実測記録すること。
-->

# Testing 規則

本規則は、UT駆動TDDとIntegration Testの方針、およびそれらが満たすべき品質ゲートを定める。設計書 §6、§7の正本である。

> **テストの役割分担**
>
> UTは細粒度・高速なTDDループで設計と実装を駆動する。Integration Testは、Runtime Context、Datastore、トランザクション、シリアライズ、メッセージング等の実連携を機能単位で保証する（設計書 §6 冒頭）。

## 1. テストコマンドの出所

すべてのテストコマンドは`docs/status/baseline.yaml`の**実測結果**に基づく（設計書 §5.0）。**推測しない。**

> **`baseline.yaml`は信頼境界ではない**（設計書 §3.6.2）。Git内の編集可能なファイルであり、baselineから読んだ文字列をshellへ直接渡さない。Bash allowlistとの照合は`.claude/rules/permissions.md` §4による。

baselineに無いコマンドが必要な場合、代替を推測して実行せず、blockingな未解決事項としてOrchestratorへ差し戻す。

## 2. Unit Testポリシー（設計書 §6.2）

| 項目 | 方針 |
|---|---|
| 目的 | ドメインロジック、状態遷移、条件分岐、計算、例外、境界値を高速に検証 |
| Runtime Context | **原則として起動しない** |
| DB・Repository | インターフェース境界で代替し、テスト対象を小さく保つ |
| 外部API | モックまたはスタブ |
| 実行速度 | 頻繁に全関連UTを実行できる速度を維持 |
| 命名 | 振る舞いと期待結果が分かる名前にする |
| 対象 | 一つのクラス、関数、または小さな協調単位 |

**UTにDB起動やRuntime Context起動が必要になったら、UT/ITの切り分けが誤っている。** 差し戻す。

## 3. 標準サイクル（設計書 §6.1）

```text
要件・受入条件・詳細設計を確認
↓
UTケース設計
↓
UT作成 → RED確認
↓
最小実装 → GREEN_CONFIRMATION
↓
REFACTOR
↓
対象UT・関連UT・全UT → POST_REFACTOR_GREEN
↓
Integration Test作成・更新
↓
Integration Test実行
↓
レビュー・完了判定
```

**PHASE-7の`POST_REFACTOR_GREEN`はUTだけを対象とする。Integration Testの作成・更新・実行はPHASE-8で行う**（設計書 §6.5 末尾）。

### 3.1 RED Gate（設計書 §6.3）

- テストコードが作成済みで、**実行可能**である。
- 失敗が、**未実装または期待する振る舞いとの差**によって起きている。
- **単なるコンパイルエラーだけでRED完了としない。** 必要なら最小の型・インターフェースを用意する。
- 失敗理由をタスクまたは状態ファイルへ記録する。

### 3.2 GREEN_CONFIRMATION（設計書 §6.4）

- 対象UT、関連UT、**全UT**が成功している。
- **テストの削除、無効化、assertion弱体化を行っていない。**
- **対象タスク外の先行実装をしていない。** タスク文書の`Out of scope`が判定基準である。
- 最小限の実装で受入条件を満たしている。

### 3.3 REFACTOR Gate（設計書 §6.5）

- 重複、責務、命名、例外、トランザクション境界、パッケージ構造を改善する。
- リファクタリング中もUTを短い間隔で実行する。
- リファクタリング後に**対象・関連・全UTを再実行**する。
- `POST_REFACTOR_GREEN`は、**コマンド、終了コード、結果要約を記録した状態**とする。**これを満たすまでレビュー対象を固定しない。**

### 3.4 PREPARATORY_REFACTOR（設計書 §6.5、例外）

通常のREDを安全に書けない構造の場合**に限り**許可する。

1. baseline GREENを確認する。
2. 既存挙動をcharacterization testで保護し、`GREEN_CONFIRMATION`を記録する。
3. characterization test集合を**固定する。** 以後、削除・変更・skip・assertion弱体化を禁止する。
4. 振る舞いを変えない最小の構造整理を行う。
5. **同じcommand**で同じテストの成功を再確認する。前後のtest artifact hashが**完全一致**しなければ失敗とする。
6. `baseline_commit`、`result_commit`、`diff_base`、前後の`diff_hash`、同一の`test_command`、各`test_artifact_hash`、結果要約をcheckpointへ記録する。
7. 通常のREDへ進む。

**変更してはならないもの**: 公開API、永続化形式、認証・認可、監査、秘密情報境界。必要な場合は機能実装と分離した独立Development taskへ昇格する。独立レビューが必要、複数責務・複数component、architecture判断、または大規模変更でも同様に昇格する。

使用した場合、`IMPLEMENTATION_REVIEW_TARGET`へ`preparatory_refactor_used: true`と`preparatory_checkpoint_ref`を必ず含める。**Implementation Evaluatorはproduction diffとこの宣言の一致を検査し、不一致ならfail-closedで差し戻す**（設計書 §6.6）。

## 4. Integration Testポリシー（設計書 §7）

| 項目 | 方針 |
|---|---|
| Runtime Context | 実際の構成を使用 |
| Datastore | 本番と互換性のある**隔離環境**を使用 |
| Persistence Adapter | 実実装を使用 |
| Transaction | 実際のコミット、ロールバック境界を検証 |
| Serialization | 実際のデータ・メッセージ変換を使用 |
| 内部Service | **原則としてモックしない** |
| 外部システム | Stubまたは隔離コンテナ等で制御 |
| 実行タイミング | 機能単位の節目、PR/CI、完了ゲート |

### 4.1 確認する代表項目（設計書 §7.1）

- 入力境界 → Application Service → Persistence Adapter → Datastoreの連携
- データマッピング、クエリ、制約、ロック、トランザクション
- 認証・認可、バリデーション、例外ハンドリング
- メッセージ送受信、シリアライズ、イベント発行条件
- 外部APIアダプターの要求・応答変換と障害時挙動

### 4.2 静かなフォールバックの禁止（設計書 §3.6.6）

**サービス未起動時にインメモリ等の代替へ切り替わる構成は、ITが実構成を検証していないことを隠す。** Integration Test Reviewerはこれをblockingとして扱う。

### 4.3 本番接続の禁止

Integration Test Engineerは**本番環境へ接続しない**（設計書 §3.6）。外部システムはローカルstubまたは隔離コンテナで制御する。接続先はallowlistで強制する（`.claude/rules/permissions.md` §7）。

## 5. テスト設計（PHASE-6）の要件（設計書 §11 TEST_DESIGN）

各UT / ITについて、**正常・異常・境界**の3分類を設計する。

| 分類 | 内容 |
|---|---|
| 正常系 | ACが満たされる標準的な入力と期待結果 |
| 異常系 | 詳細設計が定義した例外とバリデーションに対応させる |
| 境界値 | **実際に境界を突く** |

> **境界値は実際に境界を突くこと。** 範囲が`1..100`なら`0, 1, 100, 101`であって、`50`は境界値ではない。空、null、最大長、桁溢れ、時刻の境界も同様に扱う。

ITの境界はUTと異なり、永続化・設定・時間の境界（カラム最大長、一意制約の境界、バッチサイズ、タイムアウト、接続プール枯渇）に現れる。

**3分類が揃わない場合は、そう判断した理由を書く。** 「境界値なし」と「境界値を検討していない」は区別できなければならない。理由の無い空欄は漏れとして扱う。

### テストデータ

- 各ケースから**解決可能**にする。「適当な注文データ」では実装者が書けない。
- **秘密情報と本番データを持ち込まない**（設計書 §3.6, §2）。実データの複製ではなく、意図を持った合成データにする。
- 共有フィクスチャは、どのケースが依存するかを明示する。**テスト間の暗黙の依存は、後でIT並列実行を壊す。**

## 6. 禁止事項

- **テストを削除・無効化・skipしない。assertionを弱体化しない**（設計書 §6.4, §8.3）。テストが落ちたら**実装を直す。** 設計書 §3.10は`weakened-test`をevalケースとして明示している。
- **RED前に本実装をしない**（設計書 §8.3）。
- **対象タスク外の先行実装をしない**（設計書 §6.4）。
- **CIを無効化しない**（設計書 §3.6）。
- **テストデータへ秘密情報・本番データを持ち込まない。**
- **固定したcharacterization testを変更しない**（`PREPARATORY_REFACTOR`時。設計書 §6.5）。
- **PHASE-7でIntegration Testを作成・更新・実行しない**（設計書 §6.5 末尾）。

## 7. テストに関わる品質ゲート（設計書 §11）

| ゲート | 主な条件 | 種別 |
|---|---|---|
| `TEST_DESIGN` | UT/IT観点、正常・異常・境界、データが定義 | Exit gate（PHASE-6） |
| `UNIT_TEST_RED` | UTが意図した理由で失敗 | Intra-phase（PHASE-7） |
| `UNIT_TEST_GREEN` | `POST_REFACTOR_GREEN`完了、対象・関連・全UT成功、テスト弱体化なし、`result_commit`に証跡を束縛 | Intra-phase（PHASE-7） |
| `INTEGRATION_TEST` | 必要ITが成功、実ランタイム・永続化層・Tx・設定を検証 | Intra-phase（PHASE-8） |
| `UI_VERIFICATION` | UI変更時に表示・操作・viewport・console errorを実ブラウザで検証。非UI変更はnot applicable | Intra-phase（PHASE-8） |

`UNIT_TEST_RED`と`UNIT_TEST_GREEN`は**RED-GREEN-REFACTORの反復ごとに評価する。** 一つのPhaseRunが複数のGateRunを持つため、`progress.yaml.gates`の値は当該Phaseにおける**最新のGateRun**の結果を表す（設計書 §11.0）。

### PHASE-7の順序（設計書 §6.6）

```text
GREEN_CONFIRMATION → REFACTOR → POST_REFACTOR_GREEN
  → IMPLEMENTATION_REVIEW_TARGET → IMPLEMENTATION_EVALUATION → PHASE-8 ready
```

### PHASE-8の順序（設計書 §7.2）

```text
INTEGRATION_TEST → UI_VERIFICATION → CODE_REVIEW_TARGET → PHASE-9 ready
```

Integration TestまたはUI検証後にコード・テスト・証跡が変わった場合は、**それ以前の結果を必要な範囲で再実行してから**最終対象を固定する。

## 8. UI Verification（設計書 §7.2）

Plannerがタスクへ`ui_change: true|false`を記録し、Context Builderがcontext manifestへ転記する。

> **Generatorの自己申告だけでnot applicableにしてはならない**（設計書 §7.2）。Orchestratorと独立Reviewerは、固定されたreview targetのchanged files manifest、route・component・style・template等のUI資産規約から値を**再検証する。** 未指定、判定不一致、対象SHA不一致はfail-closedでゲート判定を拒否する。

`ui_change: true`の場合、通常のtest・typecheck・buildに加えて次を**同じcommit SHAへ結び付けた**証跡とする。

- 対象画面を実際に表示したスクリーンショット
- 受入条件に関係する操作結果
- 変更に関係するnarrow / wide等のviewport確認
- browser consoleの新規errorが**0件**であること

GateRunには`ui_change`、判定者、判定根拠、review targetのcommit SHAを必ず記録する。

**previewまたはbrowser機能を利用できない場合は、未検証として完了をブロックする。** これをnot applicableへ読み替えてはならない（設計書 §3.6.5）。`ui_change: false`の場合**だけ**not applicableとして扱う。

実行者は専用`ui-verifier`とする。供給方式とNetwork境界は`.claude/rules/permissions.md` §8による。

## 9. 機械判定とLLM判定の分離（設計書 §11.1）

| 機械判定にするもの | LLMレビューにするもの |
|---|---|
| コンパイル、UT、IT、静的解析、フォーマット、依存関係スキャン | 要件の曖昧性、設計妥当性、責務分離、保守性、回帰リスク |
| ファイル存在、ID重複、テンプレート必須欄、終了コード | 要件と実装の意味的な対応、例外・境界ケースの漏れ |
| 変更範囲の逸脱、越権書込み、秘密情報の混入 | 変更内容が要件・設計の意図に合致しているか |

> **Evaluatorの読解を機械的検査の代替にしない**（設計書 §11.1）。変更範囲の逸脱のような「無いことの証明」は、変更前の状態を持たないAgentには原理的に判定できない。

read-onlyのEvaluatorへ変更範囲の確認を求める場合は、Runnerまたは`PostToolUse`が生成した**変更一覧の証跡を入力として与える。** 証跡が無い場合、Evaluatorは「読んだ限り見当たらない」を根拠にPASSとせず、`residual_risks`へ独立検証できていない旨を記録し、Orchestratorへ機械的検証を要求する。

**ただしテスト弱体化の検出は差分の読解であり、再実行に依存しない**（設計書 §3.6.3, §6.4, §8.4）。

## 10. Definition of Doneのテスト条件（設計書 §15）

- UTのRED-GREEN-REFACTORを完了している。
- 必要なIntegration Testが作成され、成功している。
- 全UT、全対象IT、静的解析、フォーマットが成功している。
- **テストの削除・無効化・弱体化がない。**
- UI変更では`UI_VERIFICATION`が成功し、非UI変更ではnot applicableである。
- 要件IDからタスク、UT、IT、実装への追跡が成立している（設計書 §12）。
