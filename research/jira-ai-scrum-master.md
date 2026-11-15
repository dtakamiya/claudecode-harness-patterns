# Jira REST API で AI スクラムマスターを運用する調査レポート

調査日: 2026-10-03 / 対象: Jira Cloud REST API + Claude（Atlassian Remote MCP は比較のみ）

## 結論

- スクラムマスター業務のうち、**読み取り・分析・提案**は AI に任せやすい。Jira への**書き込みは承認制を基本**にする。
  - 既存の `patterns/human-gate-policy.md` §2 で、Jira 遷移・外部 writeback は Tier 2（一名の事前承認）と定義されている。
  - 当初の希望「ほぼ自律」は、この方針と衝突する。そのため将来課題とし、拡大条件だけを「自律化の条件（将来課題）」の節に残す。
- 構成は「Read ボット + Write ボット（サービスアカウント分離）→ 狭い Gateway → 承認付き Outbox → 監査ログ」にする。
  - AI に汎用 REST クライアントは渡さない。
  - 認可は LLM ではなく、トークンのスコープと Jira のプロジェクトロールで強制する。
- 認証は**サービスアカウント + スコープ付き API トークン**が第一候補。
  - 削除スコープを付けない。古典スコープ `write:jira-work` は削除も含むため、粒度スコープを使う。
  - API トークン経由の通信は新レート制限（ポイント制）の対象外で、従来のバースト制限のみが適用される。
- **ベロシティ・バーンダウンの公式 API は存在しない**。`board/{id}/sprint` と `sprint/{id}/issue` で自前計算する。
  - 非公式の greenhopper エンドポイントは、いつ消えてもおかしくないため使わない。
- 受入条件・見積り・粒度の判定は JQL では完結しない。JQL は候補の絞り込みに使い、判定は AI が本文を読んで行う。

## 業務マッピング

| 業務 | 取得データ | AI の出力 | 書き込み | Tier |
|---|---|---|---|---|
| イベント運営支援（デイリー／計画／レビュー／レトロ） | 稼働スプリントの更新、直近 24h の遷移、changelog | 議題案、要約、前回アクションの確認 | なし（Slack 等へ出すだけ） | 0 |
| チケット品質管理 | 説明、受入条件、見積り、リンク、ラベル | 不足項目の指摘、粒度分割案 | 指摘コメント（承認後）、ラベル付与 | 2 |
| 進捗・阻害要因の検知 | 滞留日数、flagged、`is blocked by` リンク、期限 | 滞留・ブロッカー一覧と通知文案 | コメント（承認後） | 0 → 2 |
| メトリクス／レポート | 完了スプリントの課題、遷移時刻 | ベロシティ、サイクルタイム、レビュー資料 | なし | 0 |
| スプリント操作（開始・完了・課題移動） | `board/{id}/sprint`、`sprint/{id}/issue` | 操作案（変更計画 JSON） | **常時承認** | 2 |

- 「Tier」は `patterns/human-gate-policy.md` §2 の表（:17-25）に対応させた。
- 操作を細かく分けて Tier を下げることは、同ポリシー §2 で禁止されている。

## アーキテクチャ

```
Jira Cloud ─(Read 用サービスアカウント)→ Read Gateway ─→ AI（分析・提案）
                                                        │ 変更計画(JSON)
                                                        ▼
                                              承認（人）→ Outbox → Write Gateway
                                                                  └(Write 用サービスアカウント)→ Jira
                                              監査ログ（変更前後・理由・承認者・リクエスト ID）
```

- Read と Write は credential を分ける。既存設計の `patterns/claude-code-jira-ticket-harness/docs/design.md` §3.1（Gateway）と §8.1（credential 分離）、`docs/claude_code_em_ai_secretary_harness_design_v1.0.md` §23（Outbox）が再利用できる。
- JQL は管理者定義の allowlist だけを使う方針が既存設計にある（jira-ticket-harness `design.md` §3.1）。AI に任意 JQL は書かせない。
- 実行直前に現在値を読み直し、承認時の期待状態と違えば再承認にする（既存 Human Gate Policy §4 と同じ考え方）。

