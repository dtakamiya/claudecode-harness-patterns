# 汎用レビュースキル設計書

- 作成日: 2026-08-19
- 対象: 任意のリポジトリで単独利用できる汎用コードレビュースキル（`/xx-review`）
- 位置づけ: 既存の[Development Harness](../../claude-code-development-harness/README.md) PHASE-9エージェント群とは**別物**。工程・ゲートに束縛されず、単体で成立する
- 目的: 最新のスキル設計ベストプラクティスに基づき、precisionを設計で担保するレビュースキルを定義する

本文書は設計の意図と根拠を記す。実装（SKILL.md本体）は本設計に従って別途作成する。

---

## 1. なぜ新規に作るのか

### 1.1 既存資産との差分

このリポジトリには既にレビュー系エージェントが6本ある。

| ファイル | 行数 | 束縛 |
|---|---:|---|
| `code-reviewer.md` | 719 | PHASE-9固定、設計書§参照が前提 |
| `security-reviewer.md` | 737 | PHASE-9固定 |
| `integration-test-reviewer.md` | 559 | PHASE-8固定 |
| `test-reviewer.md` | 429 | PHASE-7固定 |
| `plan-reviewer.md` | 300 | PHASE-5固定 |
| `harness-reviewer.md` | 294 | ハーネス定義が対象 |

いずれも優れているが、3つの制約がある。

1. **工程束縛**: `allowed_phases: PHASE-9` のように特定工程でしか起動しない。単発のPRレビューには使えない。
2. **外部設計書への依存**: 本文がURL先の設計書§番号を正本として参照する。設計書のないリポジトリへコピーしても機能しない（ファイル冒頭に明記されている）。
3. **一括ロード**: 719行が丸ごとコンテキストへ載る。progressive disclosureが効いていない。

新スキルはこの3点を反転させる。**工程非依存・自己完結・段階ロード**である。

### 1.2 既存資産を置き換えない

Development Harnessを使う場面では既存の`code-reviewer.md`が正しい。ゲート条件の合接（Code Reviewer + Security Reviewer + Human Reviewer）を扱う責務は、工程を知っているエージェントにしか果たせない。

本スキルは**工程管理のない場面**（単発PR、他リポジトリ、探索的レビュー）を担当する。適用レイヤが異なるため併存する。

---

## 2. 設計原則

以下は一次情報から採用した原則である。各項に出典を付す。

### 2.1 Progressive Disclosure（3段階ロード）

