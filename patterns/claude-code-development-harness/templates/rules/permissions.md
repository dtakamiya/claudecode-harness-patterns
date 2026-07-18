<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/rules/`が配布元であり、
利用者の`.claude/rules/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

正本: 設計書 §3.6, §3.6.1〜§3.6.7, §3.4.1 実行規則3, §14.1〜§14.3, §11 ACCESS_POLICY

--- このファイルの位置づけ（重要） ---

設計書 §3.6は「エージェント定義に記載したWrite範囲は論理ルールであり、
記述しただけではファイルACLにならない」と定める。**本ファイルも同じく
宣言であり、それ自体は強制力を持たない。** 本ファイルは、強制側
（permissions設定、PreToolUse Hook、sandbox、External Runner）が
実装すべき規則の正本であって、強制の実体ではない。

したがって本ファイルの利用者は、ここに書かれた規則を
`.claude/settings.json`のpermissions、`.claude/hooks/pre-tool-use.sh`、
sandbox設定、`scripts/verify-permissions.sh`のいずれかへ**変換して**
初めて設計書 §11の`ACCESS_POLICY`ゲートを満たす。変換せずに本ファイルを
置いただけの状態は、設計書 §3.5.1の`Manual`モードであり、
本格運用に使用しない。
-->

# Permissions / アクセス境界規則

本規則は、各Agentの読取り・書込み・Shell・Networkの境界と、その強制方法を定める。設計書 §3.6、§3.6.1〜§3.6.7の正本である。

> **宣言は境界ではない**
>
> 本規則に書いたWrite範囲は論理ルールである。強制側（permissions、`PreToolUse` Hook、sandbox、External Runner）へ変換しなければファイルACLにならない（設計書 §3.6）。宣言と実効制御が一致しない場合、`ACCESS_POLICY`ゲートはFAILであり、実装へ進まない（設計書 §14.3）。

## 1. 実効権限の決定規則（設計書 §3.4.1 実行規則3）

実効的な権限と利用可能toolsは、次の**積集合**とする。

```text
Agent定義（tools / disallowedTools / permissionMode）
  ∩ Skill定義
  ∩ context manifest の access_policy
  ∩ 実行環境の permissions / sandbox
```

- 未指定または競合時は**fail-closed**とする。
- **Skillによって権限を拡張しない。** Skillは手順の再利用であって、権限の付与ではない。
- context manifest自体はアクセス制御ではない（設計書 §3.3）。manifestの`access_policy`は、permissionsとPreToolUse Hookへ変換して初めて強制される。

## 2. Write範囲の解決規則（設計書 §3.6.1）

論理Write範囲はディレクトリ単位で記すが、**prefix一致でそのまま強制してはならない。**

| 規則 | 内容 |
|---|---|
| 既定deny | 明示的に許可したパスだけを書込み可能にする |
| 最長一致 | 許可と禁止が重なる場合はmost-specific-winsで判定する |
| 競合時deny | 同一具体度の競合、および曖昧な場合はdenyを採る |
| 正規化先行 | canonical pathへ正規化してから判定する |

### パス正規化（設計書 §3.6.1）

判定前に対象パスをcanonical pathへ正規化し、次を拒否する。

- `..` traversalを含むパス
- リポジトリルート外へ解決されるパス
- symlink

**ワイルドカードを正規化前のraw文字列でglob照合しないこと。** `docs/features/../../etc/x`のようなパスで許可範囲を迂回され得る。

### 証跡は追記専用（設計書 §10.2, §3.6.1）

`docs/status/agent-runs/**`や`docs/features/<feature-id>/reviews/**`を**prefixで許可してはならない。** 過去のrun、他タスクのrun、他Agentのrun、評価対象のrunを上書きでき、追記専用要件を機械的に保証できない。

- 書込み対象は**現在taskの自分のファイル一点**へ限定する。
- **既存ファイルへのWrite/Editを拒否する（create-only）。** 存在するパスへの書込みは内容に関わらずfail-closedとする。
- `<task>`は`progress.yaml`の`current_task`と一致しなければならない。

> **証跡を改変できるAgentは、その証跡を根拠とするゲートを無効化する。** Evaluatorが自らのPASS根拠を書き換えられる構成、Generatorが過去の失敗runを消せる構成を許してはならない（設計書 §3.6.1）。

## 3. Agent別の論理Write範囲（設計書 §3.6）

