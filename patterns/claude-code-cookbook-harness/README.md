# Claude Code Cookbook Harness

## 概要

ハーネスを「1つのワークフロー」ではなく、**再利用可能な能力の配布物（plugin）**として構成するパターンです。`wasabeef/claude-code-cookbook`（fork: `foreveryh/claude-code-cookbook`、調査時点 v3.2.0 / commit `d4a413b`）の実装から抽出しました。

既存の4方式（Micro Bugfix / Lightweight Feature / Development / Incident Response）がいずれも「1タスクをどう完遂するか」を定めるのに対し、本パターンは**それらのハーネスを構成する部品を、どう蓄積し・配布し・一貫性を保つか**を定めます。適用レイヤが異なるため、既存4方式と競合せず併用できます。

## 向いているケース

- 複数プロジェクト・複数メンバーへ、同じコマンド群とレビュー観点を配布したい
- 同じ能力を「明示呼び出し」と「自動起動」の両方で使わせたい
- レビュー観点を専門領域別に分割し、それぞれ独立したコンテキストで実行したい
- 能力の数が増えており（本事例は39コマンド+9ロール）、テンプレートと機械検証で品質を揃えたい
- 多言語・多チームへ同一構造で展開する必要がある

## 向いていないケース

- 単発タスクの遂行手順そのものを定めたい（既存4方式を使う）
- 能力が数個で、CLAUDE.mdへ直接書けば足りる
- 状態管理、品質ゲート、人間承認の設計が主目的（[Human Gate Policy](../human-gate-policy.md)と既存4方式が正本）
- 本番障害対応（[Incident Response Harness](../claude-code-incident-response-harness/README.md)へ）

## 抽出したパターン

本事例から、再利用可能な7つのパターンを抽出しました。個別の根拠と実装詳細は[設計書](docs/design.md)を参照してください。

### P1. Dual-Surface Capability（同一能力の二面公開）

1つの能力を、frontmatterなしの`commands/<name>.md`（明示的なslash command）と、`description` + `allowed-tools`付きの`skills/<name>/SKILL.md`（自動起動）の**両方**で公開します。本文は同一で、skill側にfrontmatterが加わるだけです（実測差は各ファイル8〜11行）。

利用者が名前を知っていれば`/pr-review`で確実に呼べ、知らなくても「PRをレビューして」で起動する。**発見可能性と決定性のトレードオフを、二者択一ではなく両立で解く**のが要点です。

代償は本文の二重管理です。採用する場合は、単一ソースからの生成か、後述のP6による差分検出を前提とします。

### P2. Trigger Phrase Enumeration（起動フレーズの列挙）

skillの`description`へ、抽象的な機能説明ではなく**利用者が実際に打つ言い回しを列挙**します。

```yaml
description: "ステージングされた変更からコミットメッセージを生成する。「コミットメッセージ考えて」
  「良いメッセージ生成して」「commit message を作って」「適切なコミットメッセージは？」
  「メッセージを提案して」「コミット文を書いて」「変更内容をメッセージに」などで起動。"
```

39 skill全てがこの形式を守っています。日本語・英語の混在、口語・敬体の両方、同義表現の網羅が特徴です。自動起動の精度は description の記述品質に直結するため、**起動条件を仕様として明示的に設計する**という位置づけになります。

### P3. Role as Constrained Sub-Agent（権限拘束付き専門ロール）

レビュー観点を9つの専門ロール（security, performance, analyzer, architect, frontend, backend, mobile, qa, reviewer）へ分割し、それぞれを独立したsub-agent定義とします。各ロールは3つの軸で拘束されます。

| 軸 | 内容 | 例 |
|---|---|---|
| `model` | 難度に応じたモデル割当 | analyzer/architect/security → opus、他6ロール → sonnet |
| `tools` | 責務に必要な最小ツール | security: Read/Grep/WebSearch/Glob（**書込みツールなし**） |
| 本文 | 領域固有の判断基準 | security: OWASP Top 10、CVE照合、Zero Trust |

**分析ロールから書込み権限を外し、実装ロール（backend/frontend）にのみEdit/Writeを与える**設計が要点です。ロール定義そのものが最小権限の実施点になります。モデル割当も「根本原因分析・アーキテクチャ・セキュリティは高難度」という判断をファイルへ固定しています。

