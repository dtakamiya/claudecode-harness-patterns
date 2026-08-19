# Cookbookハーネス設計書

- 作成日: 2026-08-19
- 調査対象: `foreveryh/claude-code-cookbook`（`wasabeef/claude-code-cookbook` のfork）
- 固定revision: commit `d4a413b713119573fce72b49d111a1dd2bbc0b91`（2026-04-15）、marketplace version 3.2.0
- 目的: 実装から再利用可能なハーネスパターンを抽出し、各パターンの根拠・代償・適用条件を記録する

本文書の主張は上記revisionの実際のファイル内容に基づきます。以降の行数・ファイル数は当該revisionでの実測値です。

## 1. 調査対象の構造

### 1.1 全体構成

```text
claude-code-cookbook/
├── .claude-plugin/marketplace.json   # 8プラグインの配布定義
├── plugins/{ja,en,ko,zh-cn,zh-tw,es,fr,pt}/
│   ├── .claude-plugin/plugin.json
│   ├── CLAUDE.md                     # 自律実行の境界宣言（P7）
│   ├── COMMAND_TEMPLATE.md           # 能力定義の書式
│   ├── commands/*.md          (39)   # 明示呼び出し面（P1）
│   ├── skills/*/SKILL.md      (39)   # 自動起動面（P1/P2）
│   └── agents/roles/*.md       (9)   # 権限拘束付きロール（P3）
├── scripts/
│   ├── check-locales.sh              # 構造等価性検証（P6）
│   ├── preserve-file-permissions.sh  # 決定論的Hook
│   └── statusline.sh                 # 可観測性
├── settings.json                     # permissions deny + hooks + statusLine
├── .mcp.json                         # MCP サーバ定義
├── lefthook.yml / commitlint.config.js
└── .github/workflows/release.yml     # git-cliffによるリリース自動化
```

### 1.2 多言語版の位置づけ

8言語版はいずれも91ファイルで、`plugins/en` と `plugins/ja` のファイル一覧差分は空です。

```bash
diff <(cd plugins/en && find . -type f | sort) <(cd plugins/ja && find . -type f | sort)
# 出力なし
```

すなわち各言語版は構造的に同一の翻訳であり、**パターン抽出の観点では1ロケールを読めば十分**です。多言語であること自体は本パターンの本質ではなく、P6（構造等価性検証）の必要性を生んだ背景条件として扱います。本設計書は `plugins/ja` を基準に記述します。

`check-locales.sh` 内でも `ja` が基準版として扱われ、他言語は `compare_with_base` でjaと比較されます。

## 2. パターン別の根拠

### 2.1 P1: Dual-Surface Capability

#### 観測事実

39の能力それぞれが `commands/<name>.md` と `skills/<name>/SKILL.md` の2ファイルで公開されています。行数の実測は次のとおりです。

| 能力 | commands | skills | 差 |
|---|---|---|---|
| plan | 134 | 142 | 8 |
| spec | 549 | 558 | 9 |
| role-debate | 571 | 578 | 7 |
| task | 303 | 314 | 11 |
| tech-debt | 185 | 194 | 9 |

`commands/plan.md` と `skills/plan/SKILL.md` を比較すると、本文（`# 実装前の計画立案モードで戦略を策定` 以降）は完全に一致し、skill側にのみ次のfrontmatterが付きます。

```yaml
---
description: "実装前の計画立案モードを起動して詳細な実装戦略を策定する。「計画を立てて」…"
allowed-tools:
  - Read
  - Grep
  - Glob
---
```

commands側にfrontmatterは一切ありません（39ファイル中、frontmatter区切りを持つものはゼロ）。

#### 設計意図の解釈

2つの面は起動経路が異なります。

| | commands | skills |
|---|---|---|
| 起動 | 利用者が `/plan` と明示入力 | モデルがdescriptionから判断して起動 |
| 決定性 | 高い（必ず起動する） | descriptionの記述品質に依存 |
| 発見可能性 | 名前を知っている必要がある | 知らなくても起動しうる |
| ツール制約 | なし | `allowed-tools` で拘束 |

