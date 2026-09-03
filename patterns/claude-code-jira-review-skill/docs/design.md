# Jira インシデント/障害チケットレビュースキル設計書

- 作成日: 2026-09-03
- 対象: 貼り付けた Jira チケット（本番インシデント / 開発時の障害）を品質基準でレビューする単独動作スキル（`/jira-incident-review`）
- 位置づけ: [Claude Code Review Skill](../../claude-code-review-skill/README.md) の姉妹。あちらはコード差分、本スキルはチケット記述と品質プロセスの穴を対象にする
- 目的: ポストモーテム / バグチケットのレビュー観点を、Webリサーチした一次情報に基づいて機械化し、PIR 会議前・チケットクローズ前のセルフチェックに使えるようにする

本文書は設計の意図と根拠を記す。実装（SKILL.md 本体）は本設計に従う。

---

## 1. なぜ作るのか

### 1.1 既存資産との差分

このリポジトリには `diff-review` スキルがあるが、対象は**コードの差分**である。
Jira チケット（特にインシデントのポストモーテム）の**記述の質**と、そのチケットが
露呈させている**品質プロセスの穴**を評価する仕組みは無い。

インシデント対応そのものの進行管理は [Incident Response Harness](../../claude-code-incident-response-harness/README.md)
が担うが、これは「対応中」のためのもので、「事後に書かれたチケットが基準を満たすか」は
守備範囲外である。

### 1.2 何を検査するか

Webリサーチ（§3）が一致して指摘するのは次の 2 点である。

1. **ポストモーテムの価値はアクションアイテムの実効性で決まる**（incident.io: 完了率
   50% 未満は「ドキュメント演劇」）。
2. **単一 root cause と非難的表現は無効な対策を生む**（Kitchen Soap / Atlassian）。

本スキルはこの 2 点を最重要ステップに置く。記述が整っていても、すり抜け工程が未特定・
再発防止が「周知」止まり・アクションアイテムに owner がない、ならブロッカーとする。

---

## 2. 設計原則

### 2.1 Progressive Disclosure（`diff-review` に準拠）

