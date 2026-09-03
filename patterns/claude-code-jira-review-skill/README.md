# Claude Code Jira Incident Review Skill

## 概要

貼り付けた Jira チケット（本番インシデント / 開発時の障害）を、一定の品質基準で
レビューする単独動作スキルの設計パターンです。既存の[Claude Code Review Skill](../claude-code-review-skill/README.md)が
**コードの差分**を対象にするのに対し、本スキルは**チケットの記述と、それが露呈させる
品質プロセスの穴**を対象にします。両者は併存します。

中核の主張: **インシデントチケットのレビューは「文章が整っているか」ではなく、
「この障害を監視・テストでなぜ捕らえられなかったか」「再発防止策が品質プロセスに
組み込まれているか」で決まる。**

このスキルが検査するのは「根本原因の**記述が深掘りの構造を備えているか**」まで。
根本原因が事実として正しいか、対策が技術的に有効かは、コード・メトリクス・設計の確認が
必要でスコープ外です（「要確認」として PIR の議題に回す）。

## 向いているケース

- PIR（ポストインシデントレビュー）会議の前に、**作成者/対応チームが**チケットの穴を洗い出したい
- インシデント / バグチケットをクローズする前のセルフチェック
- ポストモーテムの作成ガイドラインの土台にしたい（個票の採点ではなく）
- 再発防止策が「周知する」「注意する」で流れていないかを機械的に検査したい

## 向いていないケース

- **担当者・対応者の評価や査定**（本スキルの出力はプロセス改善のためのもので、人事評価に転用してはならない）
- 実際の本番対応の進行管理（[Incident Response Harness](../claude-code-incident-response-harness/README.md)へ）
- コード差分のレビュー（[Claude Code Review Skill](../claude-code-review-skill/README.md)へ）
- Jira から自動でチケットを取得したい（本スキルは貼り付け前提。MCP 連携は範囲外）
- チケットの自動修正（本スキルは設計上チケットを編集しない。出力は追記文案まで）

## 設計の要点

### 1. プロセスの穴を最優先に見る

Webリサーチ（Atlassian Postmortems handbook、incident.io の SRE ベストプラクティス）が
一致して指摘するのは、**動くポストモーテムと形骸化したポストモーテムを分けるのは
アクションアイテムの実効性**という点です。本スキルは QA/QC 観点（`reference/qa-process.md`）を
最重要ステップに置き、次を満たさなければ記述が整っていてもブロッカーとします。

- 障害の性質（実装バグ / 設計欠陥 / キャパシティ / 外部依存 / 組織）で分岐し、実装バグなら
  すり抜けた**テストのレイヤ**（unit / integration / E2E / 型 / lint / staging / canary）が
  特定されている
- 再発防止策が品質プロセスへの**恒久的な組み込み**（テスト追加・アラート追加・CI 追加・
  ガードレール追加）である
- 特定された最深の contributing factor に、対応するアクションアイテムが紐付いている
- 「同じ人が退職しても残って機能するか」に耐える

**コードレビューはすり抜け工程の候補に含めません。** コードレビューの主目的は保守性・
知識移転であって欠陥検出ではなく（Microsoft Research "Code Reviews Do Not Find Bugs":
コメントの約 15% しか欠陥に関係しない）、レビューに欠陥検出を期待する設計自体が誤りだ
からです。TDD / shift-left の前提では、欠陥検出はテストの責務。「レビューで見落とした」と
書かれたチケットは、それ自体を要改善とし「この不具合を捕らえるテストが無かった」への
書き換えを促します。

### 2. 網羅方針（チェックリスト全項目に合否）

[Claude Code Review Skill](../claude-code-review-skill/README.md) が precision 優先で
「書けない指摘は出さない」のに対し、本スキルは**チェックリスト型**として全項目に
`合格 / 要改善 / 該当なし` を付けます。チケットの構造的な欠落（フィールド・タイムライン・
影響定量値）は「記載なし = 要改善」で機械的に拾えるため、網羅が有効に働きます。

### 3. ただし非難と過剰指摘は構造で抑える

網羅方針の代償（粗探し・言いがかり・萎縮）を次で抑えます。

- **blameless 指摘とアクションアイテムの不備指摘は、本文の該当箇所を引用できるものに限る**（推測で非難扱いしない。引用に実名は含めない）
- 埋まっている項目には難癖を付けず「合格」とする。「要改善」は記載の欠落・曖昧さに限定する
- 出力冒頭に免責文（改善提案であり個人評価材料ではない）、「良い点」を先に列挙、
  「要改善」を内訳表示（記載追加で解消 / 内容の見直し）

根拠は blameless postmortem の原則（Atlassian / PagerDuty / Google SRE Book / Allspaw /
Hebert）です。「エンジニアがデプロイし忘れた」→ 再教育、という無効な対策を生む表現を、
`reference/blameless-language.md` の言い換えテンプレートでシステム主語へ書き直させます。
**ただし言い換えただけで終わらせません** —— 言い換え先（システム / プロセス）が根本原因
分析で掘り下げられているか（"second story"）まで見ます。実名でのタイムライン記録・対応者の
実名記載それ自体は非難ではなく、指摘しません。

