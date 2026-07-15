# Claude Code 開発ハーネスの再利用可能な設計パターン調査

- 調査日: 2026-07-15
- 対象: Claude Codeを使うソフトウェア開発ワークフロー
- 目的: プロジェクトや技術スタックをまたいで再利用できるハーネス設計の抽出

## 結論

再利用しやすい開発ハーネスは、巨大な万能プロンプトではなく、次の責務を分離した小さな部品の組み合わせとして設計するのがよい。

1. `CLAUDE.md` / `.claude/rules/`: 常時必要なプロジェクト規約
2. Skills: 必要なときだけ読み込む再利用可能な手順・知識
3. Subagents: 独立コンテキストで行う調査、実装、レビュー
4. Hooks / permissions / sandbox / CI: LLMの判断に依存させない制御
5. Git、タスク一覧、進捗・handoffファイル: セッションをまたぐ外部状態
6. テスト、ブラウザ操作、評価基準: 完了を観測可能にするフィードバック

最初は単一セッションの「探索 → 計画 → 実装 → 検証」から始め、長期化、並列化、高リスク化した場合だけSubagent、worktree、外部状態、Evaluatorを追加する。モデル能力やClaude Codeの機能が向上したら、各部品が現在も必要かを評価し、1つずつ削減する。

## 調査方法

- Anthropicの公式Claude Codeドキュメント、公式Engineering記事、公式GitHubリポジトリを優先した。
- コミュニティ由来のパターンは、公式資料が同じ原則を裏付ける場合のみ補助的に扱った。
- 製品仕様は更新されるため、実装時はリンク先の最新版と利用中のClaude Codeバージョンを再確認する。

## パターン一覧

| # | パターン | 解決する問題 | 主な実装手段 |
|---|---|---|---|
| 1 | 薄い常設コンテキスト | 指示の肥大化と遵守率低下 | `CLAUDE.md`, `.claude/rules/` |
| 2 | オンデマンド手順 | 専門手順による常時コンテキスト消費 | Skills |
| 3 | Explore → Plan → Implement → Verify | 早すぎる実装と手戻り | Plan mode, tests, build |
| 4 | 決定論的品質ゲート | 自己申告による誤完了 | tests, lint, typecheck, CI, Hooks |
| 5 | 専門Subagentと独立Evaluator | コンテキスト汚染と自己評価バイアス | custom subagents, review criteria |
| 6 | 増分実装と構造化handoff | 長期タスクの迷走と早期完了 | task list, progress file, Git |
| 7 | 最小権限と多層防御 | 誤操作、prompt injection、情報流出 | permissions, sandbox, Hooks |
| 8 | worktreeによる変更隔離 | 並列編集の衝突 | Git worktrees, `isolation: worktree` |
| 9 | Tool Gateway | 外部ツールの過剰公開 | MCP, agent別tool制限 |
| 10 | ハーネス自体のEvals | 改善・劣化を感覚で判断 | task, trial, grader, outcome |
| 11 | 能力連動の段階的簡素化 | 過剰なオーケストレーション | 段階導入、ablation、計測 |
| 12 | Pluginによる配布 | リポジトリ間の設定複製と更新漏れ | plugin manifest, marketplace |
| 13 | Headless実行契約 | CI・定期処理の非対話実行 | `claude -p`, structured output |

## 1. 薄い常設コンテキスト

### ねらい

全セッションで必要な不変ルールだけを`CLAUDE.md`へ置き、局所ルールを`.claude/rules/`へ分離する。長い手順書や参照資料を常時読み込ませない。

### 実装要点

- `CLAUDE.md`にはビルド・テストコマンド、主要ディレクトリ、禁止事項、完了条件を具体的に書く。
- 目安として各`CLAUDE.md`を200行未満に保つ。
- パス固有の規約は`.claude/rules/`で対象ファイルへスコープする。
- `@path` importは整理には役立つが、起動時コンテキストの削減にはならない。
- 規約は行動を誘導するだけで強制ではない。必須制約はpermissions、sandbox、Hooks、CIへ移す。

