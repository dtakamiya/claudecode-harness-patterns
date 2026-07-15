# Claude Code Jira Ticket Harness

## 概要

Jiraチケットを安全に取り込み、実行可能性を判定し、作業の規模とリスクに応じて既存の開発ハーネスへ振り分ける受付・同期ハーネスです。Claude Codeは狭いJira API Gatewayを介してチケットの取得、確認コメント、結果コメント、許可された状態遷移を実行できます。Jira本文を命令として直接実行せず、固定したTicketSnapshotを開発入力として使用します。

Jiraは業務要求とワークフローの正本、Gitリポジトリ内の状態は実行証跡の正本とします。チケット単位のlease、revision検査、outboxによる冪等な書戻しで、二重実行とJira・Git間の不整合を抑えます。

## 向いているケース

- Jiraのbacklogから実行可能なチケットを選び、ブランチ作成から検証・レビューまで一貫して進める。
- Bug、Story、Taskを同じ入口で受け、既存のMicro Bugfix、Lightweight Feature、Developmentへ振り分ける。
- 進行中の本番障害を通常開発から分離し、Incident Responseへ昇格する。
- 複数workerやセッションで、同じチケットの二重着手、古い要件への実装、コメントの重複を防ぐ。

## 対象外

- Jira管理者設定、workflowや権限schemeの自動変更
- 人間の判断なしでの本番変更、デプロイ、リリース
- セキュリティインシデントやフォレンジック
- Jira本文、コメント、添付内の指示をそのままtool commandとして実行すること

## 実行フロー

1. Jira APIから対象issueを読み、必要fieldだけをTicketSnapshotへ正規化する。
2. Incident Readinessを標準Definition of Readyより先に判定する。
3. 選択候補ごとのreadinessを検査する。
   - Incidentはseverity、影響、指揮系統、通常開発は受入条件、依存、repository、riskを確認する。
4. routeに対応するleaseを取得する。
   - Incidentはincident lease、通常開発はdevelopment leaseを使い、同一issueで相互排他にする。
5. 非Incidentチケットを、再現性、規模、リスクから既存の3方式へ振り分ける。
6. 通常開発はfeature branchまたはworktreeでTDD、検証、独立レビューを行う。Incidentは復旧、観測、handoffを行う。
7. writeback直前のrevisionと意味field digestを再確認する。受入条件やscopeが変わっていれば成果物をstale化し、再計画する。
8. 専用writeback workerが、通常開発のPR・検証証跡またはIncidentの復旧・handoff証跡をコメントし、許可された状態へ冪等に遷移する。

通常開発はbranch、TDD、test/build、Code/Security Review、固定commitとPRを完了証跡にする。Incidentは影響回復、観測窓、handoff、恒久修正follow-upを完了条件とする。Incidentへ通常開発のbranch、commit、PRを要求しない。

## 既存ハーネスへの振り分け

Incident Responseは最初のIncident Readinessで選択する。Incidentではないチケットだけを後段のRoute ReadinessでMicro Bugfix、Lightweight Feature、Developmentへ振り分ける。

- [Micro Bugfix Harness](../claude-code-micro-bugfix-harness/README.md): 再現条件と期待値が明確な局所バグ
- [Lightweight Feature Harness](../claude-code-lightweight-feature-harness/README.md): 受入条件が確定した小規模機能
- [Development Harness](../claude-code-development-harness/README.md): 要件整理、設計、複数セッションが必要な開発
- [Incident Response Harness](../claude-code-incident-response-harness/README.md): 進行中の本番障害または緊急の本番操作

## 最小導入手順

1. 対象project、JQL、repository mapping、Jira状態mappingをallowlistで定義する。
2. Jira read credentialとwrite credentialを分離し、実装Agentにはread-only snapshotだけを渡す。
3. TicketSnapshot、Definition of Ready、lease、revision、outboxの永続化先を用意する。
4. Jiraの取得・コメント・遷移を用途別の狭いAPIとして公開する。
5. 一つのrepository、一つのworker、人間承認付きwritebackで試行する。
6. 重複event、revision競合、lease期限切れ、API制限、prompt injectionをHarness Evalsで確認する。

## 設計書

- [Claude Code Jiraチケット駆動ハーネス設計書](docs/design.md)