### P4. Adversarial Role Debate（ロール間の対立議論）

単一の結論ではなく、**利害が対立するロールを明示的に衝突させて**トレードオフを表面化させます。`/role-debate security,performance` のように2〜3ロールを指定し、4フェーズで進行します。

1. **初期立場表明** — 各ロールが独立に推奨案と根拠を提示（相互参照なし）
2. **相互議論・反駁** — 他案への反論、見落とし指摘、トレードオフ明確化
3. **妥協点探索** — Win-Win案、段階的実装、リスク軽減策
4. **統合結論** — 合意案、ロードマップ、成功指標、将来の見直し点

論拠には公式文書・実証事例・定量評価・時系列影響が要求されます。Phase 1で独立表明を強制するのは、**先行意見への同調（anchoring）を構造で防ぐ**ためです。既存の2軸Review（code-reviewer / security-reviewer）が「独立に検査する」なら、本パターンは「独立した見解を突き合わせて設計判断を導く」点で役割が異なります。

### P5. Capability Router（状況からの能力推薦）

利用者がどの能力を使うべきか判断できない問題に対し、**対象を分析して推薦する専用能力**（`/smart-review`）を置きます。判定はファイル拡張子・パス・内容から段階的に行われます。

- `auth.js`, `.env`, `config/auth/` → security
- `*.test.js`, `__tests__/` → qa
- `api/` + `auth/` → security + architect（複合）
- スタックトレース, `crash.log` → analyzer
- `architecture-design.md`（多要素検出）→ `/role-debate architect,security,performance` を推奨

単一ロールで足りるか、複数ロール並行（multi-role）か、議論形式（role-debate）かまで含めて推薦します。**能力が増えるほど「選べない」が実際のボトルネックになる**ため、カタログの肥大化に対する構造的な対処です。

### P6. Structural Parity Validation（構造等価性の機械検証）

配布物の一貫性を人手のレビューではなくスクリプト（`scripts/check-locales.sh`）で検証します。8言語版が全て91ファイルで一致している状態を、次の検査で維持しています。

- 必須ディレクトリ・`plugin.json`・`README.md`の存在
- `plugin.json`の必須フィールドとJSON妥当性、命名規約（`cook` / `cook-<lang>`）
- 基準版（ja）とのファイル数一致、および欠落ファイルの個別列挙
- **言語混入検出** — 非日本語版に平仮名・片仮名や「です/ます/である/において」が残っていないかを検査

最後の検査が示唆的です。翻訳漏れという**「壊れていないが正しくない」状態を、機械判定可能な条件へ落とし込んでいます**。ハーネス部品が増えるほど、構造の一貫性は目視では守れません。

### P7. Autonomy Contract（自律実行の境界宣言）

CLAUDE.mdで「確認なしに即座実行してよい操作」と「確認必須の操作」を**列挙で確定**させます。

| 即座実行 | 確認必須 |
|---|---|
| バグ修正、リファクタリング | 新規ファイル作成 |
| 既存ファイルの修正・更新 | 重要ファイルの削除 |
| 依存関係の追加・更新・削除 | アーキテクチャ・フォルダ構造の大規模変更 |
| テスト実装（TDDに従う） | 新API・外部ライブラリ導入 |
| 設定値変更、フォーマット適用 | 認証・認可機能の実装 |
| ドキュメント更新（新規作成は要求時のみ） | スキーマ変更、マイグレーション、本番環境設定 |

加えて、完了報告に**判定可能な条件付きの合言葉**を置きます。「May the Force be with you.」は、全タスク完了・TODOリスト空・エラーゼロ・継続タスクなしを全て満たす場合のみ使用でき、「次のステップ」等を記述した場合は禁止されます。**完了の主張を、検証可能な単一のシグナルへ集約する**仕組みです。

なお、この境界設定は本事例の「確認は最小限に」という方針に基づくもので、依存追加やスキーマに近い変更を無確認で許す点はリスク選好が高めです。**採用時は自プロジェクトのリスク階層に合わせて再設定してください。正本は[Human Gate Policy](../human-gate-policy.md)です。**

## 補助的な構成要素

