# diff-review スキル実装

[設計書](../docs/design.md)に従った実装本体です。任意のリポジトリへコピーして単独で動作します。

## 導入

`diff-review/` ディレクトリをスキル配置先へコピーします。

```bash
cp -r diff-review ~/.claude/skills/          # personal（全プロジェクトで有効）
cp -r diff-review <repo>/.claude/skills/     # project（当該リポジトリのみ）
```

`/diff-review` で起動します。引数なしで作業ツリーの未コミット変更、ブランチ名・PR番号・パスを引数に取れます。

```bash
/diff-review
/diff-review feature/foo
/diff-review '#123'
/diff-review src/auth.ts
```

## 構成

```text
diff-review/
├── SKILL.md                 # 本体（131行）
├── reference/               # Step 3で該当観点に触れたときのみ読まれる
│   ├── correctness.md       # 正当性・境界・並行性
│   ├── security.md          # 注入、認証認可、秘密情報、暗号
│   ├── maintainability.md   # 重複、命名、テスト（ほぼ常に non-blocking）
│   ├── tracing.md           # 差分起点の探索手順（呼び出し元、認可の比較）
│   ├── severity.md          # blocking / non-blocking の判定基準
│   └── gotchas.md           # 実測された偽陽性パターン（Ratchetで育てる）
└── scripts/
    └── collect_diff.sh      # 対象確定（決定論的、低自由度）
```

## 配布形態の制約

`when_to_use` / `argument-hint` / `disallowed-tools` / `model` は **Claude Code 専用フィールド**です。Agent Skills spec 外のフィールドを含むため、**claude.ai へのアップロード、Skills API、`package_skill.py` では失敗します**（無視されるのではなくハードエラー）。

これは意図した割り切りです。`disallowed-tools` は設計の中核（レビュアーは修正しない）であり、これを外すと設計が成立しません。詳細は[設計書 §3.2.1](../docs/design.md)。

## 検証済みの挙動

`collect_diff.sh` は一時リポジトリでの実測で以下を確認しています。

| 入力 | 結果 |
|---|---|
| 引数なし（未コミット変更あり） | スコープ・ファイル数・変更行数を stderr へ出力、exit 0 |
| 存在しないPR番号 | ghの出力を添えてエラー、exit 1（Step 1で停止） |
| PR URL（`.../pull/456`） | 番号のみを抽出して `gh pr diff` へ渡す |
| 解決できない引数 | エラー、exit 1 |
| 差分0行のブランチ | 「対象が0行」エラー、exit 1 |
| `-- <path>` | 当該パスに触れている差分のみ、exit 0 |
| ブランチとパスが同名 | 曖昧として停止、exit 1（明示形式を案内） |

変更行数は diff のヘッダ行のみを除外して数えます。`- item` のような箇条書きを含む差分でも過少カウントしません。

**スクリプトは `${CLAUDE_SKILL_DIR}` 経由で呼びます。** 相対パスで書くとカレントディレクトリ次第で「ファイルが無い」となり、その失敗は exit 0 で返るため、対象なしのままレビューが進む危険があります。

exit 1 のとき SKILL.md Step 1 は**停止を指示します**。リポジトリ全体を推測で読み始めません（eval E4 が測る挙動）。

## 改善の回し方

偽陽性が出たら2箇所へ1件ずつ足します（[設計書 §7.2](../docs/design.md) Ratchetパターン）。

1. `reference/gotchas.md` へ棄却パターンを追記
2. `../evals/tasks.jsonl` へ負例タスクを追加

`gotchas.md` が100行を超えたら先頭に目次を置きます。