## API 調査

### エンドポイント

- Agile API（`/rest/agile/1.0`）
  - スプリント: `POST /sprint`（作成）、`POST|PUT /sprint/{id}`（更新）。状態遷移は future → active → closed のみ。
  - 開始には startDate と endDate が必要。完了時の completeDate は自動設定で、手動では編集できない。
  - 課題: `GET /sprint/{id}/issue`、`POST /sprint/{id}/issue`（移動・並び替え）。
  - ボード: `GET /board/{id}/{backlog|issue|sprint|epic|configuration}`。`startAt` と `maxResults` でページングする。
- Platform API v3
  - 検索は新しい `GET|POST /rest/api/3/search/jql`。ページングは `nextPageToken` で、総件数は返らない（二次情報）。
  - 検索は結果整合性があり、更新直後は古い値が返ることがある。`reconcileIssues`（最大 50 件）または課題の直接取得で確認する。
  - changelog の一括取得は `POST /rest/api/3/changelog/bulkfetch`（Experimental、最大 1000 課題）。
  - ステータス変更は `PUT /issue` では行えず、transitions エンドポイントを使う。
- 出典: [Sprint](https://developer.atlassian.com/cloud/jira/software/rest/api-group-sprint/)、[Board](https://developer.atlassian.com/cloud/jira/software/rest/api-group-board/)、[Search and reconcile](https://developer.atlassian.com/cloud/jira/platform/search-and-reconcile/)

### 認証とスコープ（取得日 2026-10-03、本文で確認）

- サービスアカウント（無料は組織あたり 5 件、超過は Atlassian Guard）。UI ログインはできない。
- API トークンの有効期限は既定 1 年（1〜365 日で設定）。作成後にスコープは変更できない。
- リクエスト先は `https://api.atlassian.com/ex/jira/{cloudId}/rest/api/3/...` の形式。
- 出典: [Manage API tokens for service accounts](https://support.atlassian.com/user-management/docs/manage-api-tokens-for-service-accounts/)
- 推奨スコープ（粒度スコープ）
  - Read ボット: `read:issue:jira`、`read:comment:jira`、`read:issue.changelog:jira`、`read:sprint:jira-software`、ボード読み取り
  - Write ボット: 段階に応じて最小限だけ付与する。
    - 段階 1（コメント）: `write:comment:jira`
    - 段階 2（ラベル・フィールド更新）: `write:issue:jira`
    - 段階 3（スプリント操作）: `write:sprint:jira-software`
    - 段階 3（ステータス遷移）: 遷移の実行に必要な粒度スコープは、公式のスコープ一覧に明記がなく**未確認**。一覧にあるのは閲覧用の `read:issue.transition:jira` のみで、実機で確認する。
  - 参考: 古典スコープ `write:jira-work` は課題の削除も含む。
  - `delete:*` は付けない。
- スコープと Jira 側の権限は両方が効く。ボットは対象プロジェクトの限定ロールにだけ入れる。
- OAuth 2.0 3LO は動作がユーザーに紐づき、リフレッシュトークンの管理が要るため、無人運用では第二候補。

### Webhook とポーリング（取得日 2026-10-03、本文で確認）

- 動的に登録した webhook は作成・更新から 30 日で失効する。配信失敗は最大 5 回、5〜15 分間隔で再試行される。
- `X-Atlassian-Webhook-Identifier` は再試行でも同じ値になるため、重複排除に使える。
- 管理 UI の webhook は `X-Hub-Signature`（HMAC）で署名を検証できる。
- JQL フィルタで使えるのは `issueKey`、`project`、`issuetype`、`status`、`priority`、`assignee`、`reporter` など。**sprint イベントでは JQL は評価されない。**
- 使い分け（設計提案）: 即時性が要るもの（スプリント開始・完了）は webhook、デイリー要約と滞留検知は定時ポーリング。取りこぼし対策に、定期 JQL と突き合わせる。
- サービスアカウントで webhook を登録できるかは**未確認**。できなければポーリング主体にする。
- 出典: [Jira webhooks](https://developer.atlassian.com/cloud/jira/platform/webhooks/)

### レート制限（取得日 2026-10-03、本文で確認）

- ポイント制クォータは Forge、Connect、OAuth 2.0 (3LO) アプリが対象で、2026-03-02 から強制される。
  - 「API token-based traffic is not affected by this change, and will continue to be governed by existing burst rate limits.」
- バースト制限は、GET 100、POST 100、PUT 50、DELETE 50 回/秒。
- 課題単位の書き込みは 2 秒で 20 回、または 30 秒で 100 回。
- 超過時は HTTP 429。`Retry-After` と `RateLimit-Reason` ヘッダーで種類を判別できる。
  - `jira-burst-based`、`jira-per-issue-on-write`、`jira-quota-tenant-based`、`jira-quota-global-based`
- 指数バックオフ + ジッターで再試行する。
- 出典: [Rate limiting](https://developer.atlassian.com/cloud/jira/platform/rate-limiting/)

### JQL 例（設計例。フィールド名は環境依存）

- 直近 24 時間の更新: `sprint in openSprints() AND updated >= -24h ORDER BY updated DESC`
- 昨日からのステータス変化: `sprint in openSprints() AND status CHANGED AFTER startOfDay("-1d")`
- 滞留: `sprint in openSprints() AND status = "In Progress" AND updated <= -3d`
- ブロッカー: `sprint in openSprints() AND (flagged is not EMPTY OR issueLinkType = "is blocked by")`
- 見積りなし: `sprint in openSprints() AND "Story Points" is EMPTY`
- `CHANGED` が使える項目は assignee、fixVersion、priority、reporter、resolution、status のみ。
- 出典: [JQL operators](https://support.atlassian.com/jira-software-cloud/docs/jql-operators/)、[JQL functions](https://support.atlassian.com/jira-software-cloud/docs/jql-functions/)

### メトリクスの自前計算

- ベロシティ: `closedSprints()` の課題から、Done の Story Points を合計する。
- サイクルタイム: changelog の「In Progress → Done」の遷移時刻の差を取る。
- バーンダウン: スプリント期間中の changelog から再構成する。スコープ変更の追跡には限界がある。
- 公式 API はないため、グラフ値は Jira 標準のレポートと突き合わせて検算する。

### Atlassian Remote MCP との比較（最小限）

- MCP は導入が早く、削除系と管理系ツールが既定で無効。`manageJiraSprint` でスプリント操作もできる。
- REST 直は、スコープを粒度スコープまで絞れる。承認・ログ層を自前で差し込め、changelog の一括取得などにも対応しやすい。
- 今回は REST 直を採用する。MCP のレート制限の数値は公式で確認できていない。

## ガードレール

- 書き込み段階（承認制）

| 段階 | 内容 | Tier |
|---|---|---|
| 0 | 読み取りのみ。要約・レポートを出力 | 0 |
| 1 | ボット名義のコメント・ラベル（承認後） | 2 |
| 2 | フィールド更新（見積り・説明） | 2 |
| 3 | ステータス遷移、スプリント開始・完了 | 2（常時承認） |
| - | 削除 | 禁止（スコープを付けない） |

- 承認フロー: AI は「変更計画（JSON）」だけを出力し、承認後に Write Gateway が実行する。
- 冪等性: Jira REST に Idempotency-Key 相当は確認できなかった。次を自前で実装する。
  - 実行前に現在値を読む。期待状態と同じなら何もしない。
  - 操作 ID をコメントに埋め込んで、重複投稿を防ぐ。
  - webhook は `X-Atlassian-Webhook-Identifier` で重複排除する。
- ロールバック: 変更前の値を保存し、changelog を根拠に PUT で戻す。スプリント完了・課題移動・通知送信は戻しにくいため、常に承認制にする。
- 監査ログ: Jira 側の操作はボット名義で課題の履歴に残る。AI 側でも「変更前後の値・理由・承認者・リクエスト ID」を残す。Jira の監査レコード API は設定変更が中心とみられ、課題の履歴の代わりにはならない（未確認）。
- プロンプトインジェクション: 課題のタイトル・説明・コメントは第三者が書ける入力。本文は不信頼データとして扱い、権限はスコープで固定する（既存 jira-ticket-harness `design.md` §2、§8.2）。
- 考え方の出典: [OWASP LLM06 Excessive Agency](https://owasp.org/www-project-top-10-for-large-language-model-applications/2_0_vulns/LLM06_ExcessiveAgency.html)、[Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

## 自律化の条件（将来課題）

- 現時点では行わない。行う場合も、段階 1（コメント・ラベル）から順に、測定してから広げる。
- 既存の jira-ticket-harness `design.md` §13 は、誤遷移率・重複コメント率・手動復旧成功率を測定してから自動遷移を有効にする方針。これに合わせる。
- 段階 3（遷移・スプリント操作）の自律化は、独立した評価で誤操作がないことを確認するまで見送る。

## 未確認・限界

- `search/jql` の `maxResults` 上限と `fields` の既定値は、公式ページの取得が途中で切れて**確認できていない**。
- ステータス遷移の実行に必要な粒度スコープ（公式一覧に明記なし）。
- ボード系エンドポイントの記述は、調査エージェント経由で原文を再確認していない。
- サービスアカウントで webhook を登録できるか。
- スプリント完了時に未完了課題がどう扱われるか（公式に明記が見つからない）。
- `POST /sprint/{id}/issue` で一度に動かせる課題数の上限。
- 受入条件と見積りが専用フィールドか、description 内かは環境依存。
- 実環境で、サービスアカウント + スコープ付きトークンが `/rest/agile/1.0` と `search/jql` を通せるかの実機確認がまだ。
- 単一課題の changelog 取得 API の公式ページは未確認。
- bulkfetch は Experimental、changelog はスコープ変更の追跡に限界がある。
- Atlassian の API 利用規約上の制約は調べていない。
- 「design.md §3」は複数ファイルで別内容のため、引用時はファイル名を併記した。

## 参照

- Atlassian 公式（取得日 2026-10-03）
  - [Rate limiting](https://developer.atlassian.com/cloud/jira/platform/rate-limiting/)（本文で確認）
  - [Manage API tokens for service accounts](https://support.atlassian.com/user-management/docs/manage-api-tokens-for-service-accounts/)（本文で確認）
  - [Jira webhooks](https://developer.atlassian.com/cloud/jira/platform/webhooks/)（本文で確認）
  - [Sprint](https://developer.atlassian.com/cloud/jira/software/rest/api-group-sprint/)（本文で確認: 状態遷移、startDate/endDate、completeDate の自動設定）
  - [Search and reconcile](https://developer.atlassian.com/cloud/jira/platform/search-and-reconcile/)（本文で確認: 最大 50 件、結果整合性）
  - [Scopes](https://developer.atlassian.com/cloud/jira/platform/scopes-for-oauth-2-3LO-and-forge-apps/)（本文で確認: `write:issue:jira`、`write:comment:jira`、`write:jira-work` に削除を含む）
  - [Board](https://developer.atlassian.com/cloud/jira/software/rest/api-group-board/)（調査エージェント経由。原文は再確認していない）
  - [Rovo MCP supported tools](https://developer.atlassian.com/cloud/rovo-mcp/guides/supported-tools/)（同上）
- コミュニティ（二次情報）
  - [Velocity chart の代替 API](https://community.atlassian.com/forums/Jira-questions/Alternative-API-for-Velocity-Chart-velocityStatEntries-in-Jira/qaq-p/3116292)
  - [search/jql の nextPageToken](https://community.developer.atlassian.com/t/jira-cloud-rest-api-v3-search-jql-slower-fetching-with-nextpagetoken-no-totalissues-any-workarounds/90176)
  - [Bulk fetch changelogs](https://community.developer.atlassian.com/t/bulk-fetch-changelogs-experimental-api/87240)
- リポジトリ内
  - `patterns/human-gate-policy.md` §2、§3、§4
  - `patterns/claude-code-jira-ticket-harness/docs/design.md` §2、§3.1、§8、§13
  - `docs/claude_code_em_ai_secretary_harness_design_v1.0.md` §18、§23
