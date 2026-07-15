# Claude Code ハーネス: コミュニティ実装事例からの再利用可能パターン調査

- 調査日: 2026-07-15
- 対象: 実際のOSSリポジトリ、公式plugin、学術研究で観測されたClaude Codeハーネス実装
- 目的: 公式ドキュメントの推奨事項ではなく、**実際に動いている実装**から再利用可能なパターンを抽出する
- 関連資料: [claude-code-development-harness-patterns.md](claude-code-development-harness-patterns.md)（公式ドキュメント中心の13パターン網羅調査）。本ファイルはその補完として、コミュニティ・学術研究発の具体的な実装を扱う。

## 結論

2026年時点でGitHub上に多数の「Claude Codeハーネス」を名乗るリポジトリが存在するが、実装は概ね次の4系統に収斂する。

1. **ループ型（Ralph Wiggum系）**: Stop Hookでセッション終了を横取りし、同じプロンプトを再投入して自律的に反復させる。最小構成で始められるが、暴走コストの制御が必須。
2. **敵対的レビュー型（GAN-style）**: Generator（実装）とEvaluator（採点）を別コンテキスト・別エージェントに分離し、両者が「完了」の定義に事前合意してから作業を始める。
3. **チーム協調型（Agent Teams）**: 複数セッションが共有タスクリストを介して対話しながら並列作業する。experimental機能であり、同一ファイルへの同時書込みや`/resume`非対応など運用上の制約が多い。
4. **メタ最適化型（Meta-Harness / Harness Evolver）**: ハーネス自体（プロンプト、ルーティング、検索戦略）をLLM自身に探索・改善させる、まだ研究段階のパターン。

学術研究側では「同一モデルでもハーネス設計だけで性能が最大6倍変わる」（Lee et al., Meta-Harness, 2026）、「Claude Codeのコードベースの98.4%は決定論的インフラで、AI判断ロジックは1.6%にすぎない」（VILA-Lab, Dive into Claude Code, 2026）という2つの知見が、公式ドキュメントの主張（「制御は極力コードとpermissionに追い出し、モデルには狭い自由度だけを与える」）を裏付けている。

## 調査方法

- GitHub検索（`gh search repos` 相当のWeb検索）で"claude code harness"を名乗る実装を横断的に収集した。
- 公式`anthropics/claude-code`リポジトリ内のplugin実装（Ralph Wiggum）をソースとして直接確認した。
- 2026年公開のarXiv論文・ブログ分析（Meta-Harness、Dive into Claude Code）を一次情報として参照した。
- スター数や更新頻度による品質保証はできていないため、採用前に各リポジトリのライセンス・メンテナンス状況・実行内容を個別に確認すること。

## パターン一覧

| # | パターン | 由来 | 解決する問題 | 再利用時の主な注意点 |
|---|---|---|---|---|
| 1 | Stop Hookループ（Ralph Wiggum） | 公式plugin / Geoffrey Huntley発案 | 対話1往復ごとの手動再指示が必要 | 暴走コスト、`--max-iterations`必須 |
| 2 | GAN型 Generator/Evaluator | コミュニティ複数実装 | 自己レビューの評価甘え | 「完了」の事前合意、敵対性の設計 |
| 3 | Agent Teams（実験的） | 公式機能 | 独立サブエージェント間の対話不足 | ファイル競合、`/resume`非対応 |
| 4 | Meta-Harness / Harness Evolver | 学術研究の実装移植 | ハーネス自体の手動チューニングの限界 | 実験的、評価コストが高い | 
| 5 | Verb分割型ハーネス | コミュニティ実装（plan/work/review/sync/release） | 単一巨大promptの責務混在 | verbごとの入出力契約の明文化 |
| 6 | リポジトリ内蔵Eval監査 | コミュニティ実装 | ハーネス構成要素の要否を主観判断 | 6軸ルーブリック等、採点基準の明文化 |

## 1. Stop Hookループ（Ralph Wiggum技法）

### 由来と仕組み

2025年7月にGeoffrey Huntleyが提唱し、2026年にAnthropic公式リポジトリの`plugins/ralph-wiggum/`として同梱された。名前は『ザ・シンプソンズ』のラルフ・ウィグムに由来し、「うまくいかなくても繰り返し試行する」という思想を表す。

