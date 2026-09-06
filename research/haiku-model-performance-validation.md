# Haiku モデル性能検証

Claude Haiku 4.5（`claude-haiku-4-5-20251001`）に、このリポジトリの実ファイルを対象とした
代表タスクを実行させ、Sonnet 4.5 がその成果物を共通ルーブリックで採点した記録。
「どの種別のタスクを Haiku に委譲してよいか、どこから劣化するか」を数値で示すことが目的。

## 結論

- **4 種別すべてでルーブリック平均 9.3〜10.0 / 10（グレード S）。** 明確な指示と、この
  リポジトリのように構造化された対象がある限り、Haiku の成果物の質は Sonnet ベースラインに
  対して 93〜109% の範囲に収まった。本検証のタスクでは Haiku の破綻点は観測できなかった
  （＝タスクが Haiku の限界を測るには易しすぎた。[限界](#限界)を参照）。
- **委譲してよい（Sonnet と実質同等）**: 機械的変換・定型修正（相対比 1.09）、
  コードレビューの正例・負例（相対比 1.00）。後者には「Haiku で反証ゲート（Step 4）が
  省略されないか」という既存 eval の重点確認事項が含まれるが、**全 6 試行で省略は起きず**、
  到達不能な欠陥候補を明示的に棄却できた。
- **条件付きで委譲（結果は良いが監督が要る）**: 探索・情報収集（相対比 0.97）と
  設計・計画（相対比 0.97）。理由は質そのものより (1) **試行間のばらつき** — 探索で
  行番号を 1 箇所取り違えた試行、設計で「軽量」の粒度を外した試行がそれぞれ 1/3 で発生、
  (2) **反復コスト** — 探索タスクで Haiku は Sonnet の 2〜3 倍のツール往復と最大 4 倍の
  トークンを消費した。単価は安いがトークン量が増えるため、探索系では純コスト優位が縮む。
- **委譲を避ける（本検証では未測定だが既存規定どおり）**: 曖昧な要件からの本格的な
  アーキテクチャ設計。D1（新パターン提案）で Haiku は 3 試行とも「実在する空白を選び
  4 項目を埋める」ことはできたが、2/3 が「軽量パターン 1 案」の制約を超えて重い多工程
  プロセスへ膨らんだ。上位モデル（Opus）との比較は本検証では行っていない。

## 調査方法

[Anthropic「Demystifying evals for AI agents」](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
と、このリポジトリの `patterns/claude-code-review-skill/evals/README.md` の方針に従う。
成果物を採点する（経路ではなく）／正例・負例の両方を置く／各タスクを複数回試行する／
可能な限りコードベース grader。記録指標は
`research/claude-code-development-harness-patterns.md` §10（複数 trial の成功率・コスト・
latency・介入回数）に揃えた。

### 実行

- 4 種別 × 各 2 タスク。**Haiku 各 3 試行 + Sonnet ベースライン各 1 試行 = 計 32 サブエージェント実行。**
- `Agent` ツールで実行。探索系（X1・X2）は `subagent_type: Explore`、他は `general-purpose`。
  Haiku は `model: haiku`、ベースラインは `model: sonnet`。作業ディレクトリはリポジトリルート。
- タスクの対象はすべてこの作業ツリーの実ファイル。人工 fixture はコードレビュー（R1・R2）の
  diff のみ（`scratchpad/R1`, `scratchpad/R2`、[再現手順](#再現手順)に転記）。
- 記録: 成果物本文（`research/_haiku-validation-runs/<taskid>.md`）、所要時間、ツール往復数、
  サブエージェントのトークン消費（`subagent_tokens`、コストの代理指標）。

### タスク定義

| ID | 種別 | 種類 | grader | 概要 |
|---|---|---|---|---|
| M1 | 機械的変換 | 正例 | コードベース | `evals/tasks.jsonl` の 7 タスクを 5 列の Markdown 表へ変換 |
| M2 | 機械的検査 | 負例 | コードベース | `README.md` «Research» のリンク実在チェック（全健全＝誤検出しないのが正解） |
| X1 | 探索 | — | コードベース | 「反証ゲート」の全出現箇所を `file:line` で列挙（正解 14 行/6 ファイル） |
| X2 | 探索 | — | コードベース | 全 `SKILL.md` の tools フロントマターを表に（正解 4 ファイル） |
| R1 | コードレビュー | 正例 | コードベース | `ceil`→`//` のオフバイワン diff（= 既存 eval E1）。真の blocking 1 件 |
| R2 | コードレビュー | 負例 | コード＋モデル | 到達不能な null 参照候補を含む diff（= 既存 eval E6）。真の blocking なし |
| D1 | 設計判断 | — | モデルベース | 既存パターンの空白を埋める新軽量パターンを 1 案提案 |
| D2 | 設計判断 | — | モデルベース | 2 つの軽量ハーネスを統合すべきか、両論＋推奨 |

### 採点ルーブリック

各試行を 5 観点 × 0–2 点（計 10 点）。コードベース採点タスクは観点を該当項目に読み替える。

| 観点 | 0 | 1 | 2 |
|---|---|---|---|
| 正確性 | 結論・事実に誤り | 一部誤り | 誤りなし |
| 網羅性 | 要求の半分未満 | 大半を満たす | 全項目を満たす |
| スコープ規律 | 範囲外を走査／変更 | 軽微な逸脱 | 依頼範囲に限定 |
| 手順遵守 | 要求手順を実施せず | 部分的 | 反証記述・検証まで実施 |
| 自己検証 | 裏付けなし | 一部提示 | 主張ごとに根拠提示 |

タスクスコア = 3 試行の平均。種別スコア = 2 タスクの平均。
グレード: 9–10=S / 7.5–8.9=A / 6–7.4=B / 4–5.9=C / <4=D。
コードベース採点タスク（M1・M2・X1・X2・R1・R2）の ground truth は Sonnet 側で
`Grep`/`Glob`/`Read` により再構築し、セル単位・行単位で突合した。

## 種別別結果

種別スコアと対 Sonnet 相対比の一覧（詳細は `research/_haiku-validation-runs/<ID>.md`）:

| 種別 | タスク | Haiku 平均 | 試行間 range | Sonnet | 相対比 | グレード |
|---|---|---|---|---|---|---|
| 1. 機械的変換・定型修正 | M1=10.0 / M2=9.67 | **9.83** | 0.0–1.0 | 9.0 | 1.09 | S |
| 2. 探索・情報収集 | X1=9.33 / X2=10.0 | **9.67** | 0.0–2.0 | 10.0 | 0.97 | S |
| 3. コードレビュー・欠陥検出 | R1=10.0 / R2=10.0 | **10.0** | 0.0 | 10.0 | 1.00 | S |
| 4. 設計・計画・トレードオフ判断 | D1=9.33 / D2=10.0 | **9.67** | 0.0–1.0 | 10.0 | 0.97 | S |

pass rate はどの種別も 0% ではない（タスク故障の兆候なし）。

### 1. 機械的変換・定型修正 — 9.83 / S（相対比 1.09）

- **M1（jsonl→表）**: Haiku 3 試行すべてが 7 行 × 5 列を ground truth と完全一致で出力。
  Sonnet ベースラインは表の後に「表以外の説明文は不要」という指示に反する補足 3 行を付け、
  スコープ規律で 1 点減。**この 1 タスクでは Haiku が指示遵守で Sonnet を上回った。**
- **M2（リンク検査・負例）**: 全 5 リンクが実在＝「壊れたリンクなし」が正解。Haiku 全試行が
  誤検出 0（precision 満点）。3 試行中 2 試行は「〜とだけ報告」の指示に完全準拠、1 試行が
  確認リストを付けて軽微に冗長（tool_uses 4、所要 26s と最長）。
- 失敗モードの兆候: なし。ばらつきは「出力抑制の指示にどこまで従うか」に限られた。

### 2. 探索・情報収集 — 9.67 / S（相対比 0.97）

- **X1（`file:line` 列挙）**: 正解は 14 行 / 6 ファイル。haiku-1・haiku-2 は Sonnet と同じく
  14/14 を正確に列挙。**haiku-3 は `design.md:411` を `:404`（存在しない行）と誤記し 411 を
  欠落** — `git grep -n` を最後まで信頼せず記憶で補完した形跡。正確性・自己検証で減点し 8/10。
- **X2（フロントマター一覧）**: Haiku 全試行が 4 スキル × 3 フィールドを完全一致で出力。
  tools 未指定の 2 スキルを「（指定なし）」と正しく報告し、ツールをでっち上げなかった。10/10。
- 失敗モードの兆候: **行番号の精度がツール出力への忠実さに依存する。** worktrees 除外・
  無関係ヒットの排除は全試行で遵守。
- コスト: X1 で Haiku は 8〜10 ツール往復・47〜64k トークン、Sonnet は 4 往復・16.6k。
  **同等以下の成果に Haiku が 2〜4 倍のトークンを要した。** X2 も往復・トークンとも約 2 倍。

### 3. コードレビュー・欠陥検出 — 10.0 / S（相対比 1.00）

- **R1（オフバイワン・正例、= E1）**: Haiku 全試行が Step 1–5 のチェックリストを応答へ
  コピーして実施。オフバイワンを `file:line` 付きで blocking 指摘、failure_scenario に
  割り切れない具体値（11/10 等）、「検討して棄却した候補」節あり、Edit/Write 不使用 ——
  E1 の期待挙動 5 項目すべて充足。算術の検算も実施。10/10。
- **R2（到達不能候補・負例、= E6）**: **本検証の主眼。** 既存の
  `review-skill/docs/design.md` §6.4 と `evals/README.md` 61 行が「Haiku で Step 4
  （反証ゲート）が省略されないか」を重点確認事項としている。
  **結果: Haiku 3 試行すべてが反証ゲートを実行し、**「`node.parent` が None のとき
  `parent.name` で NPE」というもっともらしい候補を、直前のガード節
  `if node is None or node.parent is None: return "root"` を明示的に引用して棄却。
  誤 blocking 0、沈黙による削除もなし。E6 の期待挙動 3 項目を全試行で充足。10/10。
- 質的な差: 候補洗い出しの広さは Sonnet が上（R2 で Sonnet 6 候補 vs Haiku 3 候補）。
  ただし E6 が要求する「到達不能候補の明示的棄却」は Haiku でも確実に行われた。

### 4. 設計・計画・トレードオフ判断 — 9.67 / S（相対比 0.97）

- **D2（統合の是非）**: 明確な比較対象（2 つの README）があり判断基準も文書に書かれている
  「読解＋対比＋結論」型。Haiku 3 試行すべてが「新機能追加 vs バグ修正」「TDD vs 回帰再現
  テスト」「規模帯」を正しく対比し、Micro Bugfix 側がセキュリティ境界の変更を明示除外して
  いる細部も捉えた。推奨は 3 試行とも「統合しない＋共通部分を別テンプレート化」で一致。10/10。
  Sonnet は指示範囲（README のみ）を超えて `design.md` §5–8 まで読み「7〜8 割が同一文面」と
  定量化した（Haiku の design.md 未読は指示範囲内のため減点せず）。
- **D1（新パターン提案）**: 3 試行とも実在する空白（技術負債返済 / ドキュメント品質 /
  性能最適化）を選び 4 項目を具体的に埋めた。**減点は「軽量パターン 1 案」というスコープ制約** ——
  haiku-2 はフル skill ディレクトリ構成まで展開、haiku-3 は 6 工程＋本番 A/B＋カナリアで
  「軽量」を逸脱。各 9/10。haiku-1（技術負債返済、単一セッション）は制約に収まり 10/10。
  Sonnet ベースラインは「構造を足さず外す」Spike Harness を提案し、既存 10 パターン全てに
  個別の非重複説明を付けた。
- 失敗モードの兆候: **開放的な設計タスクほど試行間のばらつきが大きい。** 提案テーマが
  3 試行で全て異なり、スコープ制約の遵守も試行依存。

### コスト・所要時間

`subagent_tokens`（コスト代理）とツール往復数。Haiku は min–max、Sonnet は単一試行。

| タスク | Haiku tokens | Sonnet tokens | Haiku 往復 | Sonnet 往復 |
|---|---|---|---|---|
| M1 | 29.0–29.1k | 30.7k | 1 | 1 |
| M2 | 28.8–37.1k | 29.4k | 2–4 | 2 |
| X1 | 47.2–64.0k | 16.6k | 8–10 | 4 |
| X2 | 23.7–24.6k | 13.2k | 5–6 | 3 |
| R1 | 36.0–38.0k | 38.9k | 5–7 | 6 |
| R2 | 35.6–37.8k | 38.4k | 5 | 5 |
| D1 | 56.9–63.6k | 69.9k | 13–14 | 4 |
| D2 | 32.9–33.8k | 49.7k | 2 | 6 |

- 機械的変換・コードレビューでは Haiku と Sonnet のトークン量・往復数はほぼ同等。
  この帯域では Haiku の低単価がそのままコスト優位になる。
- **探索（X1・X2）では Haiku が 2〜4 倍のトークンと約 2 倍の往復を消費した。** 単発の
  計画が弱い分を往復回数で補うため、低単価でも純コスト優位は縮む、または逆転しうる。
- 開放的な設計（D1）でも Haiku は 13–14 往復（Sonnet 4）。ただし出力が浅い分トークン総量は
  Sonnet 以下になることもあり、コストは一概に言えない。
- 所要時間は Haiku が一貫して速いわけではない（X1 は Haiku 40–63s vs Sonnet 39s、
  D1 は Haiku 76–125s vs Sonnet 177s）。

## 既存の使い分け規定との対応表

| 規定（出典） | 記述 | 本検証の実測 | 提案 |
|---|---|---|---|
| グローバル `~/.claude/CLAUDE.md` 委譲表 | 「機械的な変換・定型的な修正・単純な情報収集は Haiku へ委譲」 | 機械的変換は支持（相対比 1.09、指示遵守は Sonnet 超）。**「単純な情報収集」は要注意** — 探索で行番号取り違えが 1/3、トークン 2〜4 倍 | 「情報収集」を「**結論だけでよく、file:line の精度が結果を左右しない**探索」に限定。精密な位置特定を伴う探索は Haiku 出力を grep で検算する前提にする |
| グローバル `~/.claude/CLAUDE.md` 委譲表 | 「設計・計画・トレードオフ判断で迷ったとき」は Opus | 比較対象と判断基準が文書化された設計判断（D2 型）は Haiku でも相対比 1.00。曖昧要件からの新規設計（D1 型）はスコープ逸脱が 2/3 | 「既存資料の読解＋対比で答えが出る設計判断」は Haiku 可に緩められる。「白紙からの設計」は現行どおり上位モデル |
| `docs/ai-driven-development-adoption.md` §9 | 「日常作業は標準モデル、深い設計判断・複雑な推論は上位モデルへ」 | 日常作業（変換・レビュー）で Haiku は Sonnet 同等。矛盾なし | 変更不要。ただし「Haiku を積極的に使ってよい日常作業」の例示として本検証の M1/R1/R2/D2 を挙げられる |
| `patterns/claude-code-cookbook-harness/docs/design.md` 151-171 | reviewer/qa ロールは `sonnet` 割当 | R1・R2 で Haiku は反証ゲートを省略せず相対比 1.00。**diff 限定・反証ゲート付きのレビューは Haiku でも成立** | reviewer ロールに Haiku を試す余地あり。ただし候補洗い出しの広さは Sonnet 優位のため、recall 重視の監査は sonnet 維持 |
| `patterns/claude-code-review-skill/docs/design.md` §6.4 / `evals/README.md` 61 行 | 「特に Haiku で Step 4（反証ゲート）が省略されないか重点確認」 | **R2（=E6）3 試行すべてで省略なし。** 到達不能候補をガード節を引用して明示的に棄却 | 重点確認の記述は維持（1 リポジトリ・3 試行の結果に過ぎない）。実 eval 基盤ができたら E6 を Haiku で定期実行し、この結果を回帰の基準線にする |

（規定ファイル自体の書き換えは本作業のスコープ外。上表は提案まで。）

## 限界

- **タスクがルーブリックの天井に当たった。** 4 種別すべて S で、Haiku の破綻点を捉えられて
  いない。タスクがこのリポジトリ（明示的な SKILL 手順、構造化された README、書かれた判断基準）
  由来で、Haiku の弱点である「曖昧さの解消」「長い依存連鎖の追跡」「暗黙の文脈補完」を
  ほとんど要求しなかった。より難しいタスク（複数サービスをまたぐ契約、仕様が口頭のみ、
  大規模な無構造コードベース）での再検証が要る。
- **試行数が少ない（Haiku 3・Sonnet 1）。** 相対比は Sonnet 1 試行との比であり、Sonnet 側の
  ばらつきを測っていない。range も n=3 の粗い指標。
- **grader バイアス。** モデルベース採点（D1・D2 の一部）を Sonnet が行っており、Sonnet が
  自分の出力を採点する構図が残る。コードベース採点タスクにこの問題はない。
- **fixture の人工性。** R1・R2 の diff は検証用に作った小さな Python 断片で、実際の PR の
  ノイズ（無関係な変更の混在、大きな文脈）がない。
- **コスト測定は代理指標。** `subagent_tokens` はサブエージェント経由の概算で、入出力内訳や
  キャッシュヒットを反映しない。金額換算はしていない。

## 再現手順

### タスク・プロンプト（M1〜D2）

各プロンプトを Haiku 3 回・Sonnet 1 回、同一文面で `Agent` に渡す。作業ディレクトリは
リポジトリルート。

- **M1**（general-purpose）: 「`patterns/claude-code-review-skill/evals/tasks.jsonl` を読み、
  全タスクを `id`/`kind`/`measures`/`grader`/`query` の 5 列・出現順・値そのままの Markdown
  表に変換。表以外の説明文は不要。」
- **M2**（general-purpose）: 「`README.md` の «Research» セクションのリンクだけを対象に
  リンク先ファイルの実在を検査。壊れたリンクだけ列挙。全実在なら『壊れたリンクなし』とだけ報告。」
- **X1**（Explore）: 「`.claude/worktrees/` を除くリポジトリ全体で『反証ゲート』の出現箇所を
  すべて `file:line` で列挙。各箇所が定義・説明か単なる言及・参照かも添える。」
- **X2**（Explore）: 「`.claude/worktrees/` を除く全 `SKILL.md` の `allowed-tools` /
  `disallowed-tools` / `model` を、スキル名を行にした表に。無いフィールドは『（指定なし）』。」
- **R1 / R2**（general-purpose）: 「添付の diff を `diff-review` スキル
  （`patterns/claude-code-review-skill/skill/diff-review/SKILL.md` と
  `reference/correctness.md`・`reference/gotchas.md`）の方法でレビュー。Step 1–5 の
  チェックリストを応答にコピーして進める。Step 4（反証ゲート）は省略しない。diff は
  `scratchpad/R1/change.diff`（または R2）、変更後ファイルは `pagination_after.py`
  （または `label_after.py`）。Edit/Write 不使用。」
  - R1 fixture: `total_pages()` で `math.ceil(total/per_page)` を `total // per_page` に置換
    し `import math` を削除。`total=11, per_page=10` で正しくは 2 ページ、実装は 1 ページ。
  - R2 fixture: `label(node)` に `parent = node.parent; return parent.name + " / " + node.name`
    を追加。直前に `if node is None or node.parent is None: return "root"` のガードあり。
    `.name` は None にならない旨をコメントで明示。真の blocking なし。
- **D1**（general-purpose）: 「`README.md`・`patterns/README.md`・各パターンの `README.md` を
  読み、既存がカバーしていない領域を 1 つ選び、新しい軽量パターンを 1 案提案。目的／適用範囲と
  境界／失敗モード／検証方法を含め、既存パターン名を挙げて非重複を説明。」
- **D2**（general-purpose）: 「`claude-code-lightweight-feature-harness/README.md` と
  `claude-code-micro-bugfix-harness/README.md` を読み、統合すべきか判断。両論の根拠＋推奨 1 つ。」

### 採点

上記ルーブリックで各試行を採点。コードベース採点タスクの ground truth は
`research/_haiku-validation-runs/<ID>.md` に記録済み（M1 の正解表、X1 の 14 行、
X2 の 4 スキル表、M2 の全リンク実在、R1/R2 の期待挙動）。

## 出典

- [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)（Anthropic、2026 年 9 月 6 日参照）
- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents)（Anthropic、2026 年 9 月 6 日参照）
- `patterns/claude-code-review-skill/evals/README.md` — モデル横断テスト方針（2026 年 9 月 6 日時点）
- `patterns/claude-code-review-skill/docs/design.md` §6.4 — モデル別確認観点表
- `patterns/claude-code-review-skill/skill/diff-review/SKILL.md` — レビュー 5 ステップと反証ゲート
- `research/claude-code-development-harness-patterns.md` §10 — Evals の記録指標
- `docs/ai-driven-development-adoption.md` §9 / `patterns/claude-code-cookbook-harness/docs/design.md` 151-171 — 既存のモデル使い分け規定
- 生ログ: `research/_haiku-validation-runs/{M1,M2,X1,X2,R1,R2,D1,D2}.md`
