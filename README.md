# Claude Code Harness Patterns

Claude Codeを利用した開発ハーネスの再利用可能な設計パターンをまとめるリポジトリです。

## Patterns

- [Claude Code Development Harness](patterns/claude-code-development-harness/README.md) — 要件定義から実装完了までを、成果物、独立レビュー、品質ゲート、状態管理で制御するパターン
- [Claude Code Lightweight Feature Harness](patterns/claude-code-lightweight-feature-harness/README.md) — 3〜10ファイル程度の小規模機能追加を、単一セッションのTDDと最小限のレビューで進めるパターン
- [Claude Code Micro Bugfix Harness](patterns/claude-code-micro-bugfix-harness/README.md) — 再現条件が明確な局所バグを、回帰テストと最小修正で直す最軽量パターン

## Research

- [Claude Code 開発ハーネスの再利用可能な設計パターン調査](research/claude-code-development-harness-patterns.md) — 公式ドキュメント中心の13パターン網羅調査
- [コミュニティ実装事例からの再利用可能パターン調査](research/community-harness-implementations-2026.md) — Ralph Wiggum、GAN型Evaluator、Agent Teams、Meta-Harnessなど実際のOSS実装からの調査