最小形は単なるbashの`while true`ループだが、Claude Code公式実装ではセッション内で完結する形に再設計されている。

```bash
/ralph-loop "REST APIをCRUD+バリデーション+テスト付きで実装。
完了したら <promise>COMPLETE</promise> を出力。" \
  --completion-promise "COMPLETE" \
  --max-iterations 50
```

動作原理:
1. Claudeがタスクに取り組み、終了しようとする
2. `hooks/stop-hook.sh`が終了をインターセプトし、同じプロンプトを再投入する
3. 直前の変更はファイルシステムに残っているため、各反復は前回の続きから始まる
4. `--completion-promise`で指定した文字列が完全一致で出力されるまで繰り返す
5. `--max-iterations`到達で強制停止する

### 安全機構と注意点

- `--max-iterations`は事実上の予算制御であり、必ず設定する。複雑なコードベースで50反復回すと$50〜100規模のAPIコストになり得る。
- completion promiseは完全一致判定のため、複数の完了条件（例:「テストが通り、かつlintも通る」）を1つの文字列に畳み込む必要がある。
- 向く用途: グリーンフィールドの新規実装、TDDで機械的に検証可能なタスク、明確な成功基準があるタスク。
- 向かない用途: 人間の判断が必要なタスク、成功基準が曖昧なタスク、本番環境の直接デバッグ。
- 実績として、契約開発案件を$50,000相当の見積もりから$297のAPI費用で完成させた例や、Y Combinatorハッカソンで一晩に6リポジトリを生成した例が報告されている。ただしこれらは自己申告のケーススタディであり、再現性の検証は行っていない。

### 既存パターンとの関係

本リポジトリの「6. 増分実装と構造化handoff」（[claude-code-development-harness-patterns.md](claude-code-development-harness-patterns.md)）と同じ問題意識だが、Ralph Wiggumはより攻撃的に「人間の介在なしで完了まで回す」ことに振り切っている点が異なる。長時間の無人運転を許容できるリスク許容度と予算がある場合にのみ検討する。