**発見可能性と決定性はトレードオフの関係にあり、片方を選ぶと他方を失います。**本事例はこれを二者択一にせず、同一本文を両面へ露出することで両立させています。

#### 代償

本文が二重管理になります。本事例では同期を保証する仕組みが**ありません**。

- `check-locales.sh` は `commands` と `agents/roles` のファイル数しか検査せず、`skills` ディレクトリを検査対象に含めていません（`REQUIRED_DIRS=("commands" "agents/roles" ".claude-plugin")`）。
- commands/skills間の本文一致を検証する仕組みは存在しません。

したがって本文の乖離は現状では検出されません。採用時は次のいずれかを前提とします。

1. 単一ソースからの生成（skillを正本とし、commandsをビルド時に生成する等）
2. CIでの差分検出（frontmatterを除いた本文のハッシュ比較）

### 2.2 P2: Trigger Phrase Enumeration

#### 観測事実

39 skill全ての `description` が「機能の説明 + 起動フレーズの列挙 + などで起動」という形式を守っています。

```yaml
# skills/commit-message/SKILL.md
description: "ステージングされた変更からコミットメッセージを生成する。「コミットメッセージ考えて」
  「良いメッセージ生成して」「commit message を作って」「適切なコミットメッセージは？」
  「メッセージを提案して」「コミット文を書いて」「変更内容をメッセージに」などで起動。
  プロジェクト規約を自動検出し、適切なメッセージを提案。"
```

列挙されるフレーズには次の特徴があります。

- **日英混在** — 「commit message を作って」「dependency を調べて」「tech debt を調べて」
- **文体の網羅** — 命令形（「直して」）、疑問形（「このエラー何？」「原因は？」）、依頼形（「レビューお願い」）
- **同義表現の展開** — fix-error は「エラーを直して」「このエラー修正して」「エラー解決して」「このエラー何？」「エラーの原因は？」「ビルドエラーを直して」「テスト失敗を解決して」の7通り
- **具体例の埋め込み** — role-debate は「セキュリティ vs パフォーマンス」という実際の対比まで含む

#### 設計意図の解釈

skillの自動起動はdescriptionのマッチングで決まるため、descriptionは**実装の説明ではなく起動条件の仕様**です。抽象的な機能説明（「コミットメッセージ生成機能」）では利用者の実際の発話と結びつきません。

`allowed-tools` との組み合わせも重要です。descriptionが「いつ起動するか」を定め、allowed-toolsが「起動後に何ができるか」を拘束します。

```yaml
# skills/commit-message/SKILL.md — 読み取り専用のgitコマンドのみ
allowed-tools:
  - Bash(git diff *)
  - Bash(git log *)
  - Read
```

`Bash(git diff *)` のようなサブコマンド単位の指定により、コミットメッセージ生成に `git commit` や `git push` は不要という判断がファイルへ固定されています。

#### 代償

descriptionは利用実態に応じた継続的な更新が必要です。列挙漏れは「存在するのに呼び出せない能力」として現れ、しかも**失敗が静かです**（エラーにならず、単に起動しない）。

### 2.3 P3: Role as Constrained Sub-Agent

#### 観測事実

9ロールのfrontmatter実測値です。

| role | model | tools | 行数 |
|---|---|---|---|
| analyzer | opus | Read, Grep, Bash, LS, Task | 267 |
| architect | opus | Read | 233 |
| security | opus | Read, Grep, WebSearch, Glob | 392 |
| backend | sonnet | Read, Glob, Edit, Write, WebSearch, Bash | 303 |
| frontend | sonnet | Read, Glob, Edit, Write, WebSearch | 294 |
| mobile | sonnet | Read, Glob, Edit, WebSearch | 309 |
| performance | sonnet | Read, Grep, Bash, WebSearch, Glob | 254 |
| qa | sonnet | Read, Grep, Bash, Glob, Edit | 266 |
| reviewer | sonnet | Read, Grep, Glob, Bash | 256 |

#### 3軸の拘束