| Agent | 論理Write範囲 | Shell / Network | 強制手段 | 禁止事項 |
|---|---|---|---|---|
| Requirements Analyst | `docs/features/<feature-id>/requirements/**` | Shell原則なし、調査時のみNetwork | tools制限＋Hook、またはsandbox＋Runner検証 | ソースコード編集 |
| Architect | `docs/features/<feature-id>/design/**`, `decisions/**` | 読取系のみ、調査時のみNetwork | tools制限＋Hook、またはsandbox＋Runner検証 | 実装変更 |
| Context Builder | `docs/context/manifests/**` | Shell / Networkなし | 専用tool＋permissions＋secret path deny | `state-runner`、Bash、handoff・業務成果物・Agent定義・permissions設定・`progress.yaml`の編集 |
| TDD Generator | 対象モジュール、テスト、agent-run成果物、`docs/status/changes/<task>.yaml`、`docs/features/<feature-id>/reviews/targets/<task>-implementation.yaml` | build/test限定、Network原則なし | permissions＋sandbox＋Bash allowlist＋HookまたはRunner検証 | 対象外タスク、秘密情報、CI無効化 |
| Integration Test Engineer | `integration_test_engineer_write_allowlist` | test/container限定、ローカルスタブのみ | permissions＋接続先allowlist＋write allowlist検証 | 本番環境接続、production code・Unit Test・ビルド・CI・依存定義の変更 |
| UI Verifier | `docs/features/<feature-id>/tests/ui-evidence/**`, agent-run成果物 | Browser / Previewのみ、ローカルpreview限定 | 専用tool＋接続先allowlist＋write scope | ソースコード修正、外部サイト・本番接続、フォーム送信等の外部更新 |
| Evaluator | `docs/features/<feature-id>/reviews/**`, `docs/status/agent-runs/**` | test/static analysis、Network原則なし | 原則Read-only＋レビュー出力のみ許可 | プロダクションコード直接修正 |
| Completion Auditor | `docs/features/<feature-id>/reviews/**`, `docs/status/agent-runs/**` | 検証コマンドのみ、Networkなし | Read-only＋監査結果のみ許可 | 成果物の自己修正、`progress.yaml`直接更新 |

上表の`reviews/**`と`agent-runs/**`は、§2「証跡は追記専用」により**現在taskの自分のファイル一点**へ具体化してから強制する。

### 全Agent共通のread deny

```text
.env
.env.*
secrets/**
docs/archive/**
```

### 全Agent共通のwrite deny

| パス | 理由 |
|---|---|
| `docs/status/progress.yaml` | Orchestratorのsingle writer（設計書 §10） |
| `docs/status/gate-runs/**` | 信頼済みRunnerだけが書く証跡 |
| `docs/context/manifests/**` | Context Builderの領分（設計書 §3.3） |
| `.claude/**` | Agent定義・permissions設定の自己改変を禁止 |

## 4. Bash allowlist（設計書 §3.6.2）

Shell範囲を「build/test限定」等と定めた行は、**呼び出し可能なコマンド名の固定allowlist**として強制する。allowlistはCompatibleモードの代替手段ではなく、**Fullモードでも必須**とする。

### `baseline.yaml`は信頼境界ではない

設計書 §5.0はコマンドを実測して`baseline.yaml`へ記録すると定めるが、これはGit内の**編集可能なファイル**である。改ざんされていればAgentは指示に従うだけで任意コマンドの実行に到達し得る。

- baselineから読んだ文字列を**shellへ直接渡さない。**
- allowlist内のエントリと**照合**し、一致しなければfail-closedで拒否する。
- baselineのコマンドがallowlistに無い場合、**推測で代替コマンドを実行せず**、blockingな未解決事項としてOrchestratorへ差し戻す。

### shell metacharacterの遮断

`PreToolUse`で次を拒否する（設計書 §3.5 Preventive行）。

```text
;   &&   ||   |   $()   ``   >   >>   <
```

- writable外へのリダイレクトを遮断する。
- **これを行わなければ、Write/Editのwrite scope強制はBash経由で迂回される。**

### allowlist一致は「安全」を意味しない

allowlistが照合するのは`./gradlew`や`npm`という**入口のコマンド名**であり、その先で動くビルドスクリプト、テストコード、プラグイン、依存を見ていない。**推移的な呼出先の安全性はallowlistでは保証できない。** §6を併せて適用する。

## 5. 実行時作業領域（設計書 §3.6.3）

論理Write範囲は**成果物の書込み範囲**であり、コマンド実行に伴う副次的な書込みを含まない。`./gradlew test`は`build/`と`.gradle/`へ、`mvn test`は`target/`へ、`npm test`は`node_modules/.cache`へ書込む。

