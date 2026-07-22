# PHASE-0: 初期化

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §5.0):
  id: PHASE-0
  inputs: repository
  outputs: baseline, commands, progress, handoff
  entry_gate: —
  exit_gate: INITIALIZATION
  allowed_agents: initializer, harness-reviewer, context-builder
-->

## 目的

実装を開始する前に、実行環境と既存状態を検証し、継続セッションが会話履歴なしで再開できる状態を作る（設計書 §5.0、§3.2）。

## 開始条件

`entry_gate`は`—`であり、開始ゲートの検証を不要とする（設計書 §3.4.1 実行状態と遷移）。

## 入力

- リポジトリ（構造、主要モジュール、既存ドキュメント）

## 担当Agent

| 役割 | Agent | profile |
|---|---|---|
| Generator | `initializer` | generator / production code write禁止 |
| Evaluator | `harness-reviewer` | evaluator |
| コンテキスト編成 | `context-builder` | context_builder |

`allowed_agents`に無いAgentをこのPhaseで起動してはならない。片側の記載欠落、不一致、未定義IDはfail-closedで拒否する（設計書 §3.4.1 関係と多重度）。

## 手順

1. リポジトリ構造、主要モジュール、既存ドキュメントを調査する。
2. ビルド、UT、IT、静的解析のコマンドを**推測せず実行して確認する**（設計書 §5.0）。
3. 既知の失敗、環境依存、必要なサービスを`docs/status/baseline.yaml`へ記録する。
4. 実行環境の能力を検出し、`docs/project/harness-capabilities.yaml`へ記録する（設計書 §3.5.1）。Browser / Previewの供給方式と接続先allowlistもここへ記録する（設計書 §3.6.5）。
5. `docs/status/progress.yaml`、タスク一覧、最初のcontext manifest、agent-runディレクトリを作成する。
6. 初回handoffを作成する（設計書 §9.1の必須項目を満たすこと）。
7. Harness Reviewerが、継続セッションから再開可能かを独立評価する。

## 成果物

- `docs/status/baseline.yaml`
- `docs/project/harness-capabilities.yaml`
- `docs/status/progress.yaml`
- `docs/context/manifests/<task>.context.yaml`
- `docs/features/<feature-id>/handoffs/<name>.md`
- `docs/status/agent-runs/<task>/<run-id>.yaml`

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `INITIALIZATION` | exit gate | baseline、commands、progress、初回handoffが揃い、継続可能（設計書 §11） |
| `ACCESS_POLICY` | cross-cutting | 各AgentRun開始時に評価（設計書 §11.0） |
| `STATE_REVISION` | cross-cutting | 各`progress.yaml`更新時に評価（設計書 §11.0） |

### 終了条件（設計書 §3.2「初期化の終了条件」）

- 開発・UT・IT・静的解析コマンドが**実際に動作する**。
- 現在のテスト結果と既知の失敗が記録されている。
- プロジェクト構造、主要モジュール、制約、未解決事項が記録されている。
- 次のContinuation Agentが会話履歴なしで再開できる。

## ブロック時の戻り先

初期化（設計書 §11）。

## 注意事項

- `baseline.yaml`は**信頼境界ではない**。ここに記録したコマンド文字列をそのままshellへ渡さず、Bash allowlist内のエントリと照合し、一致しなければfail-closedで拒否する（設計書 §3.6.2）。
- allowlistへ登録するコマンドは、推移的な呼出先まで確認した監査を経たものに限る。確認できないコマンドは実行しない（設計書 §16-2、§3.6.2）。
- `progress.yaml`の更新者はDevelopment Orchestratorだけとする。Initializerは更新を要求し、直接更新しない（設計書 §3.4.1 実行規則6）。
- Initializerはproduction codeを書かない（設計書 §3.4.1 AgentDefinition実値表）。

## 次工程

`INITIALIZATION`がPASSし、blocking issueがなく、必須成果物と証跡が揃った場合だけ、PHASE-1を`ready`へ遷移させる（設計書 §3.4.1 実行規則7）。