**軸1: model割当**

opusは analyzer / architect / security の3ロールのみです。これらの共通点は次のとおりです。

- analyzer: 5 Whys、システム思考、仮説駆動、認知バイアス対策 — 因果推論
- architect: Evidence-First設計、MECE分析、進化的アーキテクチャ — 構造的判断
- security: OWASP Top 10、脅威モデリング、Zero Trust、CVE照合 — 網羅性と敵対的思考

いずれも**探索空間が広く、見落としの代償が大きい**領域です。実装系（backend/frontend/mobile）とレビュー系（reviewer/qa/performance）はsonnetに割り当てられています。この判断はロール定義ファイルへ固定されており、実行時の判断に委ねられていません。

**軸2: tools拘束（最小権限の実施点）**

書込みツール（Edit/Write）の分布が設計を明確に示します。

| 分類 | ロール | 書込み |
|---|---|---|
| 分析専門 | security, analyzer, architect, performance, reviewer | **なし** |
| 実装 | backend, frontend | Edit + Write |
| 部分実装 | mobile, qa | Editのみ（Writeなし） |

**分析ロールから書込み権限を構造的に外す**設計です。securityロールがコードを直接書き換えることはツールレベルで不可能であり、指摘の生成に専念します。architectに至っては `Read` 単独で、Grep/Globすら持ちません。

mobile/qaが `Edit` を持ち `Write` を持たない点も一貫しています。既存ファイルの修正は許すが新規ファイル作成は許さない、という粒度です。これはCLAUDE.md（P7）の「新規ファイル作成は確認必須」と整合します。

`WebSearch` は security / performance / frontend / backend / mobile に付与され、CVE照合や最新仕様の参照を想定しています。analyzerだけが `Task` を持ち、根本原因分析での再帰的な調査委譲を許しています。

**軸3: 本文の判断基準**

各ロール本文（233〜392行）は領域固有の評価基準を定義します。securityが最長（392行）である点は、網羅すべき観点（OWASP Top 10、CVE、LLM/AIセキュリティ）の多さを反映しています。

#### 既存パターンとの差分

本リポジトリの既存4方式は `code-reviewer` / `security-reviewer` による2軸Reviewを持ちます。両者の違いは次のとおりです。

| | 既存2軸Review | 本パターンのロール |
|---|---|---|
| 軸数 | 2（正確性・セキュリティ） | 9（領域別） |
| 位置づけ | 品質ゲート（blocking判定あり） | 分析能力（判定機構なし） |
| 呼出 | ワークフロー内で固定 | 利用者またはrouterが選択 |

**本パターンのロール定義にはblocking判定とHuman Review Evidenceの要件がありません。**したがって既存4方式の2軸Reviewを本パターンのロールで単純に置き換えることはできません。併用する場合は、ロールを「追加の分析観点」として使い、ゲート判定は既存の枠組みに残す形が安全です。

### 2.4 P4: Adversarial Role Debate

#### 観測事実

`skills/role-debate/SKILL.md`（578行）が定義する4フェーズ構造です。

1. **Phase 1: 初期立場表明** — 各ロールが専門視点から**独立して**意見表明。推奨案、根拠となる標準・文書、想定リスク、成功指標を提示
2. **Phase 2: 相互議論・反駁** — 他ロール提案への建設的反論、見落とされた視点の指摘、トレードオフの明確化、代替案提示
3. **Phase 3: 妥協点探索** — 各視点の重要度評価、Win-Win解決策、段階的実装アプローチ、リスク軽減策
4. **Phase 4: 統合結論** — 合意された解決策、実装ロードマップ、成功指標・測定方法、**将来の見直しポイント**

論拠の質的要件が明示されています。

- **公式文書**: 標準・ガイドライン・公式ドキュメントへの言及
- **実証事例**: 成功事例・失敗事例の具体的引用
- **定量評価**: 可能な限り数値・指標での比較
- **時系列考慮**: 短期・中期・長期での影響評価

議論倫理として「誠実性: 自身の専門分野の限界も認める」「開放性: 新しい情報・視点に対する柔軟性」が定義されています。