出典: [anthropics/claude-code: plugins/ralph-wiggum/README.md](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md), [Awesome Claude: Ralph Wiggum Loop for Claude Code](https://awesomeclaude.ai/ralph-wiggum), [The Register: 'Ralph Wiggum' loop prompts Claude to vibe-clone software](https://www.theregister.com/2026/01/27/ralph_wiggum_claude_loops/)

## 2. GAN型 Generator/Evaluator ハーネス

### 由来と仕組み

GAN（敵対的生成ネットワーク）の考え方をエージェント設計に転用したパターンで、複数の独立実装が確認できる（`coleam00/adversarial-dev`、`FlineDev/TandemKit`など）。Claude Agent SDK製の実装もあり、単一ツールに依存しない設計思想として定着しつつある。

構成要素:
- **Generator**: 仕様に従って実装する。
- **Evaluator**: 実際に動いているアプリケーションをPlaywright等で操作し、ルーブリックに従って採点し、具体的な改善フィードバックを返す。
- **Planner**（実装によっては存在）: 1行プロンプトを機能一覧・スプリント・評価基準を含む仕様書に展開する。

### 実装要点

- **事前契約が必須**: Generator と Evaluator が「完了」の定義に実装前に合意していないと、Generatorは自分が良いと思う基準で最適化し、Evaluatorは別の基準で採点するというすれ違いが起きる。
- Evaluatorは「Generatorより厳しくあるべき」という設計原則がある。単純な相互チェックではなく、意図的な敵対性を作る。
- 品質ゲートは各ステップに配置し、最終レビューだけに集約しない。
- Playwright等でUIを実際に操作して評価する実装が複数観測された。これは本リポジトリの既存原則（「UIはコードやunit testだけで完了判定せず、ブラウザを人間と同じ経路で操作する」）と一致する。

### 適用判断

- 主観的な品質基準（UI/UX、コード品質全般）を要するタスクに向く。
- 明確な自動テストだけで判定できるタスクでは、Evaluator専任コストが過剰になる可能性がある。

出典: [coleam00/adversarial-dev](https://github.com/coleam00/adversarial-dev), [FlineDev/TandemKit](https://github.com/FlineDev/TandemKit), [celesteanders/harness](https://github.com/celesteanders/harness), [claudeskills.info: Gan Evaluator subagent](https://claudeskills.info/subagents/gan-evaluator/)

## 3. Agent Teams（実験的公式機能）

### 由来と仕組み

Subagentが「委譲して結果を待つだけ」の一方向モデルであるのに対し、Agent Teamsは複数のClaude Codeセッションが対等に対話し、共有タスクリストを介して協調する。1セッションがteam leadとして作業を割り振り、teammateは独立したコンテキストウィンドウを持ちながら互いに直接通信する。

有効化には環境変数`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`が必要で、名称の通り実験的機能である。

### 実装要点とコミュニティの知見

- **タスクグラフを先に描く**: 3本以上の独立した並列トラックを具体的に説明できない場合、単一セッションの方が速い。
- **同一ファイルへの同時割当を避ける**: マージ競合と無言の上書きの最大の原因。同じコンポーネントを触る作業は直列化する。
- **トークンコスト**: 3-teammate構成は同じ作業を単一セッションで逐次行う場合の約3〜4倍のトークンを消費する。時間短縮効果がコストを上回るかを事前に見積もる。
- **既知の制約**: `/resume`や`/rewind`はin-processのteammateを復元しない。セッション再開後、team leadが存在しないteammateへメッセージを送ろうとする不具合が報告されている。

### 既存パターンとの関係

本リポジトリの「8. worktreeによる変更隔離」で整理した並列方式比較表のうち、「Agent teams」行の内容を実運用知見で裏付ける。安定性を優先するならSubagentまたは明示的worktreeを既定とし、Agent Teamsは協調通信の価値が追加コスト（トークン3〜4倍、実験的機能特有の不具合）を上回る場合のみ採用する、という既存の判断基準は現時点でも妥当と考えられる。

出典: [Claude Code Docs: Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams), [claudefa.st: Agent Teams Best Practices & Troubleshooting](https://claudefa.st/blog/guide/agents/agent-teams-best-practices), [MindStudio: Agent Teams vs Sub-Agents](https://www.mindstudio.ai/blog/claude-code-agent-teams-vs-sub-agents)

## 4. Meta-Harness / ハーネス自己最適化（研究段階）

### 由来

Stanford発の論文 *Meta-Harness: End-to-End Optimization of Model Harnesses*（Lee et al., 2026, arXiv:2603.28052）が、ハーネス設計そのものを探索問題として定式化した。これをClaude Code plugin化した実装（`001TMF/harness-forge`、`raphaelchristi/harness-evolver`）が公開されている。

### 仕組み

- 高性能なLLMエージェント（Claude Code自身）に、候補ハーネス群（プロンプト、ルーティング、検索戦略、コンテキスト構成）を読ませ、新しい候補を提案させる。
- 提案されたハーネス候補を「制約ゲート」「効率ゲート（マージ前のコスト/latency確認）」「回帰ガード」「Pareto選択」「holdout強制」「レート制限による早期中断」「停滞検出」という多段の審査にかける。
- 最終出力は単一の「最良ハーネス」ではなく、性能とコストのトレードオフを示すPareto frontier上の候補群。
- 論文の中心的主張: 同一モデルでもハーネス設計だけでベンチマーク性能が最大6倍変わり得る。

### 適用判断

- 2026年7月時点では研究・実験段階のパターンであり、本番運用実績は限定的と見られる。
- 評価に要する計算コストが大きい（論文では1ステップあたり最大1000万トークン規模の探索）。個人開発や小規模チームでの直接採用は現実的でない可能性が高い。
- 実用上の示唆としては、「ハーネスの各要素を固定ベストプラクティスとせず、計測しながら入れ替える」という考え方自体は、本リポジトリの既存パターン「11. 能力連動の段階的簡素化」と方向性が一致する。Meta-Harnessはこれを人手ではなく自動化しようとする試みと位置づけられる。

出典: [Yoonho Lee: Meta-Harness paper](https://yoonholee.com/meta-harness/paper.pdf), [arXiv:2603.28052](https://arxiv.org/pdf/2603.28052), [001TMF/harness-forge](https://github.com/001TMF/harness-forge), [raphaelchristi/harness-evolver](https://github.com/raphaelchristi/harness-evolver)

## 5. Verb分割型ハーネス（plan/work/review/sync/release）

### 由来

`Chachamaru127/claude-code-harness`など複数の実装が採用する構成で、ハーネスを「フォルダに置かれたプロンプト集」ではなく「ワークフローシステム」として設計する考え方。CLAUDE.md/AGENTS.mdのような最上位指示ファイルが共通の振る舞いを定め、個々のSkillが作成・デバッグ・ガバナンス・レポーティングといった役割に特化する。

### 実装要点

- 作業を5つの動詞（plan, work, review, sync, release）に分解し、各動詞に対応する薄いSkillを用意する。
- Anthropicのlong-running agent向けガイダンスと、Manusスタイルの永続的markdown計画ファイルを組み合わせた実装（`oeftimie/vv-claude-harness`）も観測された。バージョンを重ねてAgent Teamsのプリミティブ上に構築されたplugin形態へ進化した例がある。
- 「計画がチャットの中だけで生き、テストが任意になり、レビューが手遅れのタイミングで行われ、リリース証跡が記憶頼みで再構築される」というドリフトを防ぐことが動機として明示されている。

### 適用判断

本リポジトリの`patterns/`配下にある3パターン（development harness、lightweight feature harness、micro bugfix harness）は、複雑度に応じてこのverb分割をどこまで明示化するかを段階分けしたものと解釈できる。verb分割型は本リポジトリの`claude-code-development-harness`パターンと同系統だが、コミュニティ実装では「sync」（外部状態との同期）を独立verbとして切り出している点が特徴的であり、複数セッション・複数人での利用を前提にした設計思想が伺える。

出典: [Chachamaru127/claude-code-harness](https://github.com/Chachamaru127/claude-code-harness), [oeftimie/vv-claude-harness](https://github.com/oeftimie/vv-claude-harness), [hoangnb24/repository-harness](https://github.com/hoangnb24/repository-harness)

## 6. リポジトリ内蔵Eval監査（Agentic-Readiness監査）

### 由来

`affaan-m/everything-claude-code`（ECC）のようなSkill集約リポジトリで観測された手法で、保有するSkillやAgent定義を6軸ルーブリックで採点し、"HARNESS-READY" "LOOP-CAPABLE" "TOOL-ONLY" "PROSE-ONLY"のような段階にラベル付けする。2026年7月時点の監査例では、対象群のうちHARNESS-READYは26件、LOOP-CAPABLEは39件、TOOL-ONLYは43件、PROSE-ONLYは7件という分布が報告されている。

### 実装要点

- 「文章で手順を書いただけ（PROSE-ONLY）」から「決定論的ループに組み込める（LOOP-CAPABLE）」「ハーネスとして自律運用できる（HARNESS-READY）」まで段階を明示し、Skill/Agentの成熟度を可視化する。
- 大量のSkillを保有するリポジトリほど、個々の資産が実際に自律実行に耐えるかを定期監査する必要性が高まる。

### 既存パターンとの関係

本リポジトリの「10. ハーネス自体のEvals」で述べたablationや成功率計測の考え方を、Skill/Agentポートフォリオ全体に対して定期的に適用する運用例として位置づけられる。個別タスクのeval suiteだけでなく、ハーネスを構成する部品自体の成熟度を段階的ラベルで管理する発想は、Skillやplugin資産が増えるにつれて有用性が増す。

出典: [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code)

## 学術研究からの2つの裏付け

### 「ハーネス設計だけで性能が最大6倍変わる」

Meta-Harness論文（Lee et al., 2026）の中心的知見。モデル自体を変えずにハーネス（プロンプト構成、ツールルーティング、コンテキスト戦略）だけを最適化することで、同一ベンチマークで最大6倍の性能差が生じ得ることを実証した。これは、本リポジトリが一貫して主張する「ハーネス設計はモデル性能とは独立した最適化対象である」という前提を学術的に裏付ける。

### 「Claude Codeの98.4%は決定論的インフラ」

*Dive into Claude Code*（VILA-Lab, arXiv:2604.14228, 2026）はClaude Code自体のソースを分析し、AI判断ロジックが担う部分はコードベース全体のわずか1.6%で、残り98.4%は権限ゲート、コンテキスト管理、ツールルーティング、リカバリロジックといった決定論的インフラであると報告した。設計思想としては、モデルの能力が上がるほど「意思決定を制約するフレームワーク」よりも「豊かな実行環境」の方が効果的、という前提に立っている。この知見は本リポジトリの既存パターン「4. 決定論的品質ゲート」「7. 最小権限と多層防御」の設計方針（制御は極力コードとpermission/hookへ追い出す）と整合する。

出典: [arXiv:2603.28052 (Meta-Harness)](https://arxiv.org/pdf/2603.28052), [arXiv:2604.14228 (Dive into Claude Code)](https://arxiv.org/html/2604.14228v1), [Cobus Greyling: 98% of Claude Code Is Not AI](https://cobusgreyling.substack.com/p/98-of-claude-code-is-not-ai), [VILA-Lab/Dive-into-Claude-Code](https://github.com/VILA-Lab/Dive-into-Claude-Code)

## 本リポジトリの既存パターンとの対応表

| 本ファイルのパターン | [既存調査](claude-code-development-harness-patterns.md)の対応パターン | 関係 |
|---|---|---|
| 1. Stop Hookループ | 6. 増分実装と構造化handoff | 同じ問題意識をより攻撃的に自動化した特化系 |
| 2. GAN型 Generator/Evaluator | 5. 専門Subagentと独立Evaluator | 具体的な実装パターンとしての精緻化 |
| 3. Agent Teams | 8. worktreeによる変更隔離（並列方式比較表） | 実運用知見による既存判断基準の裏付け |
| 4. Meta-Harness | 11. 能力連動の段階的簡素化 | 人手のablationを自動探索に置き換える将来像 |
| 5. Verb分割型ハーネス | パターン全体（推奨リファレンス構成） | 複数セッション前提の発展形 |
| 6. Agentic-Readiness監査 | 10. ハーネス自体のEvals | Skill/Agentポートフォリオ単位への拡張適用 |

## 採用時の注意点（コミュニティ実装全般）

- スター数やREADMEの完成度は品質を保証しない。ライセンス、最終更新日、Issue対応状況を確認する。
- 外部リポジトリのhook scriptやplugin manifestは任意コード実行面になり得るため、導入前に内容を読み、`eval`の有無や外部通信先を確認する（本リポジトリの既存パターン「7. 最小権限と多層防御」を参照）。
- Ralph Wiggum系のような無人ループ機能は、実行前に必ずコスト上限とmax-iterationsを設定し、破壊的操作（push、DB migration等）を許可範囲から明示的に除外する。
- 学術研究由来のパターン（Meta-Harness等）は再現性・運用コストの検証が本番投入の前提として必要であり、2026年7月時点では研究的関心として扱うのが妥当。

## 主要参考資料

- [anthropics/claude-code: plugins/ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [Chachamaru127/claude-code-harness](https://github.com/Chachamaru127/claude-code-harness)
- [oeftimie/vv-claude-harness](https://github.com/oeftimie/vv-claude-harness)
- [anothervibecoder-s/claudecode-harness](https://github.com/anothervibecoder-s/claudecode-harness)
- [hoangnb24/repository-harness](https://github.com/hoangnb24/repository-harness)
- [coleam00/adversarial-dev](https://github.com/coleam00/adversarial-dev)
- [FlineDev/TandemKit](https://github.com/FlineDev/TandemKit)
- [celesteanders/harness](https://github.com/celesteanders/harness)
- [001TMF/harness-forge](https://github.com/001TMF/harness-forge)
- [raphaelchristi/harness-evolver](https://github.com/raphaelchristi/harness-evolver)
- [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code)
- [VILA-Lab/Dive-into-Claude-Code](https://github.com/VILA-Lab/Dive-into-Claude-Code)
- [arXiv:2603.28052 — Meta-Harness: End-to-End Optimization of Model Harnesses](https://arxiv.org/pdf/2603.28052)
- [arXiv:2604.14228 — Dive into Claude Code: The Design Space of Today's and Future AI Agent Systems](https://arxiv.org/html/2604.14228v1)
- [Claude Code Docs: Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams)