### 適用判断

- ほぼすべてのリポジトリで最初に導入する。
- 同じ指摘が繰り返されたら常設ルール化し、特定作業だけの複数ステップ手順はSkill化する。

出典: [How Claude remembers your project](https://code.claude.com/docs/en/memory), [Extend Claude Code](https://code.claude.com/docs/en/features-overview)

## 2. オンデマンド手順をSkillにする

### ねらい

デプロイ、DB migration、セキュリティレビューなど、反復するが毎回は使わない作業を自己完結したSkillとして再利用する。

### 実装要点

- 1 Skill = 1つの明確な責務とし、発動条件をdescriptionへ具体的に書く。
- `SKILL.md`から必要なscript、template、referenceを参照し、手順と資産を同梱する。
- 副作用のあるSkillは`disable-model-invocation: true`で自動発動させず、ユーザー明示実行に限定する。
- Skillは既定では主会話の文脈でinline実行される。隔離が必要なら`context: fork`と必要に応じた`agent`指定、または独立Subagentを選ぶ。
- チーム配布が必要なSkills、agents、hooks、MCP設定はpluginとして束ねる。

### 適用判断

- 2回以上繰り返す手順、チェックリスト、成果物テンプレートに向く。
- 一度しか使わない単純な指示をSkill化しない。

出典: [Agent Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview), [Skills](https://code.claude.com/docs/en/slash-commands), [anthropics/skills](https://github.com/anthropics/skills), [Extend Claude Code](https://code.claude.com/docs/en/features-overview)

## 3. Explore → Plan → Implement → Verify

### ねらい

未知のコードベースで、理解不足のまま実装を始めることを防ぐ。調査の出力を実装範囲と検証方法へ変換してから編集する。

### 実装要点

1. Explore: 規約、関連コード、類似実装、テスト、実行コマンド、git状態をread-onlyで確認する。
2. Plan: 受入条件、変更対象、対象外、テスト方法を小さな項目にする。
3. Implement: 一度に1つの検証可能な変更を行う。
4. Verify: テスト、型検査、lint、build、必要なら実UI操作を実行する。

計画は成果物や検証方法を固定し、詳細な実装を早期に決めすぎない。上流計画の誤りが下流へ連鎖するのを避けるためである。

### 適用判断

- 局所的な1行修正を除く、未知または複数ファイルの変更に適用する。
- 仕様が曖昧なら実装せず、観測可能な受入条件を先に確定する。

出典: [Best practices for Claude Code](https://code.claude.com/docs/en/best-practices), [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## 4. 決定論的品質ゲート

### ねらい

「正しそう」「完了した」というモデルの判断を、終了コードや観測結果で置き換える。

### 実装要点

- 受入条件ごとに、テスト、静的解析、API応答、スクリーンショットなどの検証手段を割り当てる。
- production codeより先に失敗するテストを作り、RED → GREENを確認する。
- Hooksはformat、保護ファイル検査、Stop時の検証など、決定論的な規則だけに使う。
- 最終ゲートはCIでも再実行し、ローカル会話だけを証拠にしない。
- リポジトリ内のHookや設定はAgent自身が変更できる可能性があるため、それ単独を信頼境界にしない。制御ファイルを書込み対象外にし、CODEOWNERS等でレビューし、信頼済みCIで再検証する。
- UIはコードやunit testだけで完了判定せず、ブラウザを人間と同じ経路で操作する。
- テスト削除、assertion弱体化、エラー抑制を「修正」として許可しない。

### 適用判断

- 全変更で最低1つの自動検証を用意する。
- 主観品質は評価基準を分解し、独立Evaluatorへ渡す。

出典: [Best practices for Claude Code](https://code.claude.com/docs/en/best-practices), [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide), [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

## 5. 専門Subagentと独立Evaluator

### ねらい

調査ログで主コンテキストを埋めず、作成者の自己評価バイアスを分離する。

### 実装要点

- Exploreはread-only、Reviewerは原則read-only、Implementerだけに対象範囲の書込みを許す。
- 各Subagentへ目的、入力、対象範囲、禁止事項、返却形式を短く明示する。
- `tools` / `disallowedTools` / `permissionMode` / `maxTurns` / `skills` / `mcpServers` / `isolation`で能力と入力を必要最小限にする。
- Evaluatorには「良いか」ではなく、受入条件、境界値、回帰、セキュリティ、実UI操作など具体的な判定基準を与える。
- GeneratorとEvaluatorの間は、契約、レビュー結果、修正結果を構造化ファイルで受け渡す。
- 単純な作業まで分業しない。委譲のtoken、latency、調整コストを上回る場合だけ使う。

### 適用判断

- 広い探索、並列化、異なるツール・権限、独立レビューが必要な場合に向く。
- 現行モデルが単独で安定して解ける範囲ではEvaluatorが過剰コストになる可能性がある。

出典: [Create custom subagents](https://code.claude.com/docs/en/sub-agents), [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## 6. 増分実装と構造化handoff

### ねらい

複数コンテキスト・複数セッションにまたがる作業で、一括実装、途中状態の放置、早すぎる完了宣言を防ぐ。

### 実装要点

- 初回Initializerが環境起動script、機能一覧、baseline、初期進捗を作る。
- 継続Agentは毎回、作業ディレクトリ、git log/status、進捗、未完了機能、baselineを確認する。
- 一度に1機能だけ選び、テスト後に状態を更新する。
- handoffには完了項目、変更ファイル、実行コマンドと結果、未解決事項、次の1手を記録する。
- 会話履歴ではなく、Gitとリポジトリ内の構造化成果物を正本にする。
- 完了状態は自由文だけでなくJSON/YAML等の機械検査可能な形式にする。
- handoff、task、transcriptへsecretを保存せず、外部入力はschema検証し、ログはredaction・保存期限・アクセス範囲を定める。

### 適用判断

- 1セッションに収まる作業では不要。長期化が判明した時点で追加する。
- compactionで安定する場合は継続セッションを優先し、不安定化した場合だけ明示的なcontext resetとhandoffを使う。

出典: [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## 7. 最小権限と多層防御

### ねらい

モデルの誤判断やprompt injectionが起きても、アクセス可能範囲と被害半径を小さく保つ。

### 実装要点

- permissionsのdenyで秘密情報、credential、本番操作へのアクセスを拒否する。
- sandboxでBashと子プロセスのfilesystem/networkをOSレベルで制限する。
- 外部通信、push、release、migration、破壊操作は明示承認を要求する。
- Hook scriptは入力を検証し、変数をquoteし、固定パスを使い、secretをstdoutへ出さない。
- `CLAUDE.md`の禁止指示をセキュリティ境界として扱わない。
- CI tokenやMCP credentialは、必要なAgentと工程だけへスコープする。
- 保護ブランチはGit hosting側のbranch protection / rulesetで強制し、ローカルpermissionsやHookで代替しない。
- sandboxはBashと子プロセスが主対象であり、他toolやMCPを一律に隔離しない。filesystem/networkは既定拒否とallowlistを基本にし、例外を個別監査する。
- Hookは任意コード実行面でもあるため、導入・更新時に内容と呼出先をレビューし、timeout、入力サイズ上限、fail-closed条件を定義し、`eval`を避ける。

### 適用判断

- 全ハーネスの基盤として導入する。
- 自律時間、外部接続、扱うデータの機密性が増すほど境界を狭くする。

出典: [Configure permissions](https://code.claude.com/docs/en/permissions), [Sandboxing](https://code.claude.com/docs/en/sandboxing), [Making Claude Code more secure and autonomous with sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)

## 8. worktreeによる変更隔離

### ねらい

複数セッションやSubagentの並列編集を別checkoutへ隔離し、同じ作業ツリーでの上書きや競合を防ぐ。

### 実装要点

- 独立タスクごとに`claude --worktree`またはSubagentの`isolation: worktree`を使う。
- 各worktreeで依存関係と開発環境を初期化する。
- gitignoredな非機密ローカル設定のコピーは`.worktreeinclude`で明示できるが、secretは原則コピーせず、必要時に短命credentialを実行時注入する。
- 共有DB、port、cache、生成物など、filesystem外の競合もAgentごとに分離する。
- merge前に各ブランチの検証とレビューを独立実行する。
- worktreeは編集衝突を避ける機能であり、セキュリティ境界ではない。同じGit metadataとユーザー権限を共有するため、未信頼コードや異なる権限を隔離する場合は別container/VM、credential、DB namespaceを使う。

### 適用判断

- 依存しないタスクの並列化に向く。
- 同じファイルや同じ設計判断へ集中するタスクは直列化する。

### 並列方式の選択

| 方式 | 向く用途 | 注意点 |
|---|---|---|
| Subagent | 調査、レビュー、自己完結した委譲 | 独立コンテキスト。必要なら`isolation: worktree`を指定 |
| 複数worktree session | 人が監督する独立変更 | task管理と統合は利用者側で行う |
| Agent teams | shared task listとAgent間通信が必要な協調 | experimentalで高token。各teammateは同じ作業ディレクトリを共有し得るため、編集競合を別途防ぐ |
| `/batch` | 多数の独立作業をworktreeへfan-out | 共通設計判断や同一ファイルの変更には不向き |

安定性を優先する場合はSubagentまたは明示的worktreeを基本とし、Agent teamsは協調通信の価値が追加コストを上回る場合だけ評価する。

出典: [Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees), [Create custom subagents](https://code.claude.com/docs/en/sub-agents), [Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams)

## 9. MCPをTool Gatewayとして扱う

### ねらい

Issue tracker、ブラウザ、DB、監視などの外部能力を、用途と権限を限定した明示的な境界から提供する。

### 実装要点

- built-in toolsで足りる場合はMCPを追加しない。
- 読取りと更新を別toolにし、更新系は確認や承認を要求する。
- Agentごとに必要なMCP serverだけを公開する。
- tool inputをschemaで制約し、外部から取得した文字列を信頼済み指示として扱わない。
- 接続先、認証、監査ログ、timeout、失敗時の再試行方針を定義する。
- MCPは能力を提供し、Skillはその能力を使う手順を提供するものとして分ける。
- MCP serverと依存関係は配布元を確認してversion/digestを固定し、egressと子process権限を制限する。credentialを引数・ログへ出さず、更新toolはidempotency key等で再試行時の重複を防ぐ。

出典: [Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp), [Extend Claude Code](https://code.claude.com/docs/en/features-overview)

## 10. ハーネス自体をEvalsで評価する

### ねらい

prompt、Skill、Agent構成、Hook、モデルを変更した際に、改善と回帰を再現可能に判断する。

### 実装要点

- 実タスクから小さな評価suiteを作り、入力と成功条件を固定する。
- 出力文章ではなく、テスト結果、生成ファイル、DB状態、UI操作結果などのoutcomeを採点する。
- 1回の成功で判断せず、複数trialの成功率、コスト、latency、介入回数を測る。
- 決定論的graderを優先し、主観評価には基準を与えた独立LLM graderと人間校正を併用する。
- transcriptを保存し、失敗を「探索」「計画」「tool利用」「検証」「handoff」へ分類する。
- ハーネス部品を1つずつ外すablationで、実際に必要な部品を特定する。

出典: [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents), [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents)

## 11. 能力連動の段階的簡素化

### ねらい

モデルの弱点を補うために追加した構造が、モデル更新後も残り続けることを防ぐ。

### 実装要点

- 各部品について「どの失敗を防ぐか」「効果を測る指標」を記録する。
- モデルやClaude Code更新時にeval suiteを再実行する。
- sprint、context reset、Evaluatorなどを1つずつ外し、品質、コスト、時間を比較する。
- タスク難度に応じて、Evaluatorを毎工程、最後だけ、なし、から選ぶ。
- 最も単純な構成を既定にし、観測された失敗にだけ対策を足す。

Anthropicの2026年3月の事例では、Sonnet 4.5からOpus 4.5への移行でcontext resetを削除し、さらにOpus 4.6でsprint分割を削除できた一方、Plannerと難しい領域のEvaluatorは価値を維持した。したがって、特定のAgent数やループ回数を固定的なベストプラクティスと見なすべきではない。

出典: [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps), [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents)

## 12. Pluginによる配布とバージョン管理

### ねらい

安定したSkills、Subagents、Hooks、MCP設定を、複数リポジトリやチームへ同じ単位で配布する。

### 実装要点

- まず単一リポジトリの`.claude/`で検証し、再利用性が確認できてからPluginへ昇格する。
- manifestの必須項目に加え、version、description等の任意metadataも定義し、変更履歴と互換性を管理する。
- Plugin固有のパスを使い、利用側リポジトリのディレクトリ構造へ暗黙に依存しない。
- 組織固有設定やcredentialをPluginへ埋め込まず、環境変数や利用側設定から注入する。
- 更新前後にharness evalsを実行し、破壊的変更はmajor versionとして扱う。

### 適用判断

- 3つ以上のリポジトリで同じ構成を複製し始めた段階が目安となる。
- プロジェクト固有規約はPlugin化せず、各リポジトリの`CLAUDE.md` / Rulesに残す。

出典: [Create plugins](https://code.claude.com/docs/en/plugins), [Extend Claude Code](https://code.claude.com/docs/en/features-overview)

## 13. Headless / CIの再現可能な実行契約

### ねらい

PRレビュー、定期調査、自動修正候補作成などを、対話UIに依存せず同じ入力・権限・出力形式で実行する。

### 実装要点

- `claude -p`へ、目的、入力、変更可能範囲、成功条件、失敗時動作を自己完結したpromptとして渡す。
- 許可toolを明示し、追加権限が必要ならfail closedとする。承認を回避する危険なpermission bypassを使わない。
- `--allowedTools`でtoolを限定し、`--output-format json --json-schema`等の構造化outputで後続CI stepが結果を機械判定できるようにする。
- 書込みを伴う場合は一時branch/worktree、最小権限token、timeout、コスト上限を設定する。
- `--max-budget-usd`等で実行コストにも上限を設ける。
- Claudeの文章上の成功宣言ではなく、後続の決定論的CI stepで成果物を再検証する。
- fork PR、Issue本文、checkoutしたコード、MCP出力は未信頼入力として扱う。`pull_request_target`等で未信頼コードとwrite token/secretsを同じjobへ置かず、読取り・解析jobと特権更新jobを分離する。
- CI Actionはcommit SHAへ固定し、可能ならOIDCの短命credentialとenvironment approvalを使い、secretをログへ出さない。

### 適用判断

- 入力と成功条件を事前に固定できる反復タスクに向く。
- 要件確認や高リスク承認が途中で必要な作業は対話セッションに残す。

出典: [Run Claude Code programmatically](https://code.claude.com/docs/en/headless), [GitHub Actions](https://code.claude.com/docs/en/github-actions)

## 推奨リファレンス構成

```text
repository/
├── CLAUDE.md                    # 短い全体規約と検証コマンド
├── .claude/
│   ├── rules/                   # パス別規約
│   ├── skills/                  # 再利用手順・script・template
│   ├── agents/                  # Explore / Implement / Review
│   ├── hooks/                   # 決定論的な検査script
│   └── settings.json            # permissions / sandbox / hooks
├── docs/
│   ├── requirements/            # 受入条件
│   ├── decisions/               # ADR
│   ├── tasks/                   # 機械可読な状態を含む作業一覧
│   └── handoffs/                # セッション間の引継ぎ
├── scripts/
│   ├── setup                    # 再現可能な環境初期化
│   └── verify                   # test/lint/typecheck/buildの統一入口
└── evals/
    ├── tasks/                   # 代表タスク
    ├── graders/                 # outcome判定
    └── baselines/               # 成功率・コスト・latency
```

すべてを最初から作る必要はない。導入順序は次を推奨する。

1. Level 1: `CLAUDE.md` + 既存テスト/CI
2. Level 2: `.claude/rules/` + 再利用Skill + permissions/sandbox
3. Level 3: Explore/Review Subagent + UI/APIのend-to-end検証
4. Level 4: task/progress/handoff + Initializer/Continuation
5. Level 5: worktree並列化 + MCP境界 + harness evals
6. Level 6: Plugin配布 + Headless/CI自動化

## アンチパターン

- 万能な巨大`CLAUDE.md`: tokenを常時消費し、重要な指示が埋もれる。
- promptだけの強制: 禁止操作や必須テストをモデルの遵守に依存する。
- 検証不能な完了条件: 「品質が高い」「適切に実装」だけで判定する。
- 自己レビューだけ: 作成時の前提と見落としをそのまま再利用する。
- 一括実装: 中断時に未完了状態と意図を復元できない。
- Subagentの乱用: 単純タスクでcontext転送と調整コストだけが増える。
- 共有作業ツリーでの並列編集: 差分の所有者と検証結果が不明になる。
- Hooksへの業務判断の埋込み: debuggingが難しく、意図しない副作用を生む。
- worktreeをsandboxとして使う: Git metadataとユーザー権限を共有するため、未信頼コードを隔離できない。
- MCPの全Agent公開: credentialと外部更新権限の被害半径が広がる。
- 固定されたハーネス: 古いモデルの弱点を補う複雑性が残り続ける。

## 採用チェックリスト

- [ ] 受入条件は観測可能か
- [ ] `CLAUDE.md`は短く、具体的で、矛盾がないか
- [ ] 局所手順はRulesまたはSkillsへ分離されているか
- [ ] 必須制約はpermissions、sandbox、Hooks、CIで強制されているか
- [ ] 各工程に実行可能な検証があるか
- [ ] Subagentの責務、入力、権限、終了条件が限定されているか
- [ ] 長期作業を会話なしで再開できるhandoffがあるか
- [ ] 並列タスクのfilesystemと外部resourceが隔離されているか
- [ ] 外部toolは最小権限でAgent別に公開されているか
- [ ] ハーネス変更を比較できるevalとbaselineがあるか
- [ ] 現在のモデルに不要な構造を定期的に削除しているか

## 主要参考資料

- [Claude Code: Best practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code: Extend Claude Code](https://code.claude.com/docs/en/features-overview)
- [Claude Code: How Claude remembers your project](https://code.claude.com/docs/en/memory)
- [Claude Code: Create custom subagents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code: Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide)
- [Claude Code: Configure permissions](https://code.claude.com/docs/en/permissions)
- [Claude Code: Sandboxing](https://code.claude.com/docs/en/sandboxing)
- [Claude Code: Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees)
- [Claude Code: Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams)
- [Claude Code: Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp)
- [Claude Code: Create plugins](https://code.claude.com/docs/en/plugins)
- [Claude Code: Run Claude Code programmatically](https://code.claude.com/docs/en/headless)
- [Anthropic Engineering: Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic Engineering: Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Anthropic Engineering: Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents)
- [Anthropic Engineering: Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Anthropic GitHub: Agent Skills](https://github.com/anthropics/skills)
