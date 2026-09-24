# Claude Code ハーネスにおける工程別コンテキスト設計ガイド

- 調査日: 2026-09-04
- 対象: Claude Codeを使うソフトウェア開発ワークフロー
- 目的: 探索・要件定義・設計・実装・TDD・レビュー・デプロイ/インシデント対応の各工程で、何を「コンテキスト」として用意すべきかを整理する
- 関連資料: 本調査はハーネス全体の設計原則を扱う[claude-code-development-harness-patterns.md](claude-code-development-harness-patterns.md)を前提とし、「コンテキスト」というテーマだけを深掘りする。実装例は[claude-code-development-harness](../patterns/claude-code-development-harness/)の`context-builder.md`と`docs/design.md`を参照する。

## 結論

1. コンテキストウィンドウは「有限で貴重なリソース」であり、トークンを追加するたびに機会費用が発生する。長くなるほど関連情報を見つける精度が落ちる**context rot**が起きるため、目標は「情報を増やすこと」ではなく「望む結果の実現確率を最大化する最小限の高シグナル・トークン集合を見つけること」である。
2. Claude Codeは、常時ロード（CLAUDE.md）・トリガー時ロード（Skills）・独立コンテキスト（Subagents）・実行時取得（just-in-time探索、MCP）・外部永続化（メモリ、状態ファイル）という異なる特性を持つ複数のコンテキスト供給手段を持つ。工程ごとに適した手段を選ぶことが設計の核心である。
3. 工程が進むほど「正本とすべき入力」は絞られていく。探索は広く読んで要約する工程、実装以降は上流工程が確定した成果物（要件・設計・ADR）だけを権威ある入力とし、会話の要約を正本にしない。
4. 長時間・複数セッションにまたがるハーネスでは、compaction（要約圧縮）・structured note-taking（外部メモリへの記録）・sub-agent分離という3技法を併用し、状態を会話履歴ではなく外部ファイル（handoff、progress.yaml、context manifest）に持たせる。
5. このリポジトリの`claude-code-development-harness`は上記の考え方を先取りして実装しており、`context-builder.md`が生成するcontext manifest（authoritative_inputs / discovery_roots / access_policy / context_budget）が、以下の工程別ガイドの実装例として機能する。

## 調査方法

- Anthropic公式Engineering Blog（"Effective context engineering for AI agents"、"Equipping agents for the real world with Agent Skills"）と、Claude Code公式ドキュメント（`code.claude.com/docs/en/`配下のmemory, skills, sub-agents, hooks, context-window, permission-modes, mcp, best-practices）を優先ソースとした。
- 本リポジトリ内の`patterns/claude-code-development-harness/docs/design.md`（§3.1〜§3.6, §8, §9, §10, 付録D.6）、および`context-builder.md`テンプレートから、工程別コンテキスト設計の具体実装例を抽出した。
- `patterns/claude-code-incident-response-harness`, `claude-code-micro-bugfix-harness`, `claude-code-lightweight-feature-harness`の各design.mdから、規模の異なるハーネスでのコンテキスト運用の違いを補助的に確認した。
- 製品仕様は更新されるため、実装時はリンク先の最新版と利用中のClaude Codeバージョンを再確認する。

## 1. コンテキストエンジニアリングの一般原則

### 1.1 有限なリソースとしてのコンテキストウィンドウ

Anthropic公式ブログは、context engineeringを「プロンプトエンジニアリングの自然な延長」と位置づける。プロンプトエンジニアリングが「指示の書き方」を扱うのに対し、context engineeringは「推論の各ステップでモデルに渡す最適なトークン集合をキュレーションし続ける戦略」である。LLMは「注意力の予算（attention budget）」を持ち、トークンを追加するたびにそれを消費する——これは人間の限定的な作業記憶になぞらえられる。したがって規律の本質は「情報を追加すること」ではなく「最小限の高シグナル・トークン集合を見つけること」にある。

