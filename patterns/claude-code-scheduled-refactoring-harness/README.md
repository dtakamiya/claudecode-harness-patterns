# Claude Code Scheduled Refactoring Harness

## 概要

毎日一回、ローカルのlaunchdから`claude -p`をヘッドレス起動し、振る舞いを変えないリファクタリングを1件ずつ進めるスケジュール実行ハーネスです。人間が`Ready for AI`へ遷移させたJiraチケットがあれば1件を実装し、自己レビュー、MR作成、MRレビュー、パイプライン成功の確認を経てレビュー依頼へ遷移します。実行可チケットが無い日は、対象プロジェクトを探索してリファクタリング候補を分析し、提案チケットを起票します。

チケットの取込み、lease、TicketSnapshot、outbox、writebackは[Jira Ticket Harness](../claude-code-jira-ticket-harness/README.md)を、実装手順は[Micro Bugfix Harness](../claude-code-micro-bugfix-harness/README.md)と[Lightweight Feature Harness](../claude-code-lightweight-feature-harness/README.md)を再利用します。本パターンが定めるのは、スケジュール起動、探索と提案起票、無人実行のための運用ガードです。

## 向いているケース

- 技術的負債を、毎日小さく継続的に返済したい。
- 人間のレビュー容量に合わせて、AIが作るMRの流量を制限したい。
- リファクタリング候補の発見から起票までを自動化し、着手判断だけを人間に残したい。
- Jira CloudとGitLab Self-Managed（private repository）のように、ホスティングが混在する環境で運用したい。

## 対象外

- 振る舞いを変える変更、機能追加、バグ修正
- 公開API、DB schema・migration、認証・認可、秘密情報の境界に触れる変更
- MRのmerge、release、デプロイ（Tier 2以上のため人間が行う）
- AIが起票したチケットを、人間の着手判断なしに実行すること
- `--dangerously-skip-permissions`による無制限実行

## 実行フロー

1. launchdが毎日決まった時刻にrun wrapperを起動する。wrapperがkill switch、run lock、ネットワーク到達性、WIP上限、予算を確認する。
2. 人間だけが遷移できるstatus `Ready for AI`のチケットをJQLで1件選び、leaseを取得する。
3. チケットがあれば`In Progress`へ遷移し、baselineのGREENを確認してcharacterization testを固定してからリファクタリングし、test・lint・typecheckを通す。RED必須の既存手順は使わず、振る舞い保存用の専用手順で進める。
4. 独立コンテキストのreviewerで自己レビューを行い、push、MR作成、MRへのレビューコメント投稿を行う。
5. 固定したcommit SHAでパイプライン成功を確認できたら、限定grantに基づいてチケットをIn Reviewへ遷移し、証跡をコメントする。失敗が上限に達したらblockedコメントを残して停止する。
6. チケットが無ければ、対象プロジェクトのホットスポットを探索・分析し、重複を照合したうえで`ai-proposed`ラベル付きの提案チケットを起票する。提案は人間が`Ready for AI`を付けるまで実行しない。
7. 実行結果、コスト、判定理由を実行記録へ残し、失敗時は通知する。

## 既存ハーネスとの関係

- [Jira Ticket Harness](../claude-code-jira-ticket-harness/README.md): TicketSnapshot、Definition of Ready、lease、revision、outbox、writebackの正本。本ハーネスは提案起票のwrite intentを追加する
- [Micro Bugfix Harness](../claude-code-micro-bugfix-harness/README.md)・[Lightweight Feature Harness](../claude-code-lightweight-feature-harness/README.md): 単一セッション、2軸レビュー、検証証跡、失敗上限の考え方。RED必須の手順は振る舞い保存と両立しないため、本ハーネスは専用手順を使う
- [Development Harness](../claude-code-development-harness/README.md): preparatory refactorでのcharacterization test固定。規模やリスクが超えたら本ハーネスでは実行せず、人間へ戻す
- [Human Gate Policy](../human-gate-policy.md): Tier判定と、提案起票・In Review遷移の限定grantの正本

## 最小導入手順

1. 対象repository、JQL、`Ready for AI`と`AI Blocked`のstatus、`ai-proposed`ラベル、遷移mapping、対象外パスをallowlistで定義する。`Ready for AI`への遷移はworkflowで人間のgroupに限定する。
2. Jira・GitLabのread credentialとwrite credentialを分け、Keychainへ保存する。AgentにはJiraのwrite credentialを渡さず、Jiraへの書込みはoutbox workerだけが行う。
3. run wrapperとlaunchd plistを用意し、最初はdry-runで提案と差分をローカルに出力するだけにする。
4. 1 repositoryで提案起票だけを有効にし、人間の採用率と却下理由を観察する。
5. 実装・MR作成を有効にし、最後にIn Review遷移の限定grantを有効にする。

## 設計書

- [Claude Code スケジュール実行リファクタリングハーネス設計書](docs/design.md)
