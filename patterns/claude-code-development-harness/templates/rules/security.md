<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/rules/`が配布元であり、
利用者の`.claude/rules/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

正本: 設計書 §3.4.1 実行規則4（redaction）, §3.5（Recovery）,
      §3.6.4（評価対象コードの実行）, §3.6.7（UI証跡）,
      §3.9（Tool Gateway）, §11（CODE_REVIEW）, §15（DoD）, §16（制御面の固定）

--- 本規則の対象 ---

本規則は「ハーネス自体の運用セキュリティ」を扱う。すなわち、
Agentが秘密情報へ到達しないこと、証跡へ秘密情報を残さないこと、
未信頼コードの実行を隔離すること、制御面の改変を防ぐことである。

アプリケーションコードの脆弱性審査（OWASP等）はSecurity Reviewerの
レビュー観点であり、設計書 §8.4 Evaluator層の責務に属する。
本規則§7でレビュー観点として扱う。

--- パス境界との関係 ---

読取り・書込みの具体的なパス境界とその強制方法は
`.claude/rules/permissions.md`を正本とする。本規則は重複して
列挙せず、秘密情報の取扱いと隔離要件に限定する。
-->

# Security 規則

本規則は、ハーネス運用における秘密情報の取扱い、未信頼コードの隔離、制御面の保護、およびセキュリティレビューの要件を定める。

## 1. 秘密情報への到達を防ぐ

### 1.1 read denyは全Agent共通

```text
.env
.env.*
secrets/**
```

- **`PostToolUse`では防げない。** `PostToolUse`は操作**後**の検知であり、秘密情報の読取り・書込み自体を予防できない（設計書 §3.5）。機密パスはpermissionsおよび`PreToolUse`で遮断する。
- context manifestの`denied`は宣言であって強制ではない（設計書 §3.3）。permissionsとPreToolUse Hookへ変換する。

### 1.2 秘密情報をコードへ書かない

- ソースコード、テストコード、設定ファイル、テストデータ、ドキュメントへ秘密情報を書かない。
- **テストデータは実データの複製ではなく、意図を持った合成データにする**（設計書 §3.6, §2）。
- 秘密情報が必要な処理は、環境変数またはsecret managerを経由する。

## 2. 証跡のredaction（設計書 §3.4.1 実行規則4）

> **証跡へsecretの値を保存してはならない。**

- コマンド**引数**、**標準出力**、**標準エラー**、**成果物パス**を保存前にredactionする。
- agent-runへ`evidence_redacted: true`と`secret_detected`を記録する。
- **secret検出時はrunを`failed`にし、安全な証跡へ置換するまでゲート判定に利用しない。**

### 2.1 raw logはAgentに書かせない（設計書 §3.6.6）

stdout / stderrのraw logは、**信頼済みRunnerがcapture・redactionしてimmutableな参照を返す。** Agentは参照と要約だけをagent-runへ記録する。**ログ用prefixをwrite allowlistへ追加してはならない。**

### 2.2 画像はredactionが効かない（設計書 §3.6.7）

UI証跡のスクリーンショットは**画像であり、実行規則4のredactionで保護できない。**

- **preview環境へ本番データ・実PIIを載せない構成が一次的な対処である。**
- 画面へ秘密情報が表示された場合、**当該証跡を保存せずrunを`failed`とする。**

## 3. 未信頼コードの実行（設計書 §3.6.4）

Agentが実行するテストは、**そのAgentが評価しようとしている未信頼の変更そのもの**である。テストコード、ビルドスクリプト、プラグイン、依存は任意コードを実行でき、秘密情報の読取り、外部送信、ファイル改変に到達し得る。

> **悪意ある変更を検出するために実行したコマンドが、その悪意ある変更を実行する。**

| 要件 | 内容 |
|---|---|
| 事前監査 | allowlistへ登録するコマンドは、**推移的な呼出先まで確認**し、外部通信・secret参照・危険操作・対象外書込みがないことを確認したものに限る |
| 確認不能なら実行しない | 監査できないコマンドは実行しない（設計書 §16-2） |
| 隔離環境 | **Network遮断・secret非搭載**の隔離環境で実行する |
| 責務 | 隔離は**強制側の責務**であり、Agentの読解やプロンプトの禁止指示で代替しない |
| 再監査 | 対象の差分がビルド設定、テストハーネス設定、CI設定、依存定義を変更している場合、**監査済み前提は失効する** |

本規定は導入時だけの手順ではなく、**評価対象コードを実行するすべてのrunへ適用する実行時要件**とする。

### 3.1 コマンド名allowlistは防御にならない

allowlistが照合するのは`./gradlew`や`npm`という**入口の名前**であり、その先で何が動くかを見ていない（設計書 §3.6.2）。allowlist一致は「安全」を意味しない。§3の事前監査と隔離を併用する。

### 3.2 Network既定deny

- Networkは**既定deny**とする（設計書 §16-3）。
- 例外が必要な場合（依存解決、調査時のNetworkが許可されたAgent等）は**接続先allowlist**を定義し、agent-runへ記録する。
- Integration Testの外部システムは**ローカルstubまたは隔離コンテナ**で制御し、**本番環境へ接続しない**（設計書 §3.6）。
- UI検証の接続先は**preview originのみ**とし、それ以外を遮断する（設計書 §3.6.7）。

## 4. Bash経由の迂回防止（設計書 §3.6.2, §3.5）

