# Claude Code Micro Bugfix Harness

## 概要

再現条件と期待値が明確な局所バグを、単一セッションで直す最軽量ハーネスです。`Triage → Reproduce → Fix → Verify → 2軸Review → Report`だけを固定し、回帰テストを先に失敗させてから根本原因への最小差分を実装します。

## 向いているケース

- 不具合の入力、現在の結果、期待する結果が明確
- 一つのコンポーネント内で、概ね1〜3ファイルの変更に収まる
- 既存のテスト方式と検証コマンドを利用できる
- 依存追加、DB migration、公開API変更、権限変更を伴わない

ファイル数は目安であり、リスクと波及範囲を優先して適用を判断します。

## 向いていないケース

- 原因または影響範囲が不明な難解なバグ、障害対応、本番操作
- 要件やアーキテクチャの判断、複数コンポーネントの変更が必要
- テスト基盤の新設、破壊的変更、高リスクな権限が必要
- 認証、認可、秘密情報、暗号、その他のセキュリティ境界に変更が及ぶ
- 4ファイル以上を目安とする広い変更、または複数セッションになる見込み

小規模機能相当なら[Lightweight Feature Harness](../claude-code-lightweight-feature-harness/README.md)、原因調査や広い変更が必要なら[Development Harness](../claude-code-development-harness/README.md)へ昇格します。

顧客資産・取引・会計・規制遵守・金融意思決定に影響する金融ドメインロジックに触れる修正は、局所的でもDevelopment Harnessへ即時昇格し、独立したAdversarial Reviewerの審査を必須とします。非金融の軽微変更だけはDevelopment HarnessのAdversarial Reviewerが承認した理由付き除外判定を利用できます。

## 実行フロー

1. **Triage:** バグの再現条件、現在値、期待値、対象外を確定し、規約、類似実装、テスト、検証コマンド、featureブランチをread-onlyで確認する。
2. **Reproduce:** 不具合を再現する回帰テストを先に追加し、期待した理由で失敗することを確認する（RED）。
3. **Fix:** 根本原因だけを修正する最小差分を実装し、回帰テストを成功させる（GREEN）。必要な整理だけを行う。
4. **Verify:** 回帰テスト、関連テスト、該当するtypecheck/lint/buildを実行し、コマンドと終了コードを記録する。UI変更は`preview_screenshot` / `preview_eval`で表示・操作・console errorを確認する。
5. **2軸Review:** `code-reviewer`が正確性と回帰を、`security-reviewer`が脆弱性と権限拡大を独立に確認する。blocking指摘を修正して再検証する。
6. **Report:** 根本原因、変更ファイル、RED/GREENを含む検証証跡、レビュー結果、残課題を最終回答にまとめる。

PR作成を依頼された場合だけ、CodeRabbitのレビューコメントをすべて解消してから完了とします。PR作成が依頼されていない場合は、Reportによるhandoffで完了できます。

## 最小成果物

- 不具合を再現する回帰テスト
- 根本原因を直すproduction code
- 最終回答の検証証跡

独自の状態ファイル、計画書、handoff文書、常設Agent、Hookは作りません。

## 設計書

- [マイクロバグ修正ハーネス設計書](docs/design.md)

## 参考資料

- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents) — 必要になるまで複雑性を増やさず、単純な構成から始める原則
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices) — 探索、計画、実装、検証と明確な検証手段
- [Configure permissions](https://code.claude.com/docs/en/permissions) — allow/ask/denyによる最小権限
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide) — 決定論的な自動化とHookの安全な利用
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html) — 小さく自己完結した変更がレビューを容易にする根拠
