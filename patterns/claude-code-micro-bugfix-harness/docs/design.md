# Claude Code マイクロバグ修正ハーネス設計書

## 1. 目的と原則

再現可能な局所バグを、回帰テストと根本原因への最小修正で安全に直す。機能追加用ハーネスより工程を減らしつつ、TDD、決定論的検証、独立レビューは省略しない。

- featureブランチ上で一つのバグだけを扱う。
- production codeより先に回帰テストを追加し、REDの失敗理由を確認する。
- 症状の抑制、テストの弱体化、エラーの無視でGREENにしない。
- 既存構造とコマンドを使い、独自基盤や将来向け抽象化を追加しない。
- 軽量範囲を外れた時点で変更を止め、上位ハーネスへ昇格する。

## 2. 構成

```text
User
  └─ Micro Bugfix Orchestrator（メインセッション）
       ├─ Explore（read-only調査）
       ├─ TDD Implementer（回帰テストと最小修正）
       ├─ Deterministic Verification（既存コマンド）
       ├─ Code Reviewer（正確性）
       └─ Security Reviewer（脆弱性）
```

メインセッションはスコープ、順序、ゲート、最終報告だけを管理する。調査、実装、レビューは対象と出力を絞ったサブエージェントへ委譲し、会話外の永続状態は持たない。

## 3. ワークフローとゲート

| Phase | 実施内容 | 終了ゲート |
|---|---|---|
| Triage | 再現条件、現在値、期待値、対象外、規約、類似実装、テスト、git状態を確認 | 未確定事項がなく、1〜3ファイルの局所修正 |
| Branch / Baseline | featureブランチを作成または選択し、変更前検証を実行 | main/master以外で開始時SHAとbaseline証跡を記録済み |
| Reproduce | 回帰テストを先に追加して実行 | テストが期待した理由で失敗（RED） |
| Fix | 根本原因への最小差分を実装 | 回帰テストが成功（GREEN_CONFIRMATION） |
| Verify | 関連test、typecheck/lint/build、必要ならUI preview | 必須コマンドが終了コード0 |
| 2軸Review | 正確性とセキュリティを独立評価 | blocking指摘が0件 |
| Report | 原因、差分、証跡、レビュー、残課題を報告 | 必須項目が存在 |

ファイル数は目安であり、リスクと波及範囲が小さいことを優先して適用を判断する。

### Triageの最小形式

```text
再現条件: <入力と操作>
現在値: <観測された誤動作>
期待値: <観測可能な正しい動作>
対象外: <変更しない範囲>
```

結果を変える不明点は推測せず、選択肢を提示して確認する。

main/master上では書き換えない。既存作業を保護し、事前許可された命名規則のfeatureブランチを作成する。個別承認が必要なリスク条件ではHuman Gateを先に通す。production code変更前に既存の関連testと該当するtypecheck/lint/buildを実行し、開始時Git SHA、コマンド、終了コード、結果要約をbaselineとして保存する。

## 4. TDDと最小修正

- REDはproduction codeを変更する前に実行し、追加テストが対象のバグによって失敗した証拠を残す。
- production codeは回帰テストのRED後にだけ変更する。RED前のproduction差分を禁止し、例外は実装しない。
- GREENは回帰テストを通す最小差分に限り、必要な場合だけ関連テストを追加する。
- REFACTORは現在の修正に必要な重複除去や命名改善だけにする。
- REFACTOR後に回帰・関連テストを再実行し、終了コード0の`POST_REFACTOR_GREEN`を確認してからVerifyとレビューへ進む。
- `PREPARATORY_REFACTOR`が必要なら実装せず、Development Harnessの別taskへ昇格する。
- 障害対応または本番操作が必要になった場合は、[Incident Response Harness](../../claude-code-incident-response-harness/README.md)へ昇格する。
- 根本原因を説明できない場合、既存挙動を固定するテストしか書けない場合、テストが最初から成功する場合はFixへ進まない。
- テスト削除、assertionの弱体化、例外握りつぶし、型・lint抑制を禁止する。

## 5. 検証証跡

最終回答に次を残す。

- RED: コマンド、非0の終了コード、期待した失敗理由
- GREEN: 同じ回帰テストのコマンド、終了コード0、結果要約
- Verify: 関連testと該当するtypecheck/lint/buildのコマンド、終了コード
- 変更ファイル一覧、根本原因、Code/Security Reviewの結果

baselineに既知の失敗がある場合は新規失敗と区別する。新規失敗は完了をブロックし、失敗を無視するオプションは使わない。

## 6. 権限とHooks

