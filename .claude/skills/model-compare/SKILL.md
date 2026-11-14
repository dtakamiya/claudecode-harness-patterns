---
name: model-compare
description: 同じプロンプトを複数の Claude モデル（Haiku/Sonnet/Opus、4.5・5・5.5 など）で実行し、コスト・所要時間・往復数・出力を並べて比較する。HTML アプリを生成させて見た目で比較することもでき、結果は Artifact として公開する。「モデルを比較して」「Haiku と Sonnet でどう違う」「5.5 のコストを知りたい」「このプロンプトを各モデルで試して」「モデル選定の根拠がほしい」など、モデル間の品質・コスト比較が話題になったら、明示的に頼まれていなくても使うこと。
---

# model-compare

同一プロンプトを複数モデルで実行し、数値（コスト・時間・トークン）と出力を1ページで比較する。

## 手順

1. **タスクを決める。** `references/tasks-example.json` を雛形に、比較したい作業を `tasks.json` にする。ユーザーがプロンプトを指定していなければ雛形（機械変換・探索・設計判断・HTML 生成）を既定とし、勝手に創作せず「何を比較するか」だけ短く確認する。
   - `kind: "html"` のタスクは単一 `index.html` を書かせ、見た目で比較する。
   - `checks.contains` を付けると、全文字列が出力に含まれるかを ✓/✗ で機械判定する。正解が文字列で決まるタスク（件数ゼロの負例、一覧の網羅など）だけに付ける。判定できないものは人が見る。
2. **モデル ID を確認する。** `claude -p "OKとだけ答えて" --model <id> --output-format json` を実行し、`modelUsage` のキーが指定 ID と一致することを見る。エイリアス（`haiku` など）は解決先が保証されないため使わない。既知の ID: `claude-haiku-4-5-20251001` / `claude-haiku-5-5` / `claude-sonnet-5` / `claude-sonnet-5-5` / `claude-opus-5` / `claude-opus-5-5`。不明な ID は存在しないことがあるので、必ずこの確認を通す。
3. **実行する。** 出力先はリポジトリ外（scratchpad）にする。HTML 成果物を Artifact に載せる際、ソースは作業ディレクトリか scratchpad 配下である必要がある。

   ```bash
   python3 -I <skill-dir>/scripts/run_compare.py --tasks tasks.json --out <scratchpad>/compare \
     --model h55=claude-haiku-5-5 --model s55=claude-sonnet-5-5 --baseline h55
   ```

   - 並列実行（既定 8）。実行コストが発生するので、Opus を含める場合は先に概算を伝える（雛形 8 タスクで Opus 5 が約 $7.6、Haiku 5.5 が約 $0.1 だった実績）。
   - 既存の結果はスキップされるため、モデルの追加は `--model` を足して再実行するだけでよい。やり直すなら `--force`。
4. **Artifact として公開する。** HTML は必ず Artifact で作る（ローカルの `open` で済ませない）。`artifact-design` スキルを読んでから、`compare.html` を `file_path` に、`publish_files.json` の内容を `files` に渡して公開する（HTML アプリの iframe が相対パスで参照するため）。Artifact は既定で非公開。URL をユーザーに渡す。
5. **要約を返す。** 合計コストの倍率、所要・往復数の目立つ差、`checks` の結果、HTML の見た目確認はユーザーに任せる旨を短く報告する。

## 注意（結果の読み方）

- 各タスク **1 試行**。ばらつきは見えていない。順位の差を断定せず、必要なら試行数を増やす提案をする。
- 判定できるのは `checks` だけ。それ以外の正誤（設計の妥当性など）は未採点であることを明記する。採点まで求められたら、正解表を作って突合するか、ルーブリックで別途採点する。
- コストは CLI の `total_cost_usd`。キャッシュ込みの実測値で、モデルごとの単価差と往復数の両方が反映される。
- 同一モデルでも往復数が試行で変わるので、コスト差の一部は探索の仕方の差である。
- テキストタスクは読み取り系ツールのみ許可（`Read Grep Glob`）。HTML タスクは `Read Write Edit`。それ以外が必要なら tasks.json の `tools` で明示する。
