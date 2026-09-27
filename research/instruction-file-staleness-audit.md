# 指示ファイル陳腐化監査（instruction-file-staleness-audit）: `/doctor prompt-audit` の運用メモ

- 調査日: 2026-09-28
- 対象: Claude Code v2.1.283 で追加された `/doctor prompt-audit`（別名 `/checkup prompt-audit`）
- 目的: ハーネスの正本ファイル（CLAUDE.md / AGENTS.md / skills / agents / commands）の陳腐化を、定期的に機械で点検する運用が組めるかを確かめる
- ステータス: 調査ノート（パターン化候補 hrq-013。パターン README 化は未着手）

## 結論

- 指示ファイルには型チェックも CI も効かない。書いた直後から古くなり始めるのに、これまで点検は人の目視に頼っていた。
- v2.1.283 で、CLI に組み込まれた監査コマンドが入った。対象は CLAUDE.md・skills・agents・commands の3種類の問題で、「古いモデル向けのプロンプト作法」「存在しないパスやコマンドの参照」「指示ファイル同士の矛盾」を検出する。
- `claude -p "/doctor prompt-audit"` のように非対話モードで実行でき、結果は Markdown のレポートで返る（2026-09-28 に v2.1.283 で実機確認）。したがって cron や CI に組み込める。
- 修正は「提案差分（未適用）」として出るだけで、ファイルは書き換えない。人間のゲートを通す前提の設計と相性がよい。

## 一次情報

- CHANGELOG v2.1.283: 「Added `/doctor prompt-audit` (also `/checkup prompt-audit`) to audit your CLAUDE.md files, skills, agents and commands for prompting patterns written for older models」
- 同じ v2.1.283 の改善項目: 「stale paths, stale commands and contradicting instruction files now lead the report」
- 出典: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md

## 実機で確認した挙動（v2.1.283、非対話実行）

| 観点 | 挙動 |
|---|---|
| スコープ | プロジェクトの CLAUDE.md / AGENTS.md / `.claude/` に加え、**祖先ディレクトリの AGENTS.md**、`~/.claude/CLAUDE.md`、同期スキル、プラグインまでを走査する |
| 対象外 | settings 系・`.mcp.json` は読まない。リポジトリ内のテンプレート（セッションに読み込まれない `.md`）は成果物として除外する |
| 分類 | G1 古いプロンプト文言 / G2 設定ファイルの劣化（矛盾・重複・変わりやすい具体名）/ G3 ツール説明 / G4 リクエスト設定・アーキテクチャ |
| 出力 | 指摘ごとに「場所・根拠となる記述・パターン・理由・確信度・対応（rewrite / flag）」の表と、未適用の diff |
| 検証 | 参照しているスキル・エージェント・MCP が今のセッションに実在するかを突き合わせる |
| 基準 | 実行中のモデル（例: `claude-opus-5-5`）を基準に「古い」を判定する |

## パターンの骨子（候補）

1. **定期監査**: 正本ファイルを持つハーネスでは、週次などの定期ジョブで `claude -p "/doctor prompt-audit"` を実行し、レポートを保存する。
2. **ゲート経由の修正**: 提案差分は PR を通して取り込む。自動では適用しない（[human-gate-policy](../patterns/human-gate-policy.md)、[change-intent-record](../patterns/change-intent-record.md) の考え方と揃える）。
3. **モデル切替時の必須チェック**: メジャーなモデル更新のたびに1回実行し、「新しいモデルでは不要になった誘導文言」をまとめて洗い出す。
4. **影響範囲の明示**: 祖先ディレクトリやユーザー全体に効くファイル（`~/AGENTS.md` など）への指摘は、配下の全プロジェクトに影響する。個別リポジトリの PR では直さず、別に扱う。

## 既存資料との関係

- 新規。research/・patterns/ に、指示ファイルそのものの健全性を点検する話はない。
- hrq-004（harness-eval-runner）とは点検の軸が違う。eval は「ハーネスがどう振る舞うか」、prompt-audit は「指示ファイルが健全か」を見る。
- hrq-012（AGENTS.md の公式対応）とは組み合わせて使える。AGENTS.md と CLAUDE.md が併存するとき、両者の矛盾を検出する手段になる。

## 注意点・未確認事項

- 誤検知率は、実機1回分の結果しか見ていないため評価できていない。矛盾の指摘は「確信度: 中」で出てきたので、採否は人が判断する前提で扱う。
- 実行するたびに LLM を1セッション分動かすので、コストがかかる。頻度は hrq-006（コストガードレール）の予算内で決める。
- レポートの形式（表の列名やグループ番号）が今後の版でも同じかは保証されていない。機械でパースするなら版を固定するか、緩いパースにする。
- 祖先ディレクトリの個人設定がレポートに出てくる。CI ログを公開する場合は、レポートの扱いに注意する。
