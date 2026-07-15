# Claude Code障害対応ハーネス設計の調査根拠

調査日: 2026-07-15

## 結論

既存のDevelopment、Lightweight Feature、Micro Bugfixは平時のコード変更を対象とし、進行中の本番障害に必要な指揮系統、single-writer、操作単位の承認、復旧観測、handoffを持たない。したがって、障害対応は独立パターンとする。

## 公式資料から採用した原則

- [Claude Code Hooks](https://code.claude.com/docs/en/hooks): `PreToolUse`はtool callをblockでき、`PostToolUse`等でライフサイクルを観測できる。一方、filterはbest-effortであり、hard allow/denyはpermission systemを使うべきと明記されるため、Hookは多層防御として扱う。
- [Claude Code Monitoring](https://code.claude.com/docs/en/monitoring-usage): OpenTelemetryによるmetrics/eventsのexportと組織の監視基盤への接続を、利用状況と操作相関の根拠にする。
- [Claude Code Sessions](https://code.claude.com/docs/en/sessions): sessionのresume、識別、履歴管理をhandoffと相関ID設計へ反映する。ただしtranscriptは秘密を含み得るため、無条件に監査記録へ複製しない。
- [Google Cloud: Manage incidents and problems](https://docs.cloud.google.com/architecture/framework/operational-excellence/manage-incidents-and-problems): incident managementの役割、軽減、communication、documenting、post-incident reviewを対応フェーズへ反映する。
- [AWS Builders' Library: Timeouts, retries, and backoff with jitter](https://aws.amazon.com/jp/builders-library/timeouts-retries-and-backoff-with-jitter/): timeout、再試行の自己増幅リスク、冪等性、capped backoff、jitterを再試行ポリシーへ反映する。
- [OpenTelemetry Logs specification](https://opentelemetry.io/docs/specs/otel/logs/): timestamp、trace/span correlation、resource contextを構造化記録の最低要件へ反映する。

## 設計判断

1. AIの既定役割はread-only Investigatorとし、本番変更は人間の明示承認を必須にする。
2. 本番変更はsingle-writerで直列化し、操作ごとに成功・停止・rollback条件を持たせる。
3. 再試行は冪等な一時障害だけに限定し、回数と総時間を制限する。
4. incident状態は特定vendorに依存しないYAML雛形とし、組織のticket/chat/observabilityへ参照で接続する。
5. セキュリティインシデントは証拠保全や法務要件が異なるため対象外とする。