#### 設計意図の解釈

**Phase 1で独立表明を強制する点が構造上の要です。**先に出た意見へ後続が引きずられる（anchoring）と、形式上は議論でも実質は追認になります。独立表明を先に固定することで、対立点が確実に表面化します。

出力例では JWT有効期限を巡り、securityが「15分の短期有効期限」をOWASP JWT Security Cheat Sheet準拠として主張する具体が示されています。**単一の結論ではなく、対立とその解消過程を成果物とする**点が、通常のレビューとの違いです。

Phase 4の「将来の見直しポイント」は、決定を恒久的な正解として固定せず再評価条件を残す設計で、[Change Intent Record](../../change-intent-record.md)の「制約・不変条件」「代替案」と親和します。

#### 適用条件

トレードオフが実在する設計判断に限って有効です。正解が一意に定まる問題（バグ修正、規約準拠）には過剰であり、コストだけが増えます。

### 2.5 P5: Capability Router

#### 観測事実

`skills/smart-review/SKILL.md` の判定ロジックは3層です。

**層1: ファイル拡張子・パス**

| 条件 | 推薦 |
|---|---|
| `package.json`, `*.tsx`, `*.jsx`, `*.css`, `*.scss` | frontend |
| `Dockerfile`, `docker-compose.yml`, `*.yaml` | architect |
| `*.test.js`, `*.spec.ts`, `test/`, `__tests__/` | qa |
| `*.rs`, `Cargo.toml`, `performance/` | performance |

**層2: セキュリティ関連の検出（複合推薦）**

| 条件 | 推薦 |
|---|---|
| `auth.js`, `security.yml`, `.env`, `config/auth/` | security |
| `login.tsx`, `signup.js`, `jwt.js` | security + frontend |
| `api/auth/`, `middleware/auth/` | security + architect |

**層3: 内容ベース（エラー・問題分析）**

| 条件 | 推薦 |
|---|---|
| スタックトレース、`error.log`, `crash.log` | analyzer |
| `memory leak`, `high CPU`, `slow query` | performance + analyzer |
| `SQL injection`, `XSS`, `CSRF` | security + analyzer |

#### 実行形式の推薦

単にロールを選ぶだけでなく、**実行形式まで含めて推薦**します。

```text
$ /smart-review src/mobile/components/
→ 「📱🎨 モバイル + フロントエンド要素を検出」
→ 「[1] mobile ロール単体」
→ 「[2] frontend ロール単体」
→ 「[3] multi-role mobile,frontend」   # 並行分析
→ 「[4] role-debate mobile,frontend」  # 対立議論

$ /smart-review architecture-design.md
→ 「🏗️🔒⚡ アーキテクチャ + セキュリティ + パフォーマンス要素検出」
→ 「複雑な設計決定のため、議論形式を推奨します」
→ 「[推奨] /role-debate architect,security,performance」
```

要素が多いほど議論形式（P4）へ寄せる方針が読み取れます。エラーログ検出時は `[自動実行] /role analyzer` と、確認を挟まず起動する場合もあります。

#### 設計意図の解釈

能力が39コマンド+9ロールまで増えると、**カタログの存在自体がボトルネック**になります。利用者は「何ができるか」を把握しきれず、結果として一部の能力しか使われません。P5はこの問題に対し、選択そのものを能力化する解です。

`skills/role-help/SKILL.md`（「どのロールを使えばいい？」で起動）も同じ問題への別アプローチで、こちらは対話的なガイドです。

#### 代償

判定ロジックはハードコードされたルール列であり、能力追加のたびに更新が必要です。更新漏れは「推薦されない新能力」を生みます。

### 2.6 P6: Structural Parity Validation

#### 観測事実

`scripts/check-locales.sh`（約380行）の検査項目です。

**構造検査（`check_structure`）**

```bash
REQUIRED_DIRS=("commands" "agents/roles" ".claude-plugin")
```

各言語版でこれらのディレクトリ、`plugin.json`、`README.md` の存在を確認します。