> **論理Write範囲だけを既定denyで強制すると、これらのコマンドは全Agentで実行不能になり、`GREEN_CONFIRMATION`と`UNIT_TEST_GREEN`が原理的に成立しない**（設計書 §3.6.3）。

- 実行時作業領域は**リポジトリ外の使い捨て領域**（sandbox内のtmpfs、コンテナ、scratch、使い捨てworktree）とし、canonical pathがリポジトリルート外へ解決されることを条件に書込みを許可する。これは論理Write範囲の拡張ではない。
- リポジトリ内へビルド出力を書くツール構成では、**出力先をリポジトリ外へ向ける設定を強制側が与える。** 与えられない場合、当該Agentはそのコマンドを実行せず、Runnerが自らの権限で実行して結果を証跡として渡す。
- **追跡対象ファイル、レビュー対象コード、`docs/**`、`.claude/**`への書込みは、実行時作業領域を理由に許可しない。**
- 実行時作業領域はrun終了時に破棄し、次のrunへ状態を持ち越さない。持ち越すとテスト結果が前のrunに依存し、証跡がcommitへ束縛されなくなる。

Evaluatorがテストを再実行する構成では、この領域が無ければ再実行を要求してはならない。再実行できない場合は`residual_risks`へ記録してOrchestratorへ機械的検証を要求する（設計書 §11.1）。**テスト弱体化の検出は差分の読解であり、再実行に依存しない。**

## 6. 評価対象コードの実行（設計書 §3.6.4）

Agentが実行するテストは、**そのAgentが評価しようとしている未信頼の変更そのもの**である。テストコード、ビルドスクリプト、プラグイン、依存は任意コードを実行でき、秘密情報の読取り、外部送信、ファイル改変に到達し得る。

> **悪意ある変更を検出するために実行したコマンドが、その悪意ある変更を実行する**（設計書 §3.6.4）。

評価対象コードを実行するAgentには次を必須とする。

- allowlistへ登録するコマンドは、**推移的な呼出先まで確認した監査**（外部通信、secret参照、危険操作、対象外書込みがないこと）を経たものに限る。**確認できないコマンドは実行しない。**
- 実行環境を**Network遮断・secret非搭載の隔離環境**とする。これは強制側の責務であり、Agentの読解やプロンプトの禁止指示で代替しない。
- **対象の差分がビルド設定、テストハーネス設定、CI設定、依存定義を変更している場合、監査済み前提は失効する。** 強制側は当該変更を検出したrunで再監査を要求し、未監査のまま実行させない。

本規定は導入時だけの手順ではなく、**評価対象コードを実行するすべてのrunへ適用する実行時要件**とする。

## 7. Integration Test Engineerの特例（設計書 §3.6.6）

同Agentは自らが書いたテスト支援設定を、**同じrunで自らの権限で実行する。** §6とそのままでは両立しないため、専用のwrite profileで拘束する。

`integration_test_engineer_write_allowlist`を唯一のwrite profileとし、context manifestが**個別のcanonical pathで列挙した**次だけを許可する。

- Integration Testコード
- テストfixture
- ローカルstub定義
- 隔離container定義
- テスト専用profile
- `docs/status/agent-runs/<current-task>/<new-run-id>.yaml`の新規作成

**含めないもの**: production code、PHASE-7のUnit Test、本番接続設定、ビルド設定、CI設定、依存定義、他taskまたは既存のagent-run。

```yaml
# PHASE-8のcontext manifestは、profile名と個別pathを併記する
access_policy:
  write_profile: integration_test_engineer_write_allowlist
  writable:
    - <Integration Testコードのcanonical path>
    - <許可されたfixtureまたはテスト支援設定のcanonical path>
    - docs/status/agent-runs/<current-task>/<new-run-id>.yaml
```

- 「テスト支援設定」は**明示的に列挙したパス**へ限定する。ディレクトリprefixで広く許可しない。
- 同一run内でテスト支援設定が変更された場合、強制側は§6に従い再監査を要求する。**未監査の設定変更を含むrunの証跡を`INTEGRATION_TEST`ゲートの根拠にしない。**
- agent-runへ`test_support_configuration_changed`、`independent_reaudit_required`、`independent_reaudit_status`、`independent_reaudit_evidence_ref`を記録する。設定変更時は再監査statusが`passed`で証跡参照が検証できるまでITを実行せず、`INTEGRATION_TEST`をrequestしない。
- stdout / stderrのraw logはAgentへ書かせず、**信頼済みRunnerがcapture・redactionしてimmutableな参照を返す。** ログ用prefixをallowlistへ追加してはならない。

