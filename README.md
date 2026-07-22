# Claude Code Harness Patterns

Claude Codeを利用した開発ハーネスの再利用可能な設計パターンをまとめるリポジトリです。

## Patterns

- [Claude Code Development Harness](patterns/claude-code-development-harness/README.md) — 要件定義から実装完了までを、成果物、独立レビュー、品質ゲート、状態管理で制御するパターン
- [Claude Code Jira Ticket Harness](patterns/claude-code-jira-ticket-harness/README.md) — Jiraチケットを安全に取り込み、適切な開発ハーネスへ振り分け、証跡をJiraへ冪等に書き戻すパターン
- [Claude Code Lightweight Feature Harness](patterns/claude-code-lightweight-feature-harness/README.md) — 3〜10ファイル程度の小規模機能追加を、単一セッションのTDDと最小限のレビューで進めるパターン
- [Claude Code Micro Bugfix Harness](patterns/claude-code-micro-bugfix-harness/README.md) — 再現条件が明確な局所バグを、回帰テストと最小修正で直す最軽量パターン
- [Claude Code Incident Response Harness](patterns/claude-code-incident-response-harness/README.md) — 本番サービス障害を、明示承認、single-writer、構造化記録、復旧検証で安全に収束させるパターン
- [Human Gate Policy](patterns/human-gate-policy.md) — 全ハーネス共通のリスク階層、承認対象、Decision Packet、失効、役割分離を定めるポリシー
- [Change Intent Record](patterns/change-intent-record.md) — AI支援変更の目的、設計上の理由、制約、検証可能なリンクを短く残す共通規約

## Research

- [Claude Code 開発ハーネスの再利用可能な設計パターン調査](research/claude-code-development-harness-patterns.md) — 公式ドキュメント中心の13パターン網羅調査
- [コミュニティ実装事例からの再利用可能パターン調査](research/community-harness-implementations-2026.md) — Ralph Wiggum、GAN型Evaluator、Agent Teams、Meta-Harnessなど実際のOSS実装からの調査
- [Claude Code障害対応ハーネス設計の調査根拠](research/claude-code-incident-response-harness-pattern.md) — 公式資料から承認、single-writer、再試行、監査、handoffを導出した調査
- [AI生成コードの設計意図トレーサビリティ調査](research/ai-generated-code-design-intent-traceability.md) — 長期保守上のリスク、限定条件、反証、実務上の対策を一次資料から整理
- [Claude Code BDD開発ハーネス設計の調査](research/claude-code-bdd-development-harness-pattern.md) — Gherkin/ATDDをエージェントで駆動する設計要素と失敗モード、独立パターン化の可否
