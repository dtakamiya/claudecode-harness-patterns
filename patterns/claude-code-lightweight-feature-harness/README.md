# Claude Code Lightweight Feature Harness

## 概要

3〜10ファイル程度の小規模な機能追加を、単一セッションで安全に完了するための軽量ハーネスです。`Intake → Explore → Micro Plan → TDD → Verify → 2軸Review → Handoff`だけを固定し、複数セッション用の状態管理や工程別の大量な成果物は持ちません。

## 向いているケース

- 受入条件を短い箇条書きで確定できる小規模機能
- 変更範囲が一つのコンポーネント内に収まり、概ね3〜10ファイルで完了する作業
- 既存アーキテクチャとテスト方式をそのまま利用できる作業
- 一つのfeatureブランチ、単一セッションで実装と検証を終えられる作業

## 向いていないケース

- 要件定義、アーキテクチャ判断、複数コンポーネントの調整が必要
- DB/APIの破壊的変更、本番操作、高リスクな権限が必要
- 10ファイルを超える見込み、複数セッション、複数担当者への引継ぎが必要
- 障害対応や、原因と影響範囲がまだ特定できていない難解なバグ

該当する場合は[Claude Code Development Harness](../claude-code-development-harness/README.md)へ昇格します。

顧客資産・取引・会計・規制遵守・金融意思決定に影響する金融ドメインロジックに触れる変更は、規模にかかわらずDevelopment Harnessへ即時昇格し、独立したAdversarial Reviewerの審査を必須とします。非金融の軽微変更だけはDevelopment HarnessのAdversarial Reviewerが承認した理由付き除外判定を利用できます。

## 実行フロー

1. **Intake:** 目的、受入条件、対象外、想定変更範囲を短く確定する。不明点は選択肢でユーザーへ確認する。
2. **Explore:** 既存実装、テスト、規約、検証コマンドをread-onlyで調査し、featureブランチであることを確認する。
3. **Micro Plan:** 変更対象、テスト観点、検証コマンドを5項目以内で提示する。範囲超過なら実装前に昇格する。
4. **TDD:** 受入条件を表す失敗テスト（RED）を先に追加し、最小実装（GREEN）、必要最小限の整理（REFACTOR）を行う。
5. **Verify:** 関連テスト、typecheck/lint/build、必要ならUI確認を実行し、コマンドと終了コードを記録する。
6. **2軸Review:** `code-reviewer`が正確性・回帰を、`security-reviewer`が入力・権限・秘密情報を独立に確認する。blocking指摘と、スコープ内で解消できるnon-blocking指摘を修正して再検証する。
7. **Handoff:** 変更概要、変更ファイル、検証コマンドと終了コード、レビュー結果、残課題を最終回答にまとめる。

## 最小成果物

- production code
- 受入条件を検証するテスト
- 最終回答の検証証跡と変更ファイル一覧

`progress.yaml`、context manifest、工程別handoff文書、常設のPlanner/Generator/Evaluatorは作りません。判断を残す必要が生じた場合だけ、既存のADRやissueを更新します。

## 適用判定

| 判断軸 | Lightweight Feature Harness | Development Harness |
|---|---|---|
| 変更規模 | 概ね3〜10ファイル、局所的 | 10ファイル超、複数コンポーネント |
| 要件 | 短い受入条件が確定済み | 要件定義・設計判断が必要 |
| 実行期間 | 単一セッション | 複数セッション・長時間 |
| 状態管理 | Git差分と最終回答 | progress、handoff、context manifest |
| Agent | 探索、実装、2軸レビューだけ | 工程別Planner/Generator/Evaluator |
| リスク | 局所的・可逆 | 破壊的変更、高権限、本番影響 |

ファイル数は目安であり、リスクと波及範囲を優先して判定します。

## 設計書

- [軽量機能追加ハーネス設計書](docs/design.md)

## 参考資料

- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents) — 必要になるまで複雑性を増やさず、最も単純な構成から始める原則
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices) — 探索、計画、実装、検証の実践
- [Configure permissions](https://code.claude.com/docs/en/permissions) — allow/ask/denyと最小権限
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide) — 決定論的な自動化とHookの安全な利用
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html) — 小さく自己完結した変更がレビュー品質と不具合発見を改善するという実務上の根拠