`PreToolUse`で次を拒否する。

```text
;   &&   ||   |   $()   ``   >   >>   <
```

- writable外へのリダイレクトを遮断する。
- **これを行わなければ、Write/Editのwrite scope強制はBash経由で迂回される。**

詳細は`.claude/rules/permissions.md` §4による。

## 5. 制御面の保護（設計書 §16 末尾）

導入時に次を**基準commit SHAとハッシュで固定する。**

```text
CLAUDE.md
.claude/rules/**
.claude/skills/**
.claude/hooks/**
.claude/agents/**
.claude/settings.json
External Runner
品質ゲートscript
```

- **これら制御面の変更を通常の実装タスクから禁止する。**
- 所有者の**明示承認**と**独立Harness Review**なしには新しい基準へ更新しない。
- 全Agentの共通write denyに`.claude/**`を含める（`.claude/rules/permissions.md` §3）。

> 制御面を書換えられるAgentは、自らを拘束する規則を無効化できる。これは証跡改変（設計書 §3.6.1）と同じ構造の問題である。

## 6. 証跡の完全性（設計書 §3.6.1, §10.2）

- **証跡を改変できるAgentは、その証跡を根拠とするゲートを無効化する。**
- agent-runとreview targetは**追記専用・create-only**とする。
- Evaluatorが自らのPASS根拠を書き換えられる構成、Generatorが過去の失敗runを消せる構成を許してはならない。
- `docs/status/gate-runs/**`は**信頼済みRunnerだけ**が書く。

## 7. Security Reviewの観点（設計書 §5 工程表 PHASE-9, §8.4）

Security ReviewerはPHASE-9で、固定された`CODE_REVIEW_TARGET`に対して評価する。

### 7.1 レビュー観点

- 認証・認可の境界と、その回避経路
- 入力検証（信頼できない入力の到達範囲）
- インジェクション（SQL、コマンド、テンプレート、パス）
- 秘密情報の混入、ログ出力、エラーメッセージからの漏洩
- 権限昇格、IDOR、アクセス制御の欠落
- 暗号処理の誤用、乱数の品質
- 依存の既知脆弱性
- 監査ログの欠落

### 7.2 判定

- 指摘を**blocking / non-blocking**へ分類する。
- `CODE_REVIEW`ゲートは「Code ReviewerとSecurity Reviewerの**blocking指摘ゼロ**」を条件とする（設計書 §11）。
- Security Reviewerは**read-only**とし、プロダクションコードを直接修正しない。指摘と必須変更をレビュー成果物へ記録し、Generatorへ差し戻す（設計書 §3.4 適用原則）。

### 7.3 機械判定との分担（設計書 §11.1）

| 機械判定 | LLMレビュー |
|---|---|
| 依存関係スキャン、秘密情報の混入、越権書込み、変更範囲の逸脱 | 認可設計の妥当性、攻撃経路の想定、例外・境界ケースの漏れ |

**「無いことの証明」をLLMの読解に依存しない。** 変更範囲の逸脱や秘密情報の混入は、変更前の状態を持たないAgentには原理的に判定できない。**変更一覧の証跡を入力として与える**（設計書 §11.1）。証跡が無い場合、`residual_risks`へ独立検証できていない旨を記録し、Orchestratorへ機械的検証を要求する。

## 8. Recovery（設計書 §3.5 Recovery行）

| 事象 | 対応 |
|---|---|
| 秘密情報を検出 | 当該タスクを**FAIL**とする。安全な証跡へ置換するまでゲート判定に利用しない |
| 秘密情報が露出した | 露出したsecretを**ローテーションする** |
| 自動コミット | **禁止**。Agentは自動コミットしない |
| 復旧 | チェックポイントへ復旧する |
| 判断困難 | **人間へエスカレーションする** |

進行中の本番障害または緊急の本番操作が必要になった場合は、開発工程を停止し、Incident Response Harnessへ昇格する（設計書 §7 冒頭）。復旧後の恒久修正は新しいDevelopment taskとして再開する。

## 9. 外部ツール接続（設計書 §3.9）

外部機能は、**汎用APIをそのまま大量公開せず、用途別の狭いツールとして公開する。**

```text
Agent → Tool Gateway（入力検証 / 権限判定 / 情報量削減 / 冪等性・現在状態確認 / 監査ログ）→ MCP Server / External System
```

- 書込み系ツールには`expected_status`や対象IDを**必須**とし、曖昧な自然言語だけで更新しない。
- Browser操作をMCPで供給する場合もTool Gatewayを経由させ、`ui-verifier`の`tools`へ明示的に追加する（設計書 §3.6.5）。

## 10. Git操作（設計書 §16-1）

- main / masterでは**書込みを止める。**
- 既存作業を保護し、**事前許可された命名規則**でfeatureブランチを作成し、開始時SHAを記録する。
- 個別承認が必要なリスク条件では**Human Gateを先に通す。**

## 11. Definition of Doneのセキュリティ条件（設計書 §15）

- Code ReviewとSecurity Reviewの**blocking指摘がゼロ**である。
- provider APIまたはsignatureで**検証済みのHuman Review Evidence**が現在対象へ束縛され、責任ある人間Reviewerのverdictが`approved`である。

> **AI/LLM ReviewerのPASSは補助証拠に限る**（設計書 §5）。変更を理解した人間Reviewerがコード、テスト、設計意図の一致を確認するまで完了としない。