出典: [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

### 1.2 Context Rot（コンテキストの劣化）

コンテキストウィンドウ内のトークン数が増えるほど、モデルがそこから情報を正確に想起する能力が低下する現象。Transformerは全トークンペア間のn²の関係を学習するため、コンテキストが長くなるほどこの関係性が「薄く引き伸ばされる」。学習データの分布や長文対応のための位置エンコーディング補間も、劣化に寄与する。性能低下は崖のような急落ではなく緩やかな「性能勾配」として現れ、needle-in-a-haystack型ベンチマークで確認されている。

出典: [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

### 1.3 コンテキストを構成する要素ごとの設計原則

| 要素 | 原則 |
|---|---|
| System prompt | 「right altitude（適切な高度）」——ハードコードされた複雑なロジックと、曖昧すぎる抽象指示の両極端を避け、期待挙動を導くのに十分具体的かつ柔軟性を残す。XML/Markdownでセクション分けし、テスト駆動で最小情報集合から段階的に拡張する |
| Tools | 理解しやすく機能重複が最小限。自己完結的・エラーに頑健・用途が明確。人間の設計者が明確に選べないツールセットはLLMにも扱えない |
| Few-shot examples | あらゆるエッジケースを列挙する「洗濯物リスト」を避け、多様で正準的な例を少数キュレーションする |
| Message history | 「informative, yet tight（情報豊富かつ引き締まっている）」を維持する |

出典: [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

### 1.4 Just-in-Time vs 事前ロード

- **Just-in-Time**: 軽量な識別子（ファイルパス、保存済みクエリ）を保持し、実行時にツールで動的にロードする。人間の認知に近く、ストレージ効率が良いが、実行時探索は遅く、設計が悪いとツールの誤用やデッドエンドでコンテキストを浪費する。
- **事前ロード**: 高速だがインデックスが陳腐化するリスクがある。
- **推奨はハイブリッド**: 一部データ（例: CLAUDE.md）は即座にロードし、残りはglob/grepなどエージェントの裁量で動的探索させる。Claude Code自身がこの設計を採用している。

出典: [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

### 1.5 長期タスク向け3技法

| 技法 | 内容 | 適用対象 |
|---|---|---|
| Compaction（圧縮） | 上限に近づいた会話を要約し、その要約で新しいコンテキストウィンドウを再初期化する。アーキテクチャ上の決定・未解決バグ・実装詳細を保持し、冗長なツール出力を破棄する。まず再現率を最大化し、そこから精度を高める方向で選別する | 広範な往復を要するタスク |
| Structured note-taking（構造化メモ） | コンテキストウィンドウ外の永続メモリ（To-doリスト、NOTES.md、memory tool）へ定期的に書き込み、後で読み戻す。コンテキストがリセットされても継続できる | 明確なマイルストーンを持つ反復的開発 |
| Sub-agent architectures（サブエージェント分離） | 専門化されたサブエージェントがクリーンなコンテキストウィンドウで焦点を絞った作業を行い、凝縮された要約（多くは1,000〜2,000トークン）のみを返す。詳細探索コンテキストはサブエージェント内に隔離される | 並列探索が有効な複雑なリサーチ・分析タスク |

出典: [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

API層でも同種の機構（`clear_tool_uses_20250919`, `clear_thinking_20251015`）がベータ提供されており、compactionと組み合わせるとピークトークン数が実測で約半減した例が報告されている。

出典: [Context editing - Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/context-editing), [Context engineering: memory, compaction, and tool clearing | Claude Cookbook](https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools)

## 2. Claude Codeにおけるコンテキスト供給手段

| 手段 | ロードタイミング | 特性 | 適した用途 |
|---|---|---|---|
| CLAUDE.md | セッション開始時に自動読込（システムプロンプト後のユーザーメッセージとして配信） | 常時消費。200行未満推奨。組織/ユーザー/プロジェクト/ローカルの4階層が連結される | コードから推測できない事実（ビルド/テストコマンド、規約、アーキテクチャ判断） |
| `.claude/rules/` | `paths` frontmatterに合致するファイルを触れた時にオンデマンド読込 | CLAUDE.mdをトピック・パスで分割しノイズを減らす | パス限定の規約 |
| Skills（SKILL.md） | 常時は`name`/`description`のみプリロード、関連性判断後に本文をロード（progressive disclosure） | 「手順」に育った知識の置き場所。500行未満推奨、詳細は別ファイルに分離 | 定型手順、チェックリスト、レビュー基準 |
| Subagents | 呼び出し時に独立したコンテキストウィンドウで起動 | メイン会話の履歴・出力スタイル・auto memoryを引き継がない（`context: fork`除く）。`tools`/`disallowedTools`でスコープ制限可能 | 大量出力を伴う調査、独立性が必要なレビュー、並列実行 |
| Auto memory | `MEMORY.md`は起動時に先頭200行/25KBロード、個別トピックはオンデマンド | Claude自身が学習を書く。CLAUDE.mdと役割分担（既述内容や導出可能な内容は書かない） | セッションをまたぐ学習・フィードバックの蓄積 |
| Hooks | ツールライフサイクルの特定時点で決定論的に実行 | 「コンテキストであり強制ではない」CLAUDE.mdと対比され、Hooksは"deterministic and guarantee the action happens" | アクセス制御の実効的強制（manifestの宣言をACLに変換する層） |
| MCP | サーバー接続時。ツールスキーマは既定で遅延ロード | 外部システム（イシュートラッカー、監視ダッシュボード）の標準化された取り込み口。出力が閾値超過でファイル参照化 | チャットへのコピペを置き換える外部データ連携 |
| Context compaction | コンテキストが上限（Sonnet 5既定で約967Kトークン付近）に近づくと自動発動 | プロジェクトルートのCLAUDE.mdは生存、ネストしたCLAUDE.mdは再ロードされない。CLAUDE.mdの「Compact Instructions」節または`/compact <instructions>`で誘導可能 | 長時間セッションの継続 |
| 外部状態ファイル（handoff, progress.yaml, context manifest） | エージェントが明示的に読み書き | 会話に依存しない永続化。session跨ぎの正本 | 複数セッション・複数エージェントにまたがるハーネス |

出典: [How Claude remembers your project](https://code.claude.com/docs/en/memory), [Agent Skills](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview), [Create custom subagents](https://code.claude.com/docs/en/sub-agents), [Automate workflows with hooks](https://code.claude.com/docs/en/hooks), [Explore the context window](https://code.claude.com/docs/en/context-window), [MCP](https://code.claude.com/docs/en/mcp)

Subagentsの使い分けについて公式ガイダンスは明確な基準を示す。サブエージェントを使うべきなのは「タスクが冗長な出力を生みメインコンテキストに残す必要がない」「特定のツール制限を強制したい」「自己完結的でサマリだけ返せる」場合。メイン会話を使うべきなのは「頻繁な往復や反復的調整が必要」「計画・実装・テストが大きくコンテキストを共有する」「レイテンシが重要」な場合。

出典: [Create custom subagents](https://code.claude.com/docs/en/sub-agents)

## 3. SDLC工程別ガイド

各節は「用意すべきコンテキスト」「正本とすべき情報源」「除外すべき情報」「このリポジトリ内の関連実例」の順で整理する。工程名は`claude-code-development-harness`のPHASE-0〜PHASE-10に大まかに対応させている。

### 3.1 探索（Explore）

- **用意すべきコンテキスト**: CLAUDE.md（規約・コマンド）、対象領域のディレクトリ構造、類似実装、既存テスト。大きなファイルは全文ではなくGrep/Globでシンボル・範囲を先に特定する。
- **正本**: リポジトリそのもの（コード・テスト・git履歴）。会話要約を正本にしない。
- **除外すべき情報**: 無関係な機能領域のソース、`docs/archive/**`、秘密情報（`.env`, `secrets/**`）。
- **実践上の注意**: 探索はコンテキストを最も消費しやすい工程であるため、公式ベストプラクティスは「サブエージェントを使って調査をメインコンテキストの外に出す」ことを明示的に推奨している（"Since context is your fundamental constraint, use subagents to keep research out of it"）。探索範囲を絞らない「infinite exploration」は典型的な失敗パターンとして名指しされている。
- **関連実例**: このリポジトリの4ハーネス全てが`Explore`サブエージェントをread-only調査専任として切り出している（`claude-code-lightweight-feature-harness/docs/design.md` §2〜3、`claude-code-micro-bugfix-harness/docs/design.md` §2〜3）。`context-builder.md`のAgentも、Phase開始時にmanifestの`discovery_roots`を決める前段としてこの探索原則を踏襲する。

出典: [Claude Code best practices](https://code.claude.com/docs/en/best-practices)

### 3.2 要件定義

- **用意すべきコンテキスト**: ステークホルダー入力、既存のプロダクト仕様・baseline、受け入れ基準のたたき台。
- **正本**: 前工程の承認済み成果物（baseline）とステークホルダーの直接入力。曖昧な場合は推測せず選択肢を提示してユーザーに確認する（AskUserQuestionに相当する運用）。
- **除外すべき情報**: 実装詳細、コード構造（この段階ではまだ関係が薄い）。
- **実践上の注意**: 受け入れ条件は後工程（TDD）でテストへ変換される前提のコンテキストであるため、「観測可能な条件」として書く（`claude-code-lightweight-feature-harness`のIntake最小形式が好例）。
- **関連実例**: `claude-code-development-harness/docs/design.md` PHASE-1 inputs = `baseline, stakeholder-input`。軽量ハーネスのIntake（目的・受入条件・対象外・想定範囲を1画面に収める）。

### 3.3 設計

- **用意すべきコンテキスト**: 承認済み要件、ADR（Architecture Decision Record）、既存アーキテクチャ・コーディング規約。
- **正本**: 承認済み要件（approved-requirements）と直前フェーズのADR。設計判断は会話の中だけに留めず、ADRとして正本化する。
- **除外すべき情報**: 未承認の代替案の詳細（結論だけ残し、検討過程は必要なら別文書に追い出す）。
- **実践上の注意**: ADRと未解決事項は「必ずコンテキストに含める」べき情報として`context-builder.md`のコンテキスト選定原則に明記されている。漏らすと同じ議論・同じ指摘が再発する。
- **関連実例**: `claude-code-development-harness/docs/design.md` PHASE-3基本設計 inputs = `approved-requirements`、PHASE-4詳細設計 inputs = `basic-design, ADR`。

### 3.4 実装計画・タスク分割

- **用意すべきコンテキスト**: 詳細設計、対象コンポーネントの既存コード構造。
- **正本**: 承認済み詳細設計。
- **除外すべき情報**: 他コンポーネントの設計（`excluded_from_context`で明示除外する）。
- **実践上の注意**: この段階で初めて`context-builder.md`のようなcontext manifestを組成し、次工程（実装）のエージェントに「読んでよい範囲」「書いてよい範囲」を明示する価値が最大化する。
- **関連実例**: `claude-code-development-harness/docs/design.md` PHASE-5実装計画 inputs = `detailed-design`。

### 3.5 実装・TDD

- **用意すべきコンテキスト**: タスク計画、テスト計画、**context manifest**（authoritative_inputs / discovery_roots / access_policy / context_budget）、対象コンポーネントのソースとテスト。
- **正本**: `context-builder.md`が編成したmanifestの`authoritative_inputs`。会話の要約や記憶に頼らず、manifestに列挙された文書だけを起点に作業する。
- **除外すべき情報**: manifestの`excluded_from_context`と`access_policy.denied`（`.env`, `secrets/**`）。他タスクの設計文書。
- **実践上の注意**:
  - TDDは「REDをproduction code変更前に確認する」という手順自体がコンテキストの一部であり、`GREEN_CONFIRMATION`のような明示的な状態名がハーネス間で共通言語として機能する。
  - Just-in-Timeの原則が最も活きる工程。CLAUDE.mdやmanifestの`authoritative_inputs`は事前ロードし、コード内の依存関係はGrep/Globで実行時に辿る。
  - 大きい機能実装は、単一セッションのコンテキストを使い切る前に「増分実装と構造化handoff」でセッションを区切る（`claude-code-development-harness-patterns.md` パターン6を参照）。
- **関連実例**: `claude-code-development-harness/docs/design.md` PHASE-7 inputs = `task-plan, test-plan, context-manifest`（唯一context-manifestを明示的にinputsへ含むフェーズ）。`context-builder.md`のYAMLテンプレート全体。

### 3.6 レビュー

- **用意すべきコンテキスト**: 固定された対象（commit SHAまたはbase_oid + diff_hash）、テスト証跡、対象コードのみ。設計意図・ADRへの参照（なぜその変更をしたか）。
- **正本**: レビュー開始前に固定したcommit/diffのハッシュ。「レビュー完了時点のcommit SHAまたは成果物ハッシュを記録し、レビュー後の変更による陳腐化を検知する」ことが`design.md`付録D.6で明示される。
- **除外すべき情報**: レビュー対象外の変更、レビュー中に加えられた新たな変更（レビュー中の変更は禁止し、修正はImplementerへ差し戻して対象を再固定する）。
- **実践上の注意**: 公式ベストプラクティスは「フレッシュなサブエージェントコンテキストでdiffのみをレビューさせるadversarial review」を推奨する。実装を行った文脈をそのまま引き継ぐと自己の誤りに気づきにくいため、レビューは独立したコンテキストで行うことに意味がある。
- **関連実例**: 全ハーネス共通の2軸レビュー（Code Reviewer / Security Reviewer / Human Reviewer）は、レビュー対象を`commit_oid`または`base_oid + diff_hash`で固定してからread-onlyで評価する設計（`claude-code-micro-bugfix-harness/docs/design.md` §8、`claude-code-lightweight-feature-harness/docs/design.md` §7）。

出典: [Claude Code best practices](https://code.claude.com/docs/en/best-practices)（Add an adversarial review step節）

### 3.7 デプロイ・インシデント対応

- **用意すべきコンテキスト**: 通常デプロイは、全アーティファクト・トレーサビリティ・レビュー結果の集約（完了監査）。インシデント対応は、メトリクス・ログ・トレース・変更履歴・依存状態をread-onlyで収集した「証拠」。
- **正本**: インシデント対応では`incident-state.yaml`が single source of truth。timeline/evidence/action_proposals/approvals/executions/rollbacksは追記専用（既存entryを更新・削除しない）。
- **除外すべき情報**: 監視アラート・ログ・trace・ticket・chat・外部ページの本文はprompt injectionを含み得る不信頼入力として扱い、必要fieldだけを構造化抽出して制御文字・markup・秘密値を無害化する。token・password・cookie・credential・個人情報・機密payload・プロンプト本文は既定で記録しない。
- **実践上の注意**: インシデント対応は「証拠と仮説を区別する」「観測データ単独を本番操作の承認根拠にせず、別の信頼できる指標または人間の確認と突合する」という、コンテキストの信頼性そのものを疑う運用が特徴的。復旧後はtimelineと証拠を固定し、非難を目的としない事後分析へ渡す。恒久修正は通常の開発ハーネスへ別taskとして戻す。
- **関連実例**: `claude-code-incident-response-harness/docs/design.md` §7状態ファイル、§8 Handoffと事後分析。`claude-code-development-harness/docs/design.md` PHASE-10完了監査 inputs = `all-artifacts, traceability, reviews`。

### 3.8 工程をまたぐ永続化（Handoff / progress.yaml）

工程間は会話の要約だけでつながず、標準化されたハンドオフ文書を作成する。次工程のエージェントはハンドオフに列挙された権威ある入力だけを起点に作業する。必須項目は「完了/未完了作業」「権威ある成果物」「確定判断とADR」「制約・禁止事項・スコープ外」「未解決事項とblocking判定」「次実行可能タスク」。

`progress.yaml`はDevelopment Orchestratorのみがsingle writerとなり、楽観ロック（`expected_previous_revision`）とatomic renameで競合・破損を防ぐ。「次のContinuation Agentが会話履歴なしで再開できる」ことが、セッションまたぎ設計の完了条件として明記されている。

出典: `patterns/claude-code-development-harness/docs/design.md` §3.2, §9, §10

## 4. 落とし穴と対策

| 落とし穴 | 内容 | 対策 |
|---|---|---|
| Kitchen sink session | 1つの会話に無関係なタスクを詰め込み続ける | タスクの切れ目で`/clear`する |
| Correcting over and over | 同じ誤りを2回訂正しても直らない | 2回失敗したら`/clear`して、根本原因を含めた新しいプロンプトで再開する |
| Over-specified CLAUDE.md | CLAUDE.mdが肥大化し、実際の指示が埋もれる | 各行について「これを削除したらClaudeが間違えるか」を自問し、Noなら削除する |
| Trust-then-verify gap | エージェントの報告を検証せずに完了扱いする | 検証コマンドを実行し出力を確認してから完了と報告する |
| Infinite exploration | スコープを絞らない調査でコンテキストを埋め尽くす | 探索はサブエージェントに切り出し、範囲（"quick"/"medium"/"very thorough"）を明示する |
| Context rot | コンテキストが長くなるほど関連情報の想起精度が落ちる | 高シグナルな情報だけを厳選し、compaction・structured note-taking・sub-agent分離で外部化する |
| Stale index / stale context | 事前ロードした情報や、固定したはずのレビュー対象が後から変化する | レビューはcommit SHA/diff hashで対象を固定し、変更後は再固定してから再検証する（design.md付録D.6） |
| 会話要約を正本化する | 会話の要約に頼ると、手戻り時に一次情報を失う | authoritative_inputsを明示的なファイルパスとして持ち、会話履歴を正本にしない |
| manifestの宣言と実効制御の乖離 | access_policyを書いただけで安全と誤認する | permissions/PreToolUse Hookへ変換して強制し、宣言と実効の一致を機械確認する（design.md §14.3） |

出典: [Claude Code best practices](https://code.claude.com/docs/en/best-practices)（失敗パターン集）、`patterns/claude-code-development-harness/docs/design.md`

## 5. 参考リンク一覧

### Anthropic公式（Context Engineering / Agent Skills）

- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

### Claude Code公式ドキュメント

- [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- [How Claude remembers your project（Memory）](https://code.claude.com/docs/en/memory)
- [Agent Skills](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
- [Create custom subagents](https://code.claude.com/docs/en/sub-agents)
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks)
- [Explore the context window](https://code.claude.com/docs/en/context-window)
- [Permission modes（Plan Mode）](https://code.claude.com/docs/en/permission-modes)
- [Model Context Protocol (MCP)](https://code.claude.com/docs/en/mcp)
- [Configure permissions](https://code.claude.com/docs/en/permissions)

### Claude Platform Docs / Cookbook

- [Context editing - Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/context-editing)
- [Context engineering: memory, compaction, and tool clearing | Claude Cookbook](https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools)

### 本リポジトリ内の関連実装

- [patterns/claude-code-development-harness/docs/design.md](../patterns/claude-code-development-harness/docs/design.md) §3.1〜§3.6（十層モデル、Context Builderアーキテクチャ、Permission Boundary）、§8（エージェント設計）、§9（ハンドオフ設計）、§10（状態管理）、付録D.6（並列レビュー安全策）
- [patterns/claude-code-development-harness/templates/agents/context-builder.md](../patterns/claude-code-development-harness/templates/agents/context-builder.md)
- [patterns/claude-code-incident-response-harness/docs/design.md](../patterns/claude-code-incident-response-harness/docs/design.md)
- [patterns/claude-code-micro-bugfix-harness/docs/design.md](../patterns/claude-code-micro-bugfix-harness/docs/design.md)
- [patterns/claude-code-lightweight-feature-harness/docs/design.md](../patterns/claude-code-lightweight-feature-harness/docs/design.md)
- [research/claude-code-development-harness-patterns.md](claude-code-development-harness-patterns.md)（ハーネス全体の設計原則、本調査の前提資料）