### 4. 種別で分岐する

インシデント（本番・顧客影響・SEV 表記）とバグ（開発中・再現手順が主）で必要な
チェックリストが違うため、Step 1 で種別を判定し**片方だけ**を読みます（`reference/` の
先読みをしない）。判断が曖昧なチケットは、無理にどちらかへ寄せず両視点で講評します。

### 5. Progressive Disclosure

SKILL.md 本体を短く保ち、観点の詳細を `reference/`（1階層）へ退避します。
[Claude Code Review Skill の設計書 §2.1](../claude-code-review-skill/docs/design.md) と
同じ作法です。各 `reference/*.md` は対応する Step に来たときだけ読みます。

### 6. チケットを編集しない

チケット不可侵は **「Jira 書き込み手段を持たせない」（MCP なし・Bash なし）** ことで
担保します。`disallowed-tools: Edit, Write` はローカルファイルの保護とレビュアーロールの
宣言で、[Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)の
「禁止は本文でなく機構で」の適用です。出力は「作成者の自己追記用の下書き」まで
（他者が督促として貼る道具にしない）。

## Webリサーチの根拠

| 出典 | 本スキルへの反映 |
|---|---|
| Atlassian — Post-incident review best practices / Postmortems handbook | 必須フィールド（severity / 影響開始・検知・復旧の時刻定義）、影響 6 次元、公開リードタイム（目安）、follow-up の work item 化 |
| Atlassian / PagerDuty — Blameless postmortem | `blameless-language.md` の検出パターンと言い換えテンプレート、foresight not hindsight |
| John Allspaw — "Blameless PostMortems and a Just Culture" / "The Infinite Hows" | second story チェック、「因果の深さ（why の本数でなく到達点）」、単線 why の否定 |
| Fred Hebert — "Superficial Blamelessness" | 言い換えだけで second story を欠くものは proximate 停止として要改善 |
| Google SRE Book — "Postmortem Culture" | 免責文、想定利用者、「良い点」の先出し、対応判断を後知恵で断罪しない、SLO 影響 |
| Richard Cook — "How Complex Systems Fail" | contributing factors は複数（小規模は単一も可）、why now（latent condition）、対策の副作用検査 |
| Microsoft Research — "Code Reviews Do Not Find Bugs" / Google の code review 分析 | コードレビューをすり抜け工程・再発防止の主軸にしない |
| incident.io — SRE incident post-mortem best practices | アクションアイテム 4 属性 + 4 分類（detective/mitigative/preventative/corrective）、クラス有効性、カバレッジ、健全性メトリクス、"CI missed the bug" 型 |
| Rootly — Postmortem meeting guide | タイムラインのフェーズ（検知→エスカレーション→診断→緩和→解決）、アクションアイテムの検証方法 |
| Bug triage 各種（Plane / BugReel / Bird Eats Bug / Supportbench） | `bug-checklist.md`（再現手順、期待 vs 実際、環境情報、severity と priority の区別） |

## 成果物

- [スキル実装](skill/README.md) — `jira-incident-review` スキル本体。任意の環境へコピーして単独動作
- [設計書](docs/design.md) — 設計原則、スキル仕様、レビュー手順、**却下した設計案**、eval 定義、未解決事項
- [Eval 定義](evals/README.md) — 評価タスク（`tasks.jsonl`）と評価方針

導入は `skill/jira-incident-review/` をスキル配置先へコピーするだけです。

```bash
cp -r skill/jira-incident-review ~/.claude/skills/
```

## 既存パターンとの関係

| パターン | 関係 |
|---|---|
| [Claude Code Review Skill](../claude-code-review-skill/README.md) | 姉妹スキル。配置・frontmatter・Progressive Disclosure の作法を継承。対象がコード差分（あちら）かチケット記述（本スキル）かで分かれる。精度方針も逆（precision 優先 / 網羅） |
| [Incident Response Harness](../claude-code-incident-response-harness/README.md) | 別レイヤ。あちらは本番対応の進行、本スキルは事後のチケット品質レビュー |
| [Cookbook Harness](../claude-code-cookbook-harness/README.md) | P2（トリガーフレーズ列挙）と P3（権限拘束ロール）を継承 |
| [Human Gate Policy](../human-gate-policy.md) | 本スキルは判断材料を提供するのみ。チケットクローズの承認判断は同ポリシーに従う |
| [Change Intent Record](../change-intent-record.md) | 判断根拠を残す発想を共有 |

## 未解決事項

設計書 §8 に記載の通り、**eval の実行基盤は含みません**。`tasks.jsonl` は仕様に
とどまります。また次は実測前です。

- 網羅方針が粗探し・**萎縮**を増やさないか（T1/T8/T11/T12/T15 と免責文・「良い点」先出しで対処）
- C7（根本原因と対策の接続）/ カバレッジ判定の客観性（最深 factor の特定に主観が入りうる）
- 種別判定の精度（Step 1 の再考ガードと T13 で対処）
- SKILL.md が 150 行目標を超過（重複記述を圧縮して約 220 行。免責文・利用者節・
  判定値表・4 群ブロッカー見出しは削れない固有記述で、150 行は未達）