- permissionsはdeny優先とし、`.env*`、秘密鍵、credential、`.git`内部、本番操作を拒否する。
- `.env*`、OS Keychain、cloud credential、CI credentialを読み取らず、その値をコマンド、ログ、差分、最終回答へ出力しない。
- 書込みを対象コードとテストへ限定し、Network、依存追加、外部状態変更は既定で許可しない。
- `git push`、PR作成、migration、依存追加はHuman Gate Policyで分類する。有効なpre-authorization grantに束縛されたprivate repositoryのfeature branchへのpushとdraft PRだけをTier 1として扱い、merge、public repository、外部公開、migration、依存追加へ許可を継承しない。
- `rm`、`git reset --hard`、強制checkoutなど変更を失う破壊操作は既定でdenyし、ユーザーがその操作を明示的に要求した場合だけ個別承認を得る。
- 独自Hookは追加しない。既存Hookを使う場合は本体と呼出先を先に確認し、外部通信、secret参照、危険操作がないことを確かめる。
- 検証scriptは初回実行前に定義と呼出先をread-onlyで確認し、外部通信、secret参照、対象外の書込み先がないことを確かめる。
- Hookがなくても既存の検証コマンドを明示実行し、終了コードで判定する。
- shell scriptを追加・変更する場合はBash 3.2互換とし、`BASHPID`、連想配列、`declare -A`等を使わない。

## 7. UI変更

UI変更では通常のtest/typecheckに加え、preview MCPの`preview_screenshot` / `preview_eval`で次を確認する。

- 対象画面とバグの再現操作を確認し、修正後の主要状態をスクリーンショットに残す。
- 変更に関係するviewportで表示を確認する。
- browser consoleに新規errorがないことを確認する。

previewを利用できない場合は完了扱いにせず、未検証項目として報告する。

## 8. 2軸レビュー

| Reviewer | 確認事項 | 出力 |
|---|---|---|
| Code Reviewer | 根本原因、正確性、回帰、境界値、テスト品質、差分の最小性 | blocking / non-blocking、根拠のファイル位置 |
| Security Reviewer | 入力検証、認可、情報漏えい、injection、依存・権限の拡大 | blocking / non-blocking、攻撃条件と対策 |

レビュー開始前に対象commit SHA（未コミット差分ならbase SHA、diff hash、変更ファイル一覧）を固定する。Reviewerは固定対象だけをread-onlyで評価し、レビュー中の変更を禁止する。修正はImplementerへ返し、blocking修正後は対象を再固定して回帰テストと関連検証を再実行する。

## 9. 昇格条件と失敗上限

次のいずれかが判明したら変更を拡大せず、理由と選択肢をユーザーへ返す。

- 4ファイル以上を目安とする広い変更、複数コンポーネント、複数セッションが必要
- 原因または影響範囲が不明、要件やアーキテクチャの選択が必要
- テスト基盤の新設、DB migration、公開APIの破壊的変更、本番操作、高リスク権限が必要
- 大規模リファクタリング、複数責務・コンポーネント境界の再設計、またはバグ修正と分離すべき構造変更が必要
- 同じ原因への修正が2回連続で失敗
- レビュー修正後も同じblocking指摘が再発
- 認証、認可、秘密情報、暗号、その他のセキュリティ境界に変更が及ぶ

仕様化できる小規模変更はLightweight Feature Harness、広い調査・設計・状態管理が必要ならDevelopment Harnessへ昇格する。

ファイル数は目安にすぎず、リスクまたは波及範囲が大きい場合はファイル数にかかわらず即時昇格する。特に認証、認可、秘密情報、暗号、セキュリティ境界への変更はMicro Bugfix Harnessで続行しない。

## 10. PRレビューゲート

PR作成を依頼された場合だけ、CodeRabbitのレビューコメントをすべて確認・解消し、必要な検証を再実行してから完了とする。PR作成が依頼されていない場合は、Reportによるhandoffで完了できる。

作業中は一時checkpointにRED証跡、現在の仮説、レビュー結果、次actionだけを保存し、完了時に削除できる。compactionや再起動後に一意に復元できない場合は上位ハーネスへ昇格する。

## 11. 公式情報との対応

人間承認の共通基準は[Human Gate Policy](../../human-gate-policy.md)を正本とする。局所修正の編集やローカル検証を操作ごとに承認させず、外部反映、高リスク変更、昇格判断だけをリスク階層に従ってゲートする。本設計のセキュリティ境界に関する即時昇格は追加条件として適用する。

- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents): 必要な場合だけ複雑性を増やすため、単一オーケストレーターと短い固定フローを採用する。
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices): 探索、実装、検証を分離し、テストで明確なフィードバックを与える。
- [Configure permissions](https://code.claude.com/docs/en/permissions): allow/ask/denyを使い、deny優先の最小権限を適用する。
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide): Hookは決定論的規則に限定し、安全性を確認した既存Hookだけを利用する。
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html): 小さく自己完結した変更を、規模上限と昇格条件の根拠にする。

これらは設計根拠であり、対象プロジェクトの`CLAUDE.md`、テスト規約、permissionsを優先する。