**メタデータ検査（`check_plugin_json`）**

- `jq empty` によるJSON構文妥当性
- 必須フィールド: `name`, `version`, `description`, `author`, `repository`, `license`
- 命名規約: `ja` → `cook`、他 → `cook-<lang>`

**基準版との比較（`compare_with_base`）**

jaを基準にcommands/rolesのファイル数一致を検査し、さらに**欠落ファイルを個別に列挙**します。

```bash
for file in "$COMMANDS_DIR"/*.md; do
  basename=$(basename "$file")
  if [[ ! -f "$plugin_dir/commands/$basename" ]]; then
    print_warning "Missing in $lang: commands/$basename"
  fi
done
```

**言語混入検査（`check_language_content`）**

最も特徴的な検査です。非日本語版に対し、次を検出します。

```bash
# 平仮名・片仮名の残存
grep -l '[ぁ-んァ-ヶー]' "$plugin_dir"/**/*.md

# 日本語の文型パターン
grep -lE 'です|ます|である|により|において|について|に関して' "$plugin_dir"/**/*.md
```

zh-cn / zh-tw は漢字を共有するため文字種だけでは判定できず、**文型パターンによる二段構えの検出**を行っています。

#### 設計意図の解釈

翻訳漏れは「ファイルは存在し、構文も正しいが、内容が誤っている」状態です。これは構造検査では捉えられません。本事例は**この意味的な誤りを、機械判定可能な条件（特定文字種・文型の出現）へ落とし込んでいます**。

一般化すると、**配布物の一貫性は「壊れている / 壊れていない」の二値ではなく、「壊れていないが正しくない」状態を含む**ということです。ハーネス部品が増えるほど目視レビューは機能しなくなるため、判定可能な条件への変換が必要になります。

#### 限界

- `skills` ディレクトリが検査対象外（`REQUIRED_DIRS` に含まれない）。39 skillの欠落・不整合は検出されません。
- commands/skills間の本文一致を検査しません（P1の代償が未対処）。
- 検査するのは構造・ファイル数・言語混入であり、**翻訳内容の正しさそのものは検証しません**。

採用時は少なくともskillsを検査対象へ加え、P1の本文同期検査を追加すべきです。

### 2.7 P7: Autonomy Contract

#### 観測事実

`plugins/ja/CLAUDE.md` 冒頭の宣言です。

```markdown
**最重要**：自律的に判断・実行。確認は最小限に。
```

これを受けて、操作が2分類で列挙されます。

**即座実行（確認不要）**

- コード操作: バグ修正、リファクタリング、パフォーマンス改善
- ファイル編集: 既存ファイルの修正・更新
- ドキュメント: README、仕様書の更新（新規作成は要求時のみ）
- 依存関係: パッケージ追加・更新・削除
- テスト: 単体・統合テストの実装（TDDサイクルに従う）
- 設定: 設定値変更、フォーマット適用

**確認必須**

- 新規ファイル作成（必要性を説明して確認）
- ファイル削除（重要ファイル）
- 構造変更（アーキテクチャ、フォルダ構造の大規模変更）
- 外部連携（新API、外部ライブラリ導入）
- セキュリティ（認証・認可機能の実装）
- データベース（スキーマ変更、マイグレーション）
- 本番環境（デプロイ設定、環境変数変更）

#### 完了報告の判定条件

完了報告に条件付きの合言葉を置きます。

```text
May the Force be with you.
```

**使用条件（すべて満たす必要あり）**

- 全てのタスクが100%完了
- TODO項目が全て完了（TaskCreate/TaskUpdateで管理しているタスクリストが空）
- エラーがゼロ
- これ以上新しい指示がない限り続けられるタスクがない

**禁止事項**

- TODOリストに未完了タスクがある場合
- 「次のステップ」「残っているタスク」など継続予定の記述をした場合
- Phase や Step など段階的な作業で未完了の段階が残っている場合
- 自分の回答に具体的な残作業リストを明記した場合

#### 設計意図の解釈