出典: [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) / [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

| 段階 | 内容 | ロード契機 |
|---|---|---|
| 1 | `name` + `description` | セッション開始時（常時） |
| 2 | `SKILL.md` 本体 | スキル起動時 |
| 3 | `reference/*.md` | 該当領域に触れたときのみ |

公式は **SKILL.md本体を500行以下** とする。既存の719行エージェントはこの閾値を超えている。本スキルはSKILL.md本体を**150行以内**に抑え、観点の詳細を`reference/`へ退避する。

**参照は1階層まで**とする。公式は、ネストした参照ではClaudeが`head -100`で部分読みし情報が欠落すると明記している。したがって`reference/security.md`から`reference/owasp.md`を参照する構造は採らない。

100行を超える参照ファイルには**先頭に目次**を置く。部分読みされても全体像が見えるようにするためである。

### 2.2 Degrees of Freedom を対象の脆さに合わせる

出典: [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

公式は「崖に挟まれた細い橋」と「障害物のない野原」の比喩で、タスクの脆さに応じて自由度を変えろと述べる。本スキルでは3層に割り当てる。

| 層 | 自由度 | 対象 | 記述形式 |
|---|---|---|---|
| 対象確定 | **低** | どのdiffを読むか | 実行コマンドを厳密指定 |
| 欠陥探索 | **高** | 何が問題か | 観点リストのみ、判断はモデルへ |
| 報告 | **中** | どう出すか | テンプレート＋逸脱許容 |

対象確定を低自由度にするのは意図的である。レビュー対象がずれると以降すべてが無効になるため、ここは「細い橋」にあたる。

### 2.3 Precisionを構造で担保する

出典: [Refute-or-Promote (arXiv:2604.19049)](https://arxiv.org/abs/2604.19049) / [AI Code Review Benchmark 2026](https://www.codeant.ai/blogs/ai-code-review-benchmark-results-from-200-000-real-pull-requests)

まず、レビューツールの精度が実用水準に達していないことが大規模計測で示されている。Martian's Code Review Bench は20万件超のPRを対象に17のAIコードレビュー**ツール**を評価したが、上位でも **F1で約52%**（precision 52.2% / recall 51.1%）にとどまる。指摘の約半分が外れる水準であり、「とりあえず全部指摘させて人間が選ぶ」という運用は成立しない。

precisionとrecallは同時には立たない。どちらを取るかは設計判断であり、暗黙に決めてよいものではない。

さらにRefute-or-Promoteの論文は決定的な事例を報告している。同論文のabstractはこう述べる。

> The most instructive failure: ten dedicated reviewers unanimously endorsed a non-existent Bleichenbacher padding oracle in OpenSSL's CMS module; it was killed only by a single empirical test, motivating the mandatory empirical gate.

**10のレビュアーが全員一致で「存在しないBleichenbacher padding oracle」を承認し、それを潰したのは合議ではなく1件の実証テストだった。** レビューの数を増やしても偽陽性は消えず、実証ゲートのみがそれを排除した。同論文は敵対的な反証ゲートで171候補の約79%を公開前に排除している（31日間・7ターゲットの集計）。

なお同論文は多エージェント方式（タイトルが "Multi-Agent Review Methodology"）を扱っており、この "reviewers" が人間かエージェントかはabstractの文面だけでは確定しない。**いずれであっても本設計の含意は変わらない** — 独立した多数のレビューを重ねること自体は偽陽性を落とさず、実証可能性の検査だけが落とす。本スキルが§4.3で採るのは後者である。

したがって本スキルは**「複数の観点で数を出す」のではなく「出した指摘を自分で反証する」**構造を採る（§4.3）。

### 2.4 Recall優先が成立する条件を満たさないなら採らない

出典: [Deep Code Review: Why Recall Beats Precision for Agents](https://www.augmentcode.com/guides/deep-code-review-recall-vs-precision)

recall優先が機能するには3条件が要る。

1. リポジトリ全体のセマンティックインデックス
2. 各指摘への理由付け
3. 人間による承認ゲート

本スキルは単独動作を前提とするため、1（全体インデックス）を持たない。よって**precision優先を採る**。これは消極的な選択ではなく、条件を満たさない構成でrecallを追うと偽陽性がそのまま利用者へ届くためである。

ただし2と3は満たせる。理由付け（§4.4のfailure_scenario）と、修正を適用しない設計（§3.3）がそれにあたる。

**この選択には明確な代償がある。** 出典は、diff限定のレビューでは原理的に見えない欠陥のカテゴリが存在し、いずれも「欠陥を見るために2つ目のファイルを読む必要がある」と述べている（認可、サービス間のAPI契約違反など）。全体インデックスを持たない本スキルは、この種の欠陥を**構造的に取りこぼす**。

したがって本スキルは「見逃さないレビュー」ではない。**出した指摘が信頼できるレビュー**である。この区別は利用者へ明示する必要がある（§4.4で指摘ゼロを明示的に報告させるのはこのためでもある）。

#### 2.4.1 局所インデックスによる部分的な緩和（改訂）

**当初この限界を全面的に受け入れたが、改訂して部分的に緩和した。** 条件1が要求するのは「リポジトリ全体のセマンティックインデックス」だが、diff限定レビューが取りこぼす欠陥の多くは、**差分に現れた識別子から参照を1ホップ辿れば確証できる**。全体インデックスの構築は不要である。

したがって Step 3 に「差分の外側を読む」を追加した（§4.3.1）。起点を差分中の識別子に限定するため、§3.4 が排除した「変更文脈も全体インデックスも持たない走査」には退行しない。

この追加は precision を犠牲にしない。理由は2つある。

1. **辿った結果は反証の材料になる。** 呼び出し元を確認して初めて `failure_scenario` が書け、逆に全呼び出し元が更新済みなら候補を棄却できる。§4.3のゲートは変更していない
2. **確証を得られなかった場合の扱いを明示した。** 従来 `security.md` は認可について「確証がないなら blocking にしない」としていたが、これは**取れるはずの真陽性まで落としていた**。読んで確証を得たなら blocking にしてよく、確認できなかった場合のみ non-blocking に留める

**残る限界。** 1ホップで辿れない欠陥（設計レベルの誤り、そもそも書かれなかったコード、複数サービスをまたぐ契約違反）は依然として取りこぼす。「差分から辿れる範囲では見逃さない」までであり、「見逃さない」ではない。

### 2.5 Evaluation-Driven Development

出典: [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) / [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

公式は「**広範な文書を書く前にevalを作れ**」と明記する。手順は以下。

1. スキル無しで代表タスクを実行し、失敗を記録
2. その失敗を突く3シナリオを作成
3. ベースラインを測定
4. 最小限の記述を書く
5. 反復

本設計は§6でeval定義を先に固める。SKILL.md本体はevalを通す最小記述として書く。

---

## 3. スキル仕様

### 3.1 配置と命名

```text
.claude/skills/diff-review/
├── SKILL.md                 # 150行以内
├── reference/
│   ├── correctness.md       # 正当性・境界・並行性
│   ├── security.md          # OWASP系、認証認可、入力検証
│   ├── maintainability.md   # 重複、抽象度、命名
│   ├── tracing.md           # 差分起点の探索手順（§4.3.1で追加）
│   ├── severity.md          # 深刻度定義と分類基準
│   └── gotchas.md           # 実測された偽陽性パターン（§7.2で追記する）
└── scripts/
    └── collect_diff.sh      # 対象確定の決定論的部分
```

名前は `diff-review` とする。公式は`name`に**gerund形（`processing-pdfs`）**を推奨するが、`diff-review`は「diffのreview」という名詞句であり、公式が許容範囲として挙げる「Noun phrases: `pdf-processing`, `spreadsheet-analysis`」に該当する。コマンドとして`/diff-review`と打つ際の自然さを優先した。

`name`の制約（64文字以内、小文字・数字・ハイフンのみ、予約語`anthropic`/`claude`を含まない）はいずれも充足する（11文字）。

**`code-review`は使わない。** Claude Codeには同名のbundled skillが存在し、プロジェクトスキルがそれを置き換えてしまう。公式ドキュメントは「プロジェクトの`.claude/skills/`にある`code-review`スキルはbundled `/code-review`を置き換え、bundled alias `/review`では自分のスキルが起動しない」と明記している。既存機能を潰す衝突は避ける。

### 3.2 frontmatter

```yaml
---
name: diff-review
description: >-
  作業ツリー・ブランチ・PRの差分をレビューし、正当性・セキュリティ・保守性の
  欠陥を深刻度付きで報告する。指摘は報告前に自己反証を通し、再現可能な失敗
  シナリオを示せるものだけを残す。コードの修正は行わない。
when_to_use: >-
  「レビューして」「PRを見て」「この変更おかしくない？」「マージして大丈夫？」
  「バグがないか確認して」「差分をチェック」「review this」「check my changes」
  などで起動。コミット前、PR作成前、マージ判断前に使う。
argument-hint: "[PR番号 | ブランチ名 | パス]"
allowed-tools: Read, Grep, Glob, Bash
disallowed-tools: Edit, Write, NotebookEdit
model: inherit
---
```

各フィールドの根拠。

**`description`は三人称で what + when**。公式は「Always write in third person」と常に三人称を求め、一人称・二人称を Avoid とする（「システムプロンプトへ注入されるため、視点の不一致が発見の問題を起こす」）。

**`when_to_use`にトリガーフレーズを列挙**。これは既存の[Cookbook Harness P2](../../claude-code-cookbook-harness/README.md)で抽出済みのパターンで、Claude Codeの`when_to_use`フィールドがこの用途を公式に持つ（「トリガーフレーズや例示リクエストなど、いつ起動すべきかの追加文脈」）。

文字数上限は2つあり、別物なので区別する。

| 上限 | 対象 | 性質 |
|---|---|---|
| 1,024文字 | `description` 単体 | バリデーション上限。超えると不正 |
| 1,536文字 | `description` + `when_to_use` の合算 | skill listing での切り詰め閾値（既定値、`skillListingMaxDescChars`で変更可） |

上記の実値は `description` 102文字 + `when_to_use` 119文字 = 221文字で、いずれの上限にも余裕がある。重要な用途を先頭に置く方針は維持する。

**`disallowed-tools`でEdit/Writeを外す**。これが本設計で最も重要な1行である。理由は§3.3。

**`allowed-tools`にBashを含める**。diffの取得に必須。既存の`code-reviewer.md`も同じ判断をしており、「PHASE-9のinputsには読むべきコードと差分が実在する」と根拠を記している。

ただし **`allowed-tools`は許可リストではない。** 公式は「It does not restrict which tools are available: every tool remains callable」と明記しており、これは当該ターンで権限プロンプトを省く**事前承認**にすぎない。したがって本設計の権限拘束（§3.3）を担保しているのは`disallowed-tools`のみであり、`allowed-tools`は担保していない。この区別を取り違えると、`allowed-tools`に書かなかったツールが使えないと誤認する。

**`context: fork`は使わない。** 検討したが却下した。理由は§5.1。

### 3.2.1 配布形態の制約

上記frontmatterのうち `when_to_use` / `argument-hint` / `disallowed-tools` / `model` は **Claude Code 専用フィールド**である。Agent Skills spec が定めるのは `name` / `description` / `license` / `compatibility` / `metadata` / `allowed-tools` の6つのみで、公式は spec 外のフィールドを含めた場合「packaging or upload fails with a hard error」と明記する（無視されるのではなく失敗する）。

| 配布経路 | 可否 |
|---|---|
| Claude Code の各レベル（personal / project / plugin） | 全フィールド可 |
| claude.ai アップロード、Skills API、`package_skill.py` | **不可**（spec外フィールドでハードエラー） |
| Cowork / cloud session 用のpersonal skill 有効化 | **不可**（claude.aiへのアップロードを伴うため同じ制約） |

本スキルの「任意のリポジトリで単独動作する」（§1）という要件は、**Claude Code のスキルディレクトリへの配置を指す**。claude.ai 経由の配布は本設計の対象外とする。

これは意図した割り切りである。`disallowed-tools` は §3.3 の中核であり、これを外すと設計が成立しない。spec準拠を優先して `disallowed-tools` を諦めるより、配布経路を Claude Code に限定する方を選ぶ。

### 3.3 レビュアーは修正しない

`disallowed-tools: Edit, Write, NotebookEdit` を置く。

これは[Cookbook Harness P3（権限拘束付き専門ロール）](../../claude-code-cookbook-harness/README.md)で既に抽出済みの原則である。当該調査では「分析ロールから書込み権限を外し、実装ロールにのみEdit/Writeを与える設計が要点。ロール定義そのものが最小権限の実施点になる」と記録されている。

加えて[Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)は、禁止事項を本文の指示ではなく機構で強制せよと述べる。本文に「修正してはならない」と書いても推論で回避され得るが、`disallowed-tools`はツールプールから除去するため回避できない。

**代償**: 利用者が「ついでに直して」と言っても直せない。これは意図した挙動である。レビューと修正を同一ターンで行うと、レビュアーが自分の修正を再レビューすることになり独立性が失われる。修正が要るなら`/simplify`など別の能力へ渡す。

### 3.4 引数

| 引数 | レビュー対象 |
|---|---|
| なし | 作業ツリーの未コミット変更（`git diff HEAD`） |
| ブランチ名 | `git merge-base` 起点の差分 |
| `#123` / PR URL | `gh pr diff` の出力 |
| パス | **当該パスに触れている差分のみ**（パス配下の全体ではない） |

対象の解決は`scripts/collect_diff.sh`が担う。§2.2で述べた通り、ここは低自由度に置く。

**すべての引数形式で対象は差分に限定する。** パス指定を「配下の全体」と解釈しない。

これは§2.4の帰結である。差分レビューでprecisionが保てるのは、「変更された箇所」という強い事前情報がスコープを絞るためであり、モデルの能力によるものではない。パス配下の全体を対象にすると、この絞り込みと全体インデックスの**両方を欠いた状態**でrecall型の走査を行うことになる。§2.4がまさに「成立しない」と判定した構成である。

具体的な失敗はこうなる。`/diff-review src/` と打つと、モデルは変更文脈も全体インデックスも持たずに数百行を走査し、既存コードの意図的な設計判断（レガシー互換のための分岐、意図的に握りつぶす例外処理）を欠陥として大量に報告する。§2.3で排除しようとした偽陽性が、仕様の穴から最も出やすい経路で戻ってくる。

パス配下の全体監査が必要な場合は、本スキルの対象外とする。Step 1で対象差分が0行なら、§4.1に従って停止する。

---

## 4. レビュー手順

SKILL.md本体に記述するワークフローである。公式が推奨する**チェックリスト方式**を採る（「複雑なワークフローには、Claudeが応答へコピーして進捗を刻めるチェックリストを与えよ」）。

```text
Review Progress:
- [ ] Step 1: 対象を確定し、行数と範囲を宣言する
- [ ] Step 2: 変更意図を推定する
- [ ] Step 3: 観点別に候補を洗い出す
- [ ] Step 4: 各候補を反証する（キル・ゲート）
- [ ] Step 5: 生存した指摘のみ深刻度を付けて報告する
```

### 4.1 Step 1: 対象確定（低自由度）

`scripts/collect_diff.sh` を実行し、**レビュー範囲を明示的に宣言してから読む**。

対象が0行、または取得に失敗した場合は**そこで停止する**。推測でリポジトリ全体を読み始めてはならない。既存の`code-reviewer.md`が「fixed targetが現在対象と一致すること」を最初の確認項目に置いているのと同じ理由である。対象がずれたレビューは、正しい指摘であっても無効である。

### 4.2 Step 2: 変更意図の推定

欠陥を探す前に「この変更は何を達成しようとしているか」を1〜2文で言語化する。

これは[Deep Code Review](https://www.augmentcode.com/guides/deep-code-review-recall-vs-precision)の指摘に対応する。OWASPは「ビジネスロジックのテスト自動化は不可能、完全なビジネスプロセス知識が必須」としている。意図を取り違えたまま探索すると、仕様通りの挙動を欠陥として報告する典型的な偽陽性が生まれる。

意図が読み取れない場合は、それ自体を「意図不明」として報告に含める。推測で埋めない。

### 4.3 Step 3-4: 探索と反証（キル・ゲート）

本スキルの中核である。**探索と反証を別ステップに分ける。**

Step 3では観点別に候補を広く出す（高自由度）。ここでは偽陽性を許容する。

Step 4で各候補に対し、以下を**明示的に試みる**。

1. この指摘が誤りであるとしたら、その理由は何か
2. 実際に失敗する具体的な入力・状態を書けるか
3. 書けないなら、なぜ書けないのか

**2が書けない候補は破棄する。** これがRefute-or-Promoteの「必須の実証ゲート」に対応する。同論文は、10のレビュアーが全員一致で承認した架空の脆弱性が、実証テストのみによって排除されたと報告している。「もっともらしさ」では偽陽性は落ちない。**具体的な失敗シナリオを書けるかどうか**だけが判別に使える。

この構造は既存の[Cookbook Harness P4（Adversarial Role Debate）](../../claude-code-cookbook-harness/README.md)と発想を共有するが、適用対象が違う。P4は「設計判断を導くために対立する見解を衝突させる」もので、本スキルは「自分の指摘を自分で潰す」ものである。前者は複数ロールを要するが、後者は単一コンテキストで完結する。

### 4.3.1 Step 3の探索（改訂で追加）

シグネチャ変更・公開APIの変更・新規エンドポイント・定数の変更が差分にあれば、その識別子を起点に参照箇所を引く。手順は`reference/tracing.md`へ置き、SKILL.md本体は起点の限定と「確証を得られなければ blocking にしない」規律のみを述べる。

Step 4の実証も強化した。`failure_scenario`を書けた候補は、可能なら既存テスト・型検査・算術の検算で**実際に確かめる**。§2.3のRefute-or-Promoteが「実証ゲートのみが偽陽性を落とした」と報告している以上、推論に留めるより実測する方が原理に忠実である。ただし副作用のある実行（ネットワーク送信、ファイル書き換え、マイグレーション）は行わない。

**この追加が生む新たなリスク**は、探索が全体走査へ退行することである。§6.3にE7（負例）を置いてこれを測る。

### 4.4 Step 5: 報告

指摘1件あたりの必須要素。

| 要素 | 内容 |
|---|---|
| `file:line` | クリック可能な位置 |
| `severity` | blocking / non-blocking |
| `summary` | 欠陥の一文記述 |
| `failure_scenario` | **具体的な入力・状態 → 誤った出力・クラッシュ** |

`failure_scenario`を必須にすることで、Step 4のゲートを報告形式でも強制する。書けないものは報告に載せられない。

深刻度は2値とする。3段階以上にすると境界の議論が発生し、利用者の判断コストが上がる。判定基準は`reference/severity.md`に置く。

**指摘がゼロなら、ゼロと報告する。** 何か書かなければならないという圧力が偽陽性の主要な発生源である。

---

## 5. 却下した設計案

設計判断の記録として残す。

### 5.1 `context: fork` によるサブエージェント実行

**案**: `context: fork` を付け、独立コンテキストで実行してメインの会話を汚さない。

**却下理由**: 3点ある。

1. **会話履歴にアクセスできない。** 公式は「forkされたサブエージェントは会話履歴へアクセスできない」と明記する。レビューは直前の実装作業の文脈（何を意図して書いたか）が判断材料になる場面が多く、これを捨てる代償が大きい。
2. **既定でバックグラウンド実行になる。** `background: false`で同期にはできるが、その場合forkの利点である「並行して作業を続けられる」が消える。
3. **背景実行時はツールセットが狭まる。** 公式は「バックグラウンドのforkは、バックグラウンドサブエージェントに適用される狭いツールセットで動く」としており、Bashの可用性が読みにくくなる。

ただし理由2と3は`background: false`を明示すれば解消する（公式も「スキルの手順がそのツールセット外のツールに依存するなら`background: false`にせよ」と案内している）。したがって**実質の却下根拠は理由1に帰着する**。会話履歴を判断材料として使えるかどうかが分岐点である。

なお公式は bundled の `/code-review` 自体が v2.1.218 以降 fork 実行だと述べている。fork が一般に不適という主張ではなく、**直前の実装文脈を読む**という本スキル固有の設計選択の帰結である。

**代替**: 利用者が明示的に独立実行を望む場合は、`Agent`ツールで`Explore`エージェントへ渡す運用を案内する。スキル側の既定にはしない。

### 5.2 観点別に複数スキルへ分割

**案**: `security-review` / `perf-review` / `style-review` に分け、状況に応じて起動させる。

**却下理由**: 主たる理由は**descriptionの競合**である。分割すると各スキルの説明文が似通い、自動起動の精度が落ちる。公式は「Claudeは100以上のスキルから選ぶ」ため description が決定的だとしており、似た説明文を並べることは discovery を直接悪化させる。

副次的な理由として、観点を増やしても偽陽性は減らない。Refute-or-Promoteの事例（10のレビュアーの全員一致が架空の脆弱性を通した）が示すのは、**レビューの多重化は偽陽性を減らさない**ということである。したがって分割の便益は候補数の増加にとどまり、§2.3で見た通り問題は指摘の量ではなく質であるため、コストに見合わない。

なお「多重化が偽陽性を**増やす**」とまでは出典は述べていない。また観点別に分割したうえで各スキルへ反証ゲートを持たせる構成は理論上は成立する。それでもdescription競合の問題は残るため、本設計は分割を採らない。

また分割すると各スキルのdescriptionが競合し、自動起動の精度が落ちる。公式は「Claudeは100以上のスキルから選ぶ」ため description が決定的だとしており、似た説明文を並べるのは discovery を悪化させる。

**代替**: 単一スキル内で`reference/`を観点別に分ける（§3.1）。progressive disclosureにより、触れない観点のトークンは消費されない。

### 5.3 静的解析との統合を前提にする

**案**: DeepSourceのように決定論的な静的解析（5,000+ルール）を先に走らせ、その結果をLLMへ渡す。静的解析とLLMのハイブリッドが偽陽性を大きく削減するという報告は複数ある。

**却下理由**: 効果は認めるが、**汎用スキルの前提にできない。** 任意のリポジトリで動くことが本スキルの要件であり、特定のリンタ・型検査器の存在を仮定すると成立しない。

**代替**: SKILL.md本文で「リポジトリに設定済みのリンタ・型検査器があれば先に実行し、その出力を前提として重複指摘を避ける」と条件付きで指示する。存在しない場合も動作する。これは公式の「ツールがインストール済みと仮定するな」というアンチパターン回避にも合致する。

### 5.4 深刻度3段階（critical / major / minor）

**却下理由**: §4.4記載の通り、境界の議論コストが利益を上回る。blockingかどうかは「マージを止めるか」という単一の問いに還元でき、利用者の意思決定に直結する。

---

## 6. Eval定義

§2.5の原則に従い、SKILL.md本文より先にevalを定める。

### 6.1 評価設計の方針

出典: [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

採用した原則。

- **良いタスクの定義**: 「2人のドメイン専門家が独立に同じpass/failへ到達するもの」。曖昧な判定基準のタスクは作らない。
- **経路ではなく成果物を採点する**: 「エージェントが何を produce したかを採点せよ。どの経路を通ったかではない」。レビュー手順の遵守ではなく、報告内容を評価する。
- **正例と負例の両方**: 欠陥がある差分と、**欠陥がない差分**の両方を用意する。後者がprecisionの実測に不可欠である。
- **pass rate 0%はタスクの故障を疑う**: 「フロンティアモデルで多数試行にわたるpass rate 0%は、能力不足ではなくタスクが壊れているサインであることが多い」。
- **各タスクは複数回試行**する。1回の結果で判断しない。

### 6.2 グレーダー構成

| タスク種別 | グレーダー | 理由 |
|---|---|---|
| 既知欠陥の検出 | コードベース | 検出対象の`file:line`が一致するかで機械判定できる |
| 偽陽性の不検出 | コードベース | 指摘件数が0かで機械判定できる |
| 報告品質 | モデルベース | failure_scenarioの具体性は自然言語判定が要る |

コードベースを優先するのは、公式が「高速・安価・客観的・再現可能・デバッグ容易」と評価しているためである。判定できない部分だけモデルベースへ回す。

### 6.3 評価タスク

**正本は [`evals/tasks.jsonl`](../evals/tasks.jsonl) とする。** 本節は各タスクの狙いと設計上の位置づけを述べるにとどめ、`setup`と`expected_behavior`の全文は再掲しない。

これは意図した判断である。[Cookbook Harness P1](../../claude-code-cookbook-harness/README.md)は、同一内容を二面に持つ代償として「本文の二重管理」を明示的に警告している。設計書とJSONLへ同じJSONを二重に書くと、片方だけが更新される事故が起きる。実際、評価タスクは実使用のたびに追加される（§7.2）ため、二重管理のコストは時間とともに増える。

| ID | 種別 | 測定 | グレーダー | 狙い | 検証する設計要素 |
|---|---|---|---|---|---|
| E1 | 正例 | 検出率 | コードベース | 境界条件の欠陥を検出できるか | §4.3 Step 3、§4.4 報告要素 |
| E2 | 負例 | **precision** | コードベース | 欠陥がないとき指摘を出さずにいられるか | §2.3 precision優先 |
| E3 | 負例 | precision | モデルベース | 仕様通りの挙動を欠陥と誤認しないか | §4.2 Step 2 変更意図の推定 |
| E4 | ガードレール | 対象規律 | コードベース | 対象を取得できないとき停止できるか | §4.1 Step 1 低自由度 |
| E5 | 正例 | 検出率 | コードベース | 複数ファイルにまたがる不整合を検出できるか | §4.3.1 差分起点の探索 |
| E6 | 負例 | **反証ゲート** | モデルベース | 到達不能な候補を棄却し、棄却理由を述べられるか | §4.3 Step 4（中核機構） |
| E7 | 負例 | 対象規律 | モデルベース | 探索が全体走査へ退行していないか | §4.3.1 が生むリスク |

補足すべき2件のみ記す。

**E2 が本eval群で最も重要である。** §2.3の通り、precisionは指摘を出さない能力で決まる。欠陥のない差分に対して沈黙できないスキルは、他のすべてのタスクに通っても実用に耐えない。

**E6 は Step 4 を直接測る唯一のタスクである。** §4.3の反証ゲートは本スキルの中核だが、E1〜E5はいずれも「結果として正しい報告が出たか」しか見ないため、反証を省略して偶然正解した場合と区別できない。E6は「もっともらしいが到達不能な候補」を置き、**明示的な棄却と棄却理由**を要求することで、ゲートの実行そのものを判定する。§6.4でHaikuを重点確認するとしたのはこのタスクである。

なお E1 の境界値は `total=11, per_page=10`（正解2ページ / floor実装1ページ）とする。`total=10, per_page=10` のような割り切れる値では `ceil` と `floor` が一致し、**欠陥が発現しないためタスクとして成立しない**。§6.1の「pass rate 0%はタスクの故障を疑う」に該当する典型例であり、かつ「無理に指摘した方が受かる」というprecision優先と逆向きの圧力を生む。負例だけでなく正例でも、setupが実際に欠陥を再現するかは算術的に検算すること。

### 6.4 モデル横断テスト

公式は「使う予定のすべてのモデルでテストせよ。Opusで完璧に動くスキルがHaikuではより多くの詳細を要する場合がある」と述べる。

| モデル | 確認事項 |
|---|---|
| Haiku | 反証ゲート（Step 4）を省略していないか |
| Sonnet | 手順が明確で効率的か |
| Opus | 過剰説明になっていないか |

特にHaikuでStep 4が飛ばされないかは重点的に見る。手順の省略はprecisionの直接の劣化につながる。

### 6.5 記録する指標

| 指標 | 算出 | 目標 |
|---|---|---|
| precision | 真の指摘 / 全指摘 | 高いほど良い（主目標） |
| 偽陽性率 | E2, E3 での誤指摘率 | 0に近づける |
| 検出率 | E1, E5 での既知欠陥の検出割合 | 参考値（副目標） |
| 手順遵守 | Step 4の反証記述の有無 | 全試行で存在 |

precisionを主目標、検出率を副目標とするのは§2.4の帰結である。全体インデックスを持たない構成でrecallを追うと偽陽性が利用者へ直接届くためである。

ただし§2.4.1の改訂により、**検出率は「差分から1ホップで辿れる範囲」については向上が期待できる**。E5がこれを測る。主目標をprecisionに置く方針は変えない。改訂は「recallを追う」のではなく「確証を得る手段を与えることで、取れるはずの真陽性を落とさないようにする」ものだからである。

---

## 7. 運用と改善

### 7.1 Claude A / Claude B による反復

出典: [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

スキルを書くClaude（A）と、それを使うClaude（B）を分ける。Bの実使用での失敗をAへ持ち帰って改善する。公式は「観察に基づいて反復せよ。仮定ではなく」と述べる。

観察すべき兆候。

- Bが`reference/`のファイルを一度も読まない → 不要か、SKILL.mdでの案内が弱い
- Bが同じ参照ファイルを繰り返し読む → SKILL.md本体へ移すべき内容
- Bが想定と違う順序でファイルを読む → 構造が直感的でない

### 7.2 Ratchetパターン

出典: [Agent Harness Engineering](https://addyosmani.com/blog/agent-harness-engineering/)

**失敗するたびにルールを1つ足す。** 偽陽性が出たら、そのパターンを`reference/gotchas.md`（§3.1）へ追記し、併せて負例タスクを`evals/tasks.jsonl`へ1件足す。予測ではなく実測で堅牢化する。

`gotchas.md`は蓄積により肥大化するため、100行を超えた時点で§2.1に従い先頭へ目次を置く。

これは既存の[Change Intent Record](../../change-intent-record.md)と同じ発想である。判断の根拠を残すことで、後から検証可能にする。

### 7.3 時限情報を書かない

公式のアンチパターン。「2025年8月以前なら旧APIを使え」のような記述は必ず陳腐化する。旧仕様は`## 旧パターン`節へ`<details>`で畳んで置く。

---

## 8. 未解決事項

正直に記す。

1. **evalの実行基盤がない。** 公式も「現時点でこれらのevalを実行する組み込みの方法はない。利用者が独自の評価システムを作る必要がある」と明記している。§6の定義は仕様であり、実行スクリプトは別途要る。
2. **precisionの絶対値を目標化できない。** §6.5で「高いほど良い」としたのは、ベースライン測定前に数値目標を置くと、その数値に合わせた調整が起きるためである。E1〜E5でベースラインを取ってから設定する。
3. **静的解析との併用効果は未検証。** §5.3で条件付き指示とした部分は、実リポジトリでの効果を測っていない。

---

## 参考資料

### 一次情報（Anthropic公式）

- [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) — progressive disclosure の3段階、単一正典の原則
- [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) — 500行上限、参照1階層、degrees of freedom、eval先行、Claude A/B
- [Extend Claude with skills](https://code.claude.com/docs/en/skills) — frontmatter全フィールド、配置場所、bundled skillとの衝突、`context: fork`の制約
- [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) — グレーダー3種、良いタスクの定義、成果物採点、pass rate 0%の解釈
- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — 最小の高シグナルトークン集合、context rot
- [Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more) — 禁止は本文でなく機構で強制する
- [Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents) — 曖昧性の排除、名前空間

### 二次情報（実測・研究）

- [Refute-or-Promote (arXiv:2604.19049)](https://arxiv.org/abs/2604.19049) — 敵対的キル・ゲートで171候補の約79%を排除。10のレビュアーの全員一致が架空の脆弱性を通し、1件の実証テストのみがそれを潰した事例
- [AI Code Review Benchmark 2026](https://www.codeant.ai/blogs/ai-code-review-benchmark-results-from-200-000-real-pull-requests) — 20万件超のPRで17のAIレビュー**ツール**を評価。上位でもF1約52%（precision 52.2% / recall 51.1%）。基盤モデル単位の評価ではない点に注意
- [Deep Code Review: Why Recall Beats Precision for Agents](https://www.augmentcode.com/guides/deep-code-review-recall-vs-precision) — recall優先の3成立条件、diff限定レビューの限界、複数ファイル欠陥
- [Agent Harness Engineering](https://addyosmani.com/blog/agent-harness-engineering/) — Ratchetパターン、success silent / failures verbose

### 本リポジトリ内の関連資料

- [Cookbook Harness](../../claude-code-cookbook-harness/README.md) — P2（トリガーフレーズ列挙）、P3（権限拘束ロール）、P4（敵対的ロール議論）
- [Human Gate Policy](../../human-gate-policy.md) — リスク階層と承認対象
- [Change Intent Record](../../change-intent-record.md) — 判断根拠の記録規約
- [Development Harness](../../claude-code-development-harness/README.md) — 工程束縛型のレビューエージェント群（本スキルとは別レイヤ）