出典: [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) /
[Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

| 段階 | 内容 | ロード契機 |
|---|---|---|
| 1 | `name` + `description` | セッション開始時（常時） |
| 2 | `SKILL.md` 本体 | スキル起動時 |
| 3 | `reference/*.md` | 対応する Step に来たときのみ |

SKILL.md 本体は **150 行以内**（`diff-review` に合わせる）を目標とし、観点の詳細を
`reference/` へ退避する。**参照は 1 階層まで**（公式: ネストした参照は `head -100` で
部分読みされ情報が欠落する）。100 行超の参照ファイルには先頭に目次を置く。

（レビュー反映で免責文・想定利用者節・判定値対応表・4 群ブロッカー基準を追加し、
その後 reference と重複する Step 3 / Step 5 / ブロッカー基準の補足文を圧縮した結果、
SKILL.md は約 220 行。150 行には未達だが、残りは免責文・想定利用者節・判定値対応表・
4 群ブロッカー見出しなど心理的安全性・判定一貫性に不可欠な固有記述である。§8 に記載。）

種別判定（Step 1）で分岐し、`incident-checklist.md` と `bug-checklist.md` の**片方だけ**を
読む。両方の先読みはしない（種別を曖昧と判定した場合のみ両方読む）。

### 2.2 Degrees of Freedom

| 層 | 自由度 | 対象 | 記述形式 |
|---|---|---|---|
| 種別判定 | **低** | インシデント / バグ | 判定表（手がかり → 種別） |
| チェックリスト評価 | **中** | 各項目の合否 | 項目定義＋合格の目安。判定はモデル |
| プロセスの穴の評価 | **中** | QA/QC | 分類表＋「退職しても残るか」の問い |
| blameless / アクションアイテムの不備指摘 | **低（保守的）** | 非難・曖昧さ | 本文を引用できるものに限る |
| 報告 | **中** | 出力 | テンプレート＋逸脱許容 |

blameless とアクションアイテムの不備指摘を低自由度（引用必須）にするのは意図的である。
網羅方針の代償である「粗探し」を、ここで構造的に抑える。

### 2.3 網羅方針を選ぶ（`diff-review` と逆）

`diff-review` は precision 優先で「失敗シナリオを書けない指摘は出さない」。
本スキルは**チェックリスト型**として全項目に `合格 / 要改善 / 該当なし` を付ける。

理由: チケットの欠陥の多くは**構造的な欠落**（severity フィールドがない、タイムラインの
フェーズが抜けている、影響の定量値がない、owner がない）であり、「記載なし = 要改善」で
機械的・客観的に拾える。ここは 2 人のレビュアーが独立に同じ判定へ至る領域であり、
網羅が有効に働く。

一方、コードの欠陥判定のような「もっともらしいが到達不能」の偽陽性リスクは、チケット
レビューでは blameless 指摘とアクションアイテムの不備指摘に集中する。そこだけ引用必須
（§2.2）にして precision を守る。

### 2.4 プロセスの穴を最上位に置く

出典: [SRE incident post-mortem best practices（incident.io）](https://incident.io/blog/sre-incident-postmortem-best-practices) /
[Postmortems handbook（Atlassian）](https://www.atlassian.com/incident-management/handbook/postmortems) /
[Code Reviews Do Not Find Bugs（Microsoft Research, ICSE 2015）](https://www.microsoft.com/en-us/research/publication/code-reviews-do-not-find-bugs-how-the-current-code-review-best-practice-slows-us-down/) /
[How Complex Systems Fail（Richard Cook）](https://how.complexsystems.fail/)

QA/QC 観点（`reference/qa-process.md`）を Step 3 に置き、次を満たさなければ記述が
整っていてもブロッカーとする。

- 検知経路: 監視で検知したか、顧客報告で検知したか（後者は監視の穴）
- すり抜け工程: 障害の性質（実装バグ / 設計欠陥 / キャパシティ / 外部依存 / 組織）で
  分岐し、実装バグならどの**テストのレイヤ**（unit / integration / E2E / 型 / lint /
  staging / canary）をすり抜けたか特定されている。**コードレビューはすり抜け工程に
  含めない**（下記）
- 再発防止の実効性: 品質プロセスへの恒久的な組み込みか。判定の問いは
  **「同じ人が退職しても、この対策は残って機能するか」**。最深の systemic cause に
  対応するアクションアイテムがあるか（根本原因と対策の接続）
- 回帰テスト: この特定の不具合を再発させないテストが定義されている
- 副作用: 恒久策が新たな失敗点・運用負荷を増やさないか（How Complex Systems Fail
  Point 15）

#### コードレビューをすり抜け工程・再発防止の主軸にしない

コードレビューの主目的は保守性・可読性・知識移転であって欠陥検出ではない。実測でも
レビューコメントの約 15% しか欠陥に関係せず、約 80% のレビューはバグを見つけない
（Microsoft Research "Code Reviews Do Not Find Bugs"）。Google の code review 分析でも
ROI の大半は知識移転とされる。

したがって:
- 「レビューで見落とした」を根本原因・すり抜け工程として書いているチケットは、それ
  自体を**要改善**とし、「この不具合を捕らえるテストが無かった / 不十分だった」への
  書き換えを促す（TDD / shift-left の前提では、欠陥検出はテストの責務）。
- 「レビューチェックリストに項目追加」を主たる再発防止策にしているものも弱いと指摘し、
  テスト / CI チェックの追加を求める。レビュー観点追加はテスト等とセットなら補助として
  認める。
- レビューが関わるのは「テスト追加の要否がレビューや CI で可視化・強制される仕組みが
  あったか」というプロセス設計の側面だけ。

### 2.5 blameless を機構で扱う

出典: [How to run a blameless postmortem（Atlassian）](https://www.atlassian.com/incident-management/postmortem/blameless) /
[The Blameless Postmortem（PagerDuty）](https://postmortems.pagerduty.com/culture/blameless/) /
[Blameless PostMortems and a Just Culture（John Allspaw）](https://www.shaunabram.com/blameless-postmortems-post-by-john-allspaw/) /
[Superficial Blamelessness（Fred Hebert）](https://resilienceinsoftware.org/news/11502437) /
[Postmortem Culture（Google SRE Book）](https://sre.google/sre-book/postmortem-culture/)

「エンジニアがデプロイし忘れた」→ 再教育、という無効な対策を生む表現を検出し、
`reference/blameless-language.md` の言い換えテンプレートでシステム主語へ書き直させる。
検出は**引用できる表現に限る**（「これは暗に人を責めている」までは踏み込まない）。
**引用に実名は含めない**（引用が必要なのは precision のためで、実名は不要）。

言い換えただけで終わらせない（second story）。言い換え先が「〜する仕組みが無かった」で
止まり、その先の「なぜその仕組みがそうなっていたか（要件未明文化 / コスト判断 /
レビュー負荷 / 過去に問題化していない）」が無ければ、表面的な言い換え（Hebert
"Superficial Blamelessness"）であり proximate cause 停止として要改善とする。

出力には免責文を必ず入れる（このレビューはプロセス改善のためで、担当者の評価材料では
ない）。使用主体は「作成者/対応チームのセルフチェック、PIR ファシリテータの会議準備」に
限る旨を SKILL.md に明示する（スキルは誰が起動したか知らないため機構では縛れず、文書
での明示に留める。§5.6 参照）。実名でのタイムライン記録・対応者の実名記載それ自体は
非難ではなく、言い換えを提案しない。

### 2.6 Evaluation-Driven / Ratchet

`evals/tasks.jsonl` に正例・負例の両方を置く。実使用で誤検出・見逃しが出るたびに、
該当する `reference/*.md` に判定基準を 1 行、`tasks.jsonl` にタスクを 1 件足す。

---

## 3. Webリサーチの反映

| 出典 | 反映先 |
|---|---|
| Atlassian — Post-incident review best practices / Postmortems handbook | `incident-checklist.md`: severity / 影響開始・検知・復旧時刻（時刻の定義ブロック、4 つ揃わないとブロッカー）/ 影響 6 次元 / 公開リードタイム（目安として緩和）/ follow-up の work item 化 |
| Atlassian / PagerDuty — Blameless postmortem | `blameless-language.md`: 検出パターン（人名 + 過失動詞、和英）と言い換えテンプレート、許容される表現。`incident-checklist.md` B6: foresight not hindsight |
| John Allspaw — "Blameless PostMortems and a Just Culture" / "The Infinite Hows" | `blameless-language.md`: second story チェック。`incident-checklist.md` C1: 「5 Whys の深さ」→「因果の深さ（本数でなく到達点）」、単線 why の否定 |
| Fred Hebert — "Superficial Blamelessness" | `blameless-language.md`: 言い換えだけで second story を欠くものは proximate 停止として要改善 |
| Google SRE Book — "Postmortem Culture: Learning from Failure" | `SKILL.md`: 免責文、想定利用者節、「良い点」を先に列挙。`incident-checklist.md` C8/E2: 対応判断を後知恵で断罪しない。`action-items.md`: アクションアイテムの適切さと優先順位。D1: SLO 影響 |
| Richard Cook — "How Complex Systems Fail" | `incident-checklist.md` C3（Point 3: 各要因は necessary but insufficient、ただし小規模は単一要因も可）、C6 why now（Point 4: latent condition は常在）。`qa-process.md` §6 対策の副作用（Point 15） |
| Microsoft Research — "Code Reviews Do Not Find Bugs" / Google の code review 分析 | `qa-process.md` §0/§2: コードレビューをすり抜け工程の原因にしない。§3: レビューチェックリスト追加は弱い再発防止策。`incident-checklist.md` / `blameless-language.md`: 「レビューで見落とした」をテスト欠如へ書き換え |
| incident.io — SRE incident post-mortem best practices | `action-items.md`: 4 属性 + detective/mitigative/preventative/corrective の 4 分類、クラス有効性、カバレッジ。`qa-process.md`: "CI missed the bug" 型、健全性メトリクス（完了率 80%+ / 再発率 <5%） |
| Rootly — Postmortem meeting guide | `incident-checklist.md`: タイムラインのフェーズ（検知→エスカレーション→診断→緩和→解決）。`action-items.md`: 検証方法 |
| Bug triage 各種（Plane / BugReel / Bird Eats Bug / Supportbench） | `bug-checklist.md`: タイトル / 再現手順 / 期待 vs 実際 / 証跡 / 環境情報 / severity と priority の区別 / 再現可否確認 / 担当アサイン。C1a/C1b: 作り込みの技術的原因とすり抜けの構造的理由を分割 |

---

## 4. スキル仕様

### 4.1 配置と命名

```text
skill/jira-incident-review/
├── SKILL.md
└── reference/
    ├── incident-checklist.md
    ├── bug-checklist.md
    ├── qa-process.md
    ├── blameless-language.md
    └── action-items.md
```

`reference/` は単数形（`diff-review` に合わせる）。スクリプトは持たない（決定論的に
処理すべき「対象確定」が無く、入力は貼り付けテキストのみのため）。

### 4.2 frontmatter

```yaml
---
name: jira-incident-review
description: >-
  貼り付けた Jira のインシデント/障害チケットをレビューし、必須フィールド・
  タイムライン・根本原因・影響評価・アクションアイテムの質と、検知/テスト/
  再発防止という品質プロセスの穴を、チェックリスト全項目に合否を付けて報告する。
  非難的表現は言い換え案を示す。チケットの編集は行わない。
when_to_use: >-
  「このインシデントチケット見て」「ポストモーテムをレビュー」「障害票の質を確認」
  「再発防止策これで十分？」「バグチケットちゃんと書けてる？」「review this incident
  ticket」「check this postmortem」などで起動。PIR 会議前、チケットクローズ前に使う。
argument-hint: "[チケット本文を貼り付け]"
allowed-tools: Read
disallowed-tools: Edit, Write, NotebookEdit
model: inherit
---
```

- `allowed-tools: Read` のみ。Jira への接続はしないため Bash / WebFetch は付けない。
  `reference/*.md` を読むために Read は要る。
- `disallowed-tools: Edit, Write, NotebookEdit` は**ローカルファイルの保護とレビュアー
  ロールの宣言**である。チケットそのものの不可侵は「Jira 書き込み手段を持たせない」
  （MCP なし・Bash なし）ことで別途担保されており、`disallowed-tools` はそこには届かない。
  将来 reference にファイル生成手順が紛れ込む場合やセッション側に広い権限がある場合の
  保険として置く（`diff-review` と同じ宣言だが、あちらは Bash を持つため実効性がより高い）。
- `when_to_use` は `diff-review` の「レビューして」単独トリガーと競合しないよう、
  「インシデントチケット」「ポストモーテム」「障害票」「再発防止策」を明示する。

#### 4.2.1 配布形態の制約

`when_to_use` / `argument-hint` / `disallowed-tools` / `model` は Claude Code 専用
フィールドで、claude.ai アップロード・Skills API・`package_skill.py` ではハードエラーに
なる。`disallowed-tools` は設計の中核なので、この非互換は意図的に受け入れる
（`diff-review` と同じ判断）。

### 4.3 処理フロー（SKILL.md の Step）

| Step | 内容 | 読む参照 |
|---|---|---|
| 1 | チケット種別を判定（インシデント / バグ / 曖昧）。Step 2 で「該当なし」多数なら再考 | なし（判定表は SKILL.md 内） |
| 2 | 種別のチェックリスト全項目に合否 | `incident-checklist.md` または `bug-checklist.md`（曖昧なら両方） |
| 3 | QA/QC 観点（障害分類・検知経路・すり抜けたテストのレイヤ・再発防止の実効性・回帰テスト・副作用） | `qa-process.md` |
| 4 | 各アクションアイテムを 7 軸で個別評価 + カバレッジ | `action-items.md` |
| 5 | 非難的表現をスキャン、言い換え案（言い換え先が分析で掘られているかも見る） | `blameless-language.md` |
| 6 | `false-positives.md` と照合 → 総評（ブロッカー→軽微）＋追記文案 | `false-positives.md` |

### 4.4 ブロッカーの定義

SKILL.md「ブロッカーの基準」を 4 群に分けて集約する。各 reference の該当項目にも
太字で個別記載があり、本一覧は閉じたリストではない（reference が個別に定める条件も含む）。

**インシデント（記述）**
- severity / 影響開始時刻 / 検知時刻 / 復旧時刻 のいずれか欠落（検知・復旧までの時間が出せない）
- 根本原因が proximate cause で止まっている（C2 ×、C1 が「修正可能な機構の名指し」に届かない）
- 最深の systemic cause に対応するアクションアイテムがない（C7 / カバレッジ）

**バグ（記述）**
- 再現手順がない / 再現不能

**QA/QC（種別共通）**
- 実装バグなのにすり抜けたテストのレイヤが 1 つも特定されていない
- 設計欠陥・キャパシティ・外部依存・組織要因なのに、対応する問いに 1 つも答えていない
- 再発防止策が「周知」「注意」「再教育」止まりで恒久的なプロセス組み込みがない
- 回帰テストがない（インシデント）
- 顧客報告で検知したのにアラート追加がアクションアイテムにない
- 過去の同一障害があるのに前回対策の検証がない

**アクションアイテム**
- owner または期日がないアクションアイテムが 1 件でもある
- アクションアイテムがゼロ件

**種別共通**
- 非難的表現が根本原因欄・アクションアイテム欄の本文に含まれている（実名 + 過失動詞）

### 4.5 出力

SKILL.md の「出力形式」ブロックに Markdown ひな型を置く。**冒頭に免責文**（改善提案で
あり個人評価材料ではない）／サマリ／**良い点（合格項目を先に列挙）**／必須項目チェック
（表。同一判定が続く項目はグループ化可）／講評／QA/QC 講評／アクションアイテム評価
（表 + カバレッジ）／blameless 指摘（実名は伏せる）／**追記推奨文案**（「作成者の
自己追記用の下書き」と枠付け、命令形回避、欠落項目のみ）。

判定値の対応表を SKILL.md に置き、3 値（合格 / 要改善 / 該当なし）、要改善の内訳
（記載追加で解消 / 内容の見直し）、アクションアイテム表の ○/×、総合列の 3 値、
ブロッカー昇格ルールの関係を 1 表で示す。「記載なし」は原則「要改善（軽微）」だが、
§4.4 に該当する「記載なし / 未特定」はブロッカーに昇格する。

---

## 5. 却下した設計案

### 5.1 Jira MCP でチケットを自動取得する

却下。現状このリポジトリ / 想定利用環境に Atlassian MCP 連携が無く、前提にすると
「MCP が無ければ動かない」スキルになる。貼り付け前提なら接続構成に依存せず動く。
MCP がある環境では利用者が本文を貼る一手間だけで済む。将来 MCP 前提の変種を別途
作る余地は残す。

### 5.2 インシデントとバグを 1 つのチェックリストで扱う

却下。必須フィールドが大きく異なる（インシデント: severity / TTD / TTR / 影響 6 次元、
バグ: 再現手順 / 環境情報 / severity と priority の区別）。1 枚にすると「該当なし」だらけに
なり、網羅方針のノイズが増える。Step 1 で分岐して片方だけ読む方が精度・トークン効率とも
良い。

### 5.3 precision 優先（`diff-review` と同じ方針）

却下。チケットの欠陥は構造的な欠落が主で、客観的に拾える。precision 優先にすると
「severity フィールドがない」のような明白かつ重要な欠落を「確証が弱い」と見送りかね
ない。ただし blameless / アクションアイテムの不備指摘だけは引用必須にして、その領域の
偽陽性を抑える（§2.2、§2.3）。

### 5.4 5 段階評価（合格 / 概ね合格 / 要改善 / 不十分 / 該当なし）

却下。境界の議論が増え、利用者の判断コストが上がる（`diff-review` の severity 2 値化と
同じ理由）。`合格 / 要改善 / 該当なし` の 3 値に絞り、「クローズを止めるか」はブロッカー
基準（§4.4）で別途 2 値判定する。ただし「要改善」だけは萎縮対策として内訳を 2 つ
（記載追加で解消 / 内容の見直しが必要）示す。実効的な状態数が増えて混乱しないよう、
SKILL.md に「判定値の対応表」を 1 つ置いて ○/× と 3 値と総合列の関係を明示する。

### 5.5 健全性メトリクス（完了率・再発率）を必須項目にする

却下。これらは複数チケット・期間集計で出す組織メトリクスであり、1 枚のチケット本文
からは判定できない。`qa-process.md` では「言及があれば加点、無くても可」に留め、
「過去に同じ障害があったと本文にあるのに前回対策の検証が無い」場合だけブロッカーに
する。

### 5.6 利用者を機構的に限定する

却下（というより実現不可）。スキルは「誰が起動したか」を知らないため、「管理者は使えない」
「督促には使えない」を機構で縛れない。SKILL.md の「想定利用者」節と出力の免責文で
文書的に明示するに留める。心理的安全性の観点で重要なので、明示は省かない。

### 5.7 コードレビューをすり抜け工程の候補に含める

却下。当初案では「unit / integration / レビュー / staging / canary」を横並びで
すり抜け工程の候補に置いていた。しかしコードレビューの主目的は保守性・知識移転で
あって欠陥検出ではなく（Microsoft Research "Code Reviews Do Not Find Bugs": コメントの
約 15% しか欠陥に関係しない、約 80% のレビューはバグを見つけない。Google の分析でも
ROI の大半は知識移転）、レビューに欠陥検出を期待する設計自体が誤り。TDD / shift-left の
前提では欠陥検出はテストの責務。すり抜け工程は**テストのレイヤ**（unit / integration /
E2E / 型 / lint / staging / canary）に限定し、「レビューで見落とした」はそれ自体を
要改善として「テスト欠如」への書き換えを促す。レビューが関わるのは「テスト追加の要否が
ゲートで可視化・強制されるか」というプロセス設計の側面のみ。

---

## 6. Eval 定義

詳細は [evals/README.md](../evals/README.md)。`tasks.jsonl` に正例・負例を置く。
code-based タスクは `grader_keywords`（must_all + 各要素内 OR）を持つ。

| ID | 種別 | grader | 測定対象 | 狙い |
|---|---|---|---|---|
| T1 | 正例 | model | 過剰指摘の抑制 | 良いインシデントチケットでブロッカー 0、無根拠な要改善なし |
| T2 | 正例 | code | 検出 | タイムライン欠落・proximate 停止・曖昧なアクションを検出 |
| T3 | 負例→検出 | model | blameless | 実名 + 「〜し忘れた」に対し引用（実名伏せ）と言い換え案を出す |
| T4 | 正例 | model | 種別分岐 | 良いバグチケットでバグチェックリストを適用、ブロッカー 0 |
| T5 | 正例 | code | 検出 | 再現手順なし・severity/priority 混同を検出 |
| T6 | 正例 | model | プロセスの穴 | 「今後は周知」だけの再発防止 + 最深層と対策の非接続を指摘（必須 3 + 加点 5 のルーブリック） |
| T7 | 正例 | model | 種別曖昧 | 曖昧なチケットで両視点の講評を出す |
| T8 | 負例 | model | precision | 良いチケットへのアクションアイテム不備指摘に本文引用があるか |
| T9 | 負例→検出 | model | 浅い深掘り | 5 Whys を 5 段書いてあるが単線で Why5 が「担当者の考慮漏れ」→ 要改善〜ブロッカー |
| T10 | 負例 | model | 対策の実効性 | 7 軸 ○ だが detective なアラート追加のみで preventative なし → 指摘 |
| T11 | 正例 | model | 偽陽性 | 散文で深い根本原因（5 Whys 形式でない）→ 根本原因は合格、指摘は影響評価/タイムラインに限定 |
| T12 | 正例 | model | 偽陽性 | 小規模・単一要因が妥当なインシデント → C3 を機械的に要改善にしない |
| T13 | 正例 | model | 種別判定 | SEV 表記なし・顧客影響が言外 → インシデントと判定し根拠を述べる |
| T14 | 正例 | model | 個数 | アクションアイテム 5 件 → 「真因を絞れていない可能性」を添える |
| T15 | 正例 | model | 偽陽性 | 実名入り中立タイムライン行 + 根本原因はシステム主語 → blameless 指摘ゼロ |
| T16 | 負例→検出 | model | blameless washing | 文言は完璧にシステム主語だが分析が proximate 止まり → C2/second story で要改善 |

---

## 7. 運用

### 7.1 Ratchet パターン

実使用で誤検出・見逃しが出たら次のように 1 件ずつ足す。

1. **判定基準の追加** なら、該当する `reference/*.md` に 1 行追記
2. **偽陽性・過剰指摘** なら、`reference/false-positives.md` に 1 件追記
   （Step 6 で照合される。diff-review の `gotchas.md` に相当）
3. いずれも `evals/tasks.jsonl` に対応タスク（正例 / 負例）を 1 件追加

`false-positives.md` / 各 reference が 100 行を超えたら先頭に目次を置く。

### 7.2 時限情報を書かない

「2026 年時点で」のような記述を SKILL.md / reference に書かない。ベストプラクティスの
数値（完了率 80%、再発率 <5%、48 時間ドラフト）は出典と共に reference に置き、本文には
「目安」として書く。「48 時間」は組織の PIR 規約が優先する旨を明記し、「明らかな放置
（週単位）」のみ要改善に緩めた。日付の例文は相対表現（「YYYY-MM-DD 形式の暦日」）に
一般化する。

---

## 8. 未解決事項

- **eval 実行基盤は含まない。** Agent Skills の eval を実行する組み込みの仕組みは無く、
  `tasks.jsonl` は仕様にとどまる。
- **網羅方針が粗探しを増やさないかは実測前。** T1 / T8 / T11 / T12 / T15（良いチケットへの
  過剰指摘）で継続的に確認する。over-flagging タスクでは「必須項目チェック表の要改善率
  （無根拠 0 が目標）」を指標化する。
- **網羅方針の「萎縮」リスクは過剰指摘とは別軸。** 全項目採点というトーンが正直な記述
  （自分たちの対応の遅れ、見落とし）を抑制しないか。免責文・「良い点」の先出し・要改善の
  内訳表示で緩和したが、実測前。
- **C7（根本原因と対策の接続）/ カバレッジ判定の客観性は実測前。** 「最深の contributing
  factor」の特定にレビュアーの主観が入りうる。T6 / T9 / T10 で測る。
- **SKILL.md が 150 行目標を超過**（約 220 行）。reference と重複する Step 3 / Step 5 /
  ブロッカー基準の補足文は圧縮済み。150 行は未達だが、残りは免責文・想定利用者節・
  判定値対応表・4 群ブロッカー見出しなど心理的安全性・判定一貫性に不可欠な固有記述。
- **種別判定の精度は未測定。** 「本番リリース済み機能のバグ」をインシデント側で見るべき
  ケースの線引きが曖昧に残る。`bug-checklist.md` に注記、Step 1 に再考ガード（Step 2 で
  「該当なし」多数なら再判定）、T13（SEV 表記なしの推論）を追加したが、実チケットでの
  分岐誤りは Ratchet で拾う。