**完了の主張を、検証可能な単一のシグナルへ集約する**仕組みです。「完了しました」という自然文は程度を含みますが、合言葉は二値です。しかも禁止事項が「回答内に残作業を書いたら使用不可」と定めているため、**合言葉と残作業記述は同一回答内で両立できません**。自己矛盾を構文レベルで防いでいます。

これは既存4方式の「最終回答に検証証跡を含める」要件と目的を共有しますが、アプローチが異なります。既存方式が**証跡の提示**を求めるのに対し、P7は**完了主張の形式**を拘束します。

#### 併記された開発規律

CLAUDE.mdには次も含まれます。これらは本パターン固有ではなく一般的なTDD規律です。

- TDDサイクル（Red → Green → Refactor）
- **構造変更と動作変更を同一コミットに含めない**
- コミット条件: 全テストパス、警告ゼロ、単一の論理的作業単位、明確なメッセージ
- リファクタリングは全テストが通っている状態でのみ開始、一度に一つの変更、各ステップ後にテスト実行

構造変更（Structural Changes）と動作変更（Behavioral Changes）の分離は、レビュー負荷を下げる実効性のある規律であり、[Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)と整合します。

#### リスク評価

**本事例の境界設定は、そのまま採用するにはリスク選好が高めです。**

| 項目 | 本事例 | 懸念 |
|---|---|---|
| 依存関係の追加・更新・削除 | 即座実行 | supply chain risk、破壊的更新 |
| リファクタリング | 即座実行 | 大規模な場合は波及範囲が広い |
| 設定値変更 | 即座実行 | 環境依存の挙動変化 |
| 認証・認可の実装 | 確認必須 | 妥当 |
| スキーマ変更・マイグレーション | 確認必須 | 妥当 |

高リスク側（認証、スキーマ、本番）の扱いは妥当ですが、依存関係の無確認変更は本リポジトリの既存方式より緩い設定です。既存4方式では依存追加はMicro Bugfixの適用対象外とされ、より重い方式へ昇格します。

**採用時は[Human Gate Policy](../../human-gate-policy.md)を正本とし、リスク階層に合わせて再設定してください。**P7から採るべきは境界の具体的な内容ではなく、**「境界を列挙で確定させ、完了主張を検証可能な形式へ拘束する」という手法**です。

## 3. 補助的な構成要素

パターンとして独立させるほどの一般性はないが、実装上参考になる要素です。

### 3.1 決定論的Hook

`scripts/preserve-file-permissions.sh` は、`PreToolUse` でファイル権限を記録し `PostToolUse` で復元します。

```json
"hooks": {
  "PreToolUse":  [{ "matcher": "Write|Edit|MultiEdit", "hooks": [...] }],
  "PostToolUse": [{ "matcher": "Edit|Write|MultiEdit", "hooks": [...] }]
}
```

AIの判断ではなくスクリプトで副作用を打ち消す例です。ただし実装には注意点があります。

- 復元後に**バックグラウンドで3秒待って再度chmodを実行**しており、他プロセスとの競合を前提とした作りになっています。
- 権限キャッシュを `/tmp/claude_file_permissions.txt` へ追記し、デバッグログを `/tmp/claude_permissions_debug.log` へ無制限に追記します。ローテーションがありません。
- `PreToolUse` のmatcherは `Write|Edit|MultiEdit`、`PostToolUse` は `Edit|Write|MultiEdit` と順序が異なりますが、正規表現の交替なので機能上の差はありません。

参考にすべきは「決定論的な副作用の打ち消しをHookへ追い出す」という方針であり、この実装をそのまま流用することは推奨しません。

### 3.2 denyリストによる操作禁止

`settings.json` の `permissions.deny` は、取り消しにくい操作を明示的に拒否します。