## 8. UI Verifierの供給とNetwork境界（設計書 §3.6.5, §3.6.7）

### Browser / Previewは組込みtoolではない

`ui_verifier` profileの`Browser / Preview`は論理モデルであり、**実在のtool名ではない。** Agent定義へ`Browser / Preview`と記述しても、`ui-verifier`はブラウザを操作できない。次のいずれかで供給し、`docs/project/harness-capabilities.yaml`へ記録する。

- Browser操作を提供する**MCP serverを接続**し、Tool Gateway経由で用途別の狭いツールとして公開する。この場合、`ui-verifier`の`tools`へ当該tool名を明示的に追加する。
- **または、信頼済みRunnerがブラウザ操作を実行**し、証跡を`ui-verifier`へ渡す。この場合`ui-verifier`は証跡の記録と判定だけを行う。

> **`ui-verifier`にBashを与えてブラウザ操作を代替してはならない。** Shell範囲は「Browser / Previewのみ、ローカルpreview限定」でありShellを含まない。Bashを与えると、禁止事項（ソースコード修正、外部サイト・本番接続）が構造的に迂回可能になる（設計書 §3.6.5）。

previewの起動は強制側の責務とし、`ui-verifier`は起動しない。**previewは固定されたreview targetのcommitからビルドする。** 現在のworking treeを指すpreviewでは「同一commit SHAの証跡」が成立しない。

### 「外部更新」の境界（設計書 §3.6.7）

禁止されるのは**外部**の更新であり、受入条件の操作そのものではない。

| 操作 | 扱い |
|---|---|
| 隔離されたローカルpreview環境の**内部で完結する**操作（フォーム送信を含む） | `UI_VERIFICATION`が要求する証跡であり実行する |
| 外部サイト、本番、ステージング、共有環境、第三者APIへ到達する更新 | 禁止 |

**この切り分けをAgentの判断だけに依存させない。** 接続先allowlistでpreview origin以外を遮断する。遮断すれば「外部更新」は構造的に到達不能になる。

### UI証跡とredaction

UI証跡のスクリーンショットは**画像でありredactionが効かない。** preview環境へ本番データ・実PIIを載せない構成が一次的な対処である。画面へ秘密情報が表示された場合、当該証跡を保存せずrunを`failed`とする。

## 9. 強制手段の対応表（設計書 §3.5.1, §14.1, §14.2）

| Fullモード | Compatibleモード |
|---|---|
| `PreToolUse` | permissions、sandbox、専用コマンド、OS権限 |
| `PostToolUse` | Agent終了後の`quality-gate.sh`、Git diff検査 |
| `SubagentStop` | Orchestratorによるagent-runと成果物検証 |
| `Stop` | External Harness Runnerの終了ゲート |
| FileChanged | Git diffベースの変更範囲・secret scan |
| WorktreeCreate | `create-task-worktree.sh`による明示生成 |

いずれの強制手段も無い環境は`Manual`モードであり、**本格運用に使用しない**（設計書 §3.5.1）。

### Fullモードの適用順序（設計書 §14.1）

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

権限設定で広いカテゴリを拒否し、Hooksでプロジェクト固有の条件を追加する。**Hooksだけでサンドボックスの代替をしない。**

### `PostToolUse`は予防ではない（設計書 §3.5）

`PostToolUse`は操作**後**の検知であり、秘密情報の書込み自体を予防できない。機密パスと危険操作はpermissionsおよび`PreToolUse`で遮断し、`PostToolUse`は差分検査と復旧判断に使用する。

## 10. `ACCESS_POLICY`ゲート（設計書 §11.0, §14.3）

本規則の遵守状況は`ACCESS_POLICY`ゲートとして判定する。

| 項目 | 内容 |
|---|---|
| 種別 | Cross-cutting gate |
| 評価時点 | **各AgentRunの開始時。** context manifest検証と同時 |
| 評価者 | Context Builder / Orchestrator |
| FAIL時 | 当該AgentRunを`queued`から進めない |

- manifestがない場合、または**宣言と実効制御が一致しない場合は実装へ進まない。**
- 反復評価するため、`progress.yaml.gates`の値は**最新の評価結果**を表す。**過去にPASSしたことは、現在のrunのPASSを意味しない。**
- GateRunは対象AgentRunの`phase_run_id`へ紐付けて永続化する。

> **Cross-cutting gateを「完了時に一度だけ確認する項目」として実装してはならない。** 予防制御を事後確認へ格下げすることになる（設計書 §11.0）。