パターンとして独立させるほどではないが、実装上参考になる要素です。

- **決定論的Hook** — `PreToolUse`でファイル権限を記録し`PostToolUse`で復元する。AIの判断ではなくスクリプトで副作用を打ち消す例（ただし本実装は3秒後の再適用をバックグラウンドで行うなど、競合前提の作りになっている点は注意）。
- **denyリストによる操作禁止** — `settings.json`で`git push --force`、`git reset --hard`、`gh release create`、各種グローバルインストールなど、取り消しにくい操作を明示的に拒否する。
- **コマンドテンプレート** — `COMMAND_TEMPLATE.md`で必須セクション（タイトル/説明/使い方/基本例/Claudeとの連携/注意事項）と省略可能セクションを区別し、能力定義の書式を揃える。
- **可観測性** — statuslineでモデル名・当日コスト（ccusage）・コンテキスト使用率を常時表示。60秒キャッシュ付き。
- **conventional commits強制** — lefthook + commitlintでcommit-msgを機械検証し、git-cliffでリリースノートを自動生成する。

## 最小成果物

本パターンを採用する場合の最小構成です。

- `.claude-plugin/plugin.json` — 配布単位のメタデータ
- `commands/` と `skills/` — 二面公開する能力定義（P1/P2）
- `agents/roles/` — 権限とモデルを拘束した専門ロール（P3）
- 構造検証スクリプト — 能力定義の一貫性検査（P6）
- CLAUDE.md — 自律実行の境界宣言（P7）

P4（role-debate）とP5（router）は、ロール数・能力数が増えてから追加すれば足ります。[Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents)の「必要になるまで複雑性を増やさない」原則に従い、**P1/P3から始めることを推奨します**。

## 既存パターンとの関係

| 観点 | 既存4方式 | 本パターン |
|---|---|---|
| 定めるもの | 1タスクの遂行手順 | 能力の構成・配布・一貫性 |
| 状態管理 | checkpoint / progress / handoff | 対象外（配布物は状態を持たない） |
| 人間承認 | [Human Gate Policy](../human-gate-policy.md)が正本 | 対象外（P7は境界宣言のみ） |
| 成果物 | テスト、production code、検証証跡 | plugin配布物 |

本パターンで用意したロール（P3）を、既存4方式のレビュー工程から呼び出す形が実用的な併用方法です。ただし**既存4方式の2軸Review（code-reviewer / security-reviewer）を本パターンのロールで置き換える場合は、blocking判定とHuman Review Evidenceの要件を満たすか個別に確認してください**。本事例のロール定義にはこれらの要件がありません。

## 適用上の注意

- **本文の二重管理（P1）** — commands/skillsの本文同期は本事例では自動化されていません。採用時は生成またはCIでの差分検出を用意してください。
- **descriptionの保守（P2）** — 起動フレーズは利用実態に合わせた継続的な更新が必要です。追加漏れは「呼び出せない能力」として現れます。
- **P7のリスク選好** — 前述のとおり、そのまま採用せず自プロジェクトのリスク階層で再設定してください。
- **検証範囲（P6）** — `check-locales.sh`が検査するのは構造とファイル数であり、内容の意味的な正しさではありません。
- **本パターンは調査対象1件からの抽出です** — 一般性の裏付けは[コミュニティ実装事例調査](../../research/community-harness-implementations-2026.md)の4系統分類と併せて判断してください。

## 設計書

- [Cookbookハーネス設計書](docs/design.md)

## 参考資料

- [wasabeef/claude-code-cookbook](https://github.com/wasabeef/claude-code-cookbook) — 本パターンの抽出元（調査は fork `foreveryh/claude-code-cookbook` の commit `d4a413b`、v3.2.0 を使用）
- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents) — 必要になるまで複雑性を増やさない原則
- [Claude Code plugins](https://code.claude.com/docs/en/plugins) — plugin構造とmarketplace配布
- [Subagents](https://code.claude.com/docs/en/sub-agents) — sub-agentのmodel/tools拘束（P3の基盤）
- [Agent Skills](https://code.claude.com/docs/en/skills) — descriptionによる自動起動（P2の基盤）
- [Configure permissions](https://code.claude.com/docs/en/permissions) — allow/ask/denyによる最小権限