| 分類 | 例 |
|---|---|
| 破壊的ファイル操作 | `rm -rf *`（`-fr`, `-Rf`, `-r -f` 等の表記揺れも網羅）, `dd *`, `mkfs *` |
| 権限変更 | `chmod 777 *`, `chown -R *` |
| グローバルインストール | `npm install -g *`, `pip install *`, `brew install *`, `gem install *` |
| 履歴改変を伴うgit | `git push --force`, `git push -f`, `git reset --hard`, `git rebase *`, `git clean *` |
| GitHub側の破壊操作 | `gh release create/delete`, `gh repo delete`, `gh secret set/delete`, `gh workflow run` |
| シェル起動 | `bash *`, `sh *`, `sudo *` |

`rm -rf` の表記揺れを6通り列挙している点が実務的です。一方で `allow` には `Bash` が丸ごと含まれるため、**denyに列挙されていないコマンドは全て許可される**設計です。denyリスト方式は網羅性の保証が原理的に困難であり、本リポジトリの既存方式が採る allowlist（`bash-allowlist`）とは思想が異なります。

### 3.3 コマンドテンプレート

`COMMAND_TEMPLATE.md` が能力定義の書式を規定します。

- **必須**: タイトル、説明、使い方、基本例、Claudeとの連携、注意事項
- **省略可**: オプション、詳細機能、出力例、ベストプラクティス、関連コマンド

「コマンドの複雑さに応じて必要なセクションのみを使用」と明記され、単純な能力へ過剰な構造を強いない設計です。「注意事項」が必須で、**前提条件・制限事項・推奨事項**の3項目を求める点は、能力の適用範囲を明示させる効果があります。

### 3.4 可観測性

`scripts/statusline.sh` がモデル名・当日コスト・コンテキスト使用率を常時表示します。

```text
🤖 Opus | 💰 $12.34 | 📊 45.6%
```

- コストは `ccusage daily --json` から取得し、`/tmp` へ60秒TTLでキャッシュ
- コンテキスト使用率は transcript の `.jsonl` から最終 `usage` エントリを読み、`input + output + cache_creation + cache_read` の合計を `MAX_CONTEXT=160000`（200K × 0.8）で割る
- `refreshInterval: 30`（settings.json）

閾値を200Kではなく160Kに置いているのは、上限到達前に警告域へ入る余裕を持たせるためと読めます。

### 3.5 リリース自動化

- `lefthook.yml` + `commitlint.config.js` により commit-msg で conventional commits を機械検証
- `.github/workflows/release.yml` が `v*.*.*` タグで発火し、git-cliff（`.github/cliff.toml`）でリリースノートを自動生成
- `-rc` / `-beta` / `-alpha` を含むタグは自動的に prerelease として扱う

コミットメッセージの規約遵守を機械強制し、それを入力としてリリースノートを生成する連鎖です。P6と同じく「人手のレビューに依存しない一貫性維持」の思想です。

## 4. パターン間の関係

```text
                    ┌─────────────────────┐
                    │  P7 Autonomy        │  境界宣言（全体の前提）
                    │  Contract           │
                    └──────────┬──────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────▼────────┐   ┌─────────▼────────┐   ┌─────────▼────────┐
│ P1 Dual-Surface│   │ P3 Role as       │   │ P6 Structural    │
│ Capability     │   │ Constrained      │   │ Parity           │
│                │   │ Sub-Agent        │   │ Validation       │
└───────┬────────┘   └─────────┬────────┘   └──────────────────┘
        │                      │                      ▲
┌───────▼────────┐   ┌─────────▼────────┐             │
│ P2 Trigger     │   │ P4 Adversarial   │             │ 一貫性を検証
│ Phrase         │   │ Role Debate      │             │
│ Enumeration    │   │                  │             │
└───────┬────────┘   └─────────┬────────┘             │
        │                      │                      │
        └──────────┬───────────┘                      │
                   │                                  │
        ┌──────────▼──────────┐                       │
        │ P5 Capability       │───────────────────────┘
        │ Router              │
        └─────────────────────┘
```

- **P2はP1の前提** — 二面公開のskill側が機能するにはdescriptionの品質が必要
- **P4はP3の前提** — 議論するには複数の拘束済みロールが必要
- **P5はP1〜P4の帰結** — 能力が増えた結果として選択問題が発生する
- **P6はP1〜P5の全てを対象とする** — 部品が増えるほど一貫性検証が必要になる
- **P7は全体の前提** — どこまで自律に委ねるかが他の全パターンの動作条件

