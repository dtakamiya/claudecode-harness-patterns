# 5.5 世代のハーネス再設計: 調査ノートと実測計画

調査日: 2026-10-31 / 状態: 仮説段階（実測前）

## 結論

- 公式は「ハーネスの各要素はモデルの限界への仮定を含み、その仮定は陳腐化する」と明言している。
- 確認できた簡素化は Opus 4.5/4.6 世代まで。**5.5 世代で planner/evaluator を削れるという公式記述は未確認**。
- 3 エージェント構成は一律に廃止ではなく、要素ごとに削る/残すを分ける。
- 5.5 世代の確定事項は価格・仕様・effort 既定値。構成の最適解は実測で決める（末尾の計画）。

## 検算済みの事実（一次ページで確認）

### 価格（入力/出力、per MTok）
出典: https://platform.claude.com/docs/en/about-claude/pricing （2026-10-31 参照）

| モデル | 入力 | 出力 | cache read |
|---|---|---|---|
| Fable 5.1 | $10 | $50 | $0.25 |
| Opus 5.5 | $4 | $20 | $0.20 |
| Sonnet 5.5 | $2 | $10 | $0.10 |
| Haiku 5.5（100k 以下） | $0.10 | $0.50 | $0.01 |
| Haiku 5.5（100k 超） | $0.50 | $2.50 | $0.05 |

- Haiku 5.5 の入力単価は Sonnet 5.5 の 1/20。ただしトークン消費量が多ければ差は縮む（Haiku 4.5 は Sonnet 4.5 の約 3 倍消費、`haiku-model-performance-validation.md:108,152`）。

### 公式ハーネス記事
出典: https://www.anthropic.com/engineering/harness-design-long-running-apps （2026-03-24）

| 要素 | Opus 4.5 | Opus 4.6 |
|---|---|---|
| context reset | 削除（自動 compaction で連続セッション） | 再導入せず |
| sprint 構造 | 維持（sprint ごとに採点） | 削除 |
| planner | 維持 | 維持（無いと generator が under-scope） |
| evaluator | sprint ごと | 最後に 1 回へ移行 |

- evaluator の価値条件: 「現行モデルが単独で確実に解ける範囲を超えるタスク」。範囲内では不要なオーバーヘッド。

### Sonnet 5.5
出典: https://www.anthropic.com/claude-sonnet-5-5 （2026-09-28）

- max effort では code-review skill が多数のサブエージェントに分割され、Cognition の検証例で timeout と範囲外編集が 2 件発生。
- 既定 effort は Claude Code/apps が Medium、Claude Platform が High。
- 公式ページにハーネス設計の専用ガイダンスは無い。

### その他の公式情報
- Cognition「Multi-Agents: What's Actually Working」（2026-04-22）: 並列 writer の swarm は採用が少ない。実態は readonly サブエージェント中心。書き込みは単一スレッド。
- Anthropic multi-agent research system（2025-06-13、自社内部評価）: マルチエージェントは通常チャット比で約 15 倍のトークン。コーディングは並列化しにくい。

## 未検証（採用前に確認が必要）

- 5.5 世代で planner/evaluator を削れるという公式記述（見つからず）。
- advisor の数値（BrowseComp 41.2% 対 19.7%、「品質 -29% / コスト -85%」）は検索スニペット・二次情報のみ。
- Opus 5.5 の「サブエージェントへの委譲が大幅に上手い」は Column 社の評価で、Anthropic 自身の主張ではない。
- 公式記事の URL が engineering/ と research/ で報告が食い違う（上記は engineering/ で本文を確認済み）。
- Fable 5.1 発表ページは 404。
- Cursor / Devin / Manus の 2026 年版は未調査。

## 現行構成とのギャップ

- `~/.claude/agents/gan-*.md` は全役 `model: sonnet` 固定（各 `:5`）。役割別の配分は未検討。
- `gan-planner.md:49-58` に sprint 構造が残る。`research/claude-code-development-harness-patterns.md:283` は sprint/context reset 削除の事例を既に記録しており、エージェント定義に未反映。
- 3 エージェント構成そのもののコスト・品質の実測は無い。

## 要素別の暫定判断（実測で確定）

| 要素 | 暫定判断 | 根拠 |
|---|---|---|
| sprint 構造・context reset | 削除 | 公式事例（Opus 4.5/4.6） |
| planner | 維持 | 公式: 無いと under-scope。独立は大規模判断のみ（DEC-006） |
| evaluator | 難易度条件付き。最後に 1 回 | 公式の価値条件 |
| サブエージェント | 書き込みは単一スレッド、並列は readonly 調査。深さ・同時数に上限 | Cognition、Sonnet 5.5 の過剰起動事例 |
| モデル配分 | Haiku/Sonnet/Opus を役割別に検証 | 価格差 20 倍。ただしトークン消費差は未測定 |

## 実測計画（未実行）

- 道具: `model-compare` スキル。
- 構成（同一タスクに適用）:
  - A: 単一エージェント Sonnet 5.5（Medium）
  - B: 現行 3 役 Sonnet 5.5 + sprint
  - C: 簡素化版（planner + generator + 最後 1 回の evaluator）Sonnet 5.5
  - D: C の generator を Haiku 5.5、evaluator は Sonnet 5.5
  - E: Haiku 5.5 実行 + Opus 5.5 の advisor サブエージェント（自作構成。Claude Code の Advisor ツールとは別物で、そちらは `advisor-cost-measurement.md`）
- タスク: 難易度 3 段（単独で確実に解ける / 中 / 単独では怪しい）。決定的テストがあるものを優先。
- 統制: effort 固定（Medium）、サブエージェントの深さ・同時数に上限、各条件 n≥3、pass^k も記録。
- 指標: トークン→価格表で換算したコスト、往復数、所要時間、テスト合格率、ルーブリック採点（採点者は実行モデルと別モデルで盲検）。
- 判定基準（事前固定）: 合格率が A と同等で最安の構成を採用。evaluator は「A が落ちる難易度で合格率を有意に上げる」場合のみ維持。
- 実行前に推定コストを提示し、承認を得る。