この依存関係から、**導入順序はP3 → P1/P2 → P6 → P4 → P5** が自然です。P7は最初に決める必要がありますが、内容は自プロジェクトのポリシーに置き換えます。

## 5. 採用判断

### 5.1 段階的導入

[Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents)の「必要になるまで複雑性を増やさない」原則に従い、次の段階を推奨します。

| 段階 | 導入するもの | 発生条件 |
|---|---|---|
| 1 | P3（ロール定義）、P7（境界宣言） | ハーネス構築の開始時 |
| 2 | P1/P2（二面公開） | 能力を明示・自動の両方で使いたくなったとき |
| 3 | P6（構造検証） | 能力数が目視で追えなくなったとき（目安10件超） |
| 4 | P4（議論） | トレードオフを伴う設計判断が繰り返し発生するとき |
| 5 | P5（router） | 利用者が能力を選べていないことが観測されたとき |

段階1のみでも有用です。P5を最初から作ると、推薦対象が少なく効果が出ないうえ保守対象だけが増えます。

### 5.2 採用時に補うべき点

本事例に不足しており、採用時に追加すべき項目です。

1. **P1の本文同期検証** — 生成またはCIでの差分検出（本事例には仕組みがない）
2. **P6のskills検査** — `REQUIRED_DIRS` へ `skills` を追加
3. **P7のリスク階層再設定** — [Human Gate Policy](../../human-gate-policy.md)を正本とする
4. **ロールとゲート判定の関係整理** — 既存2軸Reviewのblocking判定要件をロールへ持ち込むか、ゲートは既存枠組みに残すかを決める
5. **denyリストの再検討** — 本リポジトリの既存方式はallowlistであり、思想が異なる

### 5.3 一般性の限界

**本パターンは調査対象1件からの抽出です。**単一実装からの帰納であるため、次の点に留意してください。

- 7パターンのうち、公式ドキュメントで裏付けられるのはP1〜P3の基盤機能（plugin、skill、sub-agent）まで
- P4（議論）、P5（router）、P6（構造検証）は本事例固有の設計であり、他実装での有効性は未検証
- 効果の定量的な評価データはありません

[コミュニティ実装事例調査](../../../research/community-harness-implementations-2026.md)が分類する4系統（ループ型、敵対的レビュー型、チーム協調型、メタ最適化型）と照らすと、**P4は敵対的レビュー型の変種**と位置づけられます。ただし当該調査のGAN型がGeneratorとEvaluatorを分離するのに対し、P4は複数Evaluator間の対立を扱う点で異なります。

本事例はいずれの系統にも完全には該当せず、**「能力の配布物としてのハーネス」という別のレイヤ**を扱っています。この点が既存4方式と競合せず併用できる根拠です。

## 6. 参考資料

- [wasabeef/claude-code-cookbook](https://github.com/wasabeef/claude-code-cookbook) — 抽出元リポジトリ
- 調査に使用したfork: `foreveryh/claude-code-cookbook` commit `d4a413b713119573fce72b49d111a1dd2bbc0b91`（v3.2.0、2026-04-15）
- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents) — 複雑性の段階的導入
- [Claude Code plugins](https://code.claude.com/docs/en/plugins) — plugin構造とmarketplace配布
- [Subagents](https://code.claude.com/docs/en/sub-agents) — model/tools拘束（P3の基盤）
- [Agent Skills](https://code.claude.com/docs/en/skills) — descriptionによる自動起動（P2の基盤）
- [Configure permissions](https://code.claude.com/docs/en/permissions) — allow/ask/denyによる最小権限
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide) — 決定論的な自動化
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html) — 構造変更と動作変更の分離
- [Human Gate Policy](../../human-gate-policy.md) — 人間承認の正本（P7はこれに従属）
- [Change Intent Record](../../change-intent-record.md) — 設計意図の記録規約（P4 Phase 4と関連）
