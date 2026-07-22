<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/hooks/`が配布元であり、
利用者の`.claude/hooks/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。

正本: 設計書 §3.5, §3.5.1, §3.6, §3.6.1〜§3.6.7, §14
-->

# Hooks（Deterministic Guardrail 実装）

設計書 §3.5 の予防・検知・完了確認・状態確認を、Claude Code の hooks へ実装したもの。

## 構成

| ファイル | 対応するタイミング | 責務 |
|---|---|---|
| `pre-tool-use.sh` | `PreToolUse` | write scope照合、Bashコマンドの構造検証（§3.6.1, §3.6.2） |
| `post-tool-use.sh` | `PostToolUse` | secret scan、変更ファイル記録（§3.5 Detective） |
| `subagent-stop.sh` | `SubagentStop` | agent-run成果物と必須fieldの存在確認（§3.5 Completion check） |
| `stop-gate.sh` | `Stop` | revision整合、blocking issue、next_actionの確認（§3.5 State commit） |

判定ロジックは `scripts/` の3本へ委譲する。hook側はClaude Codeのプロトコル変換だけを行う。

| スクリプト | 責務 |
|---|---|
| `scripts/verify-bash-command.sh` | コマンド文字列を構造として検証し、argv[0]をallowlistと照合 |
| `scripts/verify-redirect-target.sh` | リダイレクト先をcanonical path化してwritableと照合 |
| `scripts/verify-write-scope.sh` | write scope照合、create-only、symlink・traversal拒否 |

表中のパスは**利用者リポジトリでの配置先**であり、雛形の配布元は `templates/scripts/` である。`pre-tool-use.sh` は `${CLAUDE_PROJECT_DIR}/scripts/` を参照するため、この3本を配置しないと**Bash・Write・Editが全てdenyされる**（fail-closed設計のため、設定漏れは「制限なし」ではなく「全拒否」になる）。`.claude/` 配下だけをコピーしても動作しない。

## 導入

```bash
cp templates/hooks/*.sh              .claude/hooks/
cp templates/settings.json           .claude/settings.json
cp templates/bash-allowlist          .claude/bash-allowlist
cp templates/write-scope-policy      .claude/write-scope-policy
cp templates/scripts/verify-*.sh     scripts/
chmod +x .claude/hooks/*.sh scripts/verify-*.sh
```

`bash-allowlist` と `write-scope-policy` は**雛形のままでは使えない**。プロジェクトのモジュール構成と、§16-2 の監査を経たコマンドへ置き換えること。

---

# 既知の限界

**このHook群を導入しても、設計書が要求する強制水準には届かない部分がある。** 以下は実装上の不足ではなく、Claude Codeのhooks APIと設計書の要求との構造的なギャップである。導入者が「設定したので守られている」と誤認しないために明記する。

## 1. Agent単位のwrite scopeを強制できない

設計書 §3.6 はAgentごとに異なる論理Write範囲を定め、その概念例として `.claude/agents/architect.md` のfrontmatterに `hooks:` を書く形を示す。

しかし **Agent frontmatter の `hooks` フィールドは公式ドキュメントに記載がない**（Skill frontmatterの `hooks` は記載がある）。`settings.json` の hooks は全Agent共通に適用されるため、本実装の `write-scope-policy` は**単一のポリシーしか表現できない**。

結果として、次が現状では機械的に強制されない。

- Requirements Analyst が `docs/features/*/requirements/**` だけを書くこと
- Architect が実装を変更しないこと
- Evaluator が read-only であること
- Context Builder だけが `docs/context/manifests/**` を書けること（§3.6 rules/permissions.md §3の分岐）

### 回避策

**Orchestrator / External Runner が、Agent起動前に対象Agent用のpolicyファイルを配置する。**

```text
.claude/write-scope-policy.d/
├─ tdd-generator
├─ architect
├─ context-builder
└─ evaluator
```

起動側が `cp .claude/write-scope-policy.d/<agent> .claude/write-scope-policy` してからAgentを起動する。この切替はAgent自身が行えてはならない（`.claude/**` はdenyであり、Agentは自らのpolicyを書き換えられない）。

**この切替を実装しない場合、Agent別のWrite範囲は宣言に留まる。** 設計書 §3.6 の「記述しただけではファイルACLにならない」がそのまま当てはまる。

## 2. `PostToolUse` は予防ではない

設計書 §3.5 が明記するとおり、`post-tool-use.sh` のsecret scanは**すでに書かれた後**に動く。検出は復旧手続きの起点であって、防止ではない。

機密パスは `settings.json` の `permissions.deny` と `pre-tool-use.sh` で遮断すること。secret scanのパターンは代表例に過ぎず、プロジェクト固有の形式は追加が必要である。

## 3. allowlist一致は安全を意味しない

`verify-bash-command.sh` が照合するのは `npm` という**入口の名前**だけである。その先で動くビルドスクリプト、テストコード、プラグイン、依存は見ていない。

> 悪意ある変更を検出するために実行したコマンドが、その悪意ある変更を実行する（設計書 §3.6.4）

したがって次が別途必要である。これらはhookでは代替できない。

- allowlistへ登録する前の §16-2 監査（推移的な呼出先の確認）
- Network遮断・secret非搭載の隔離実行環境
- ビルド設定・テストハーネス設定・CI設定・依存定義が変更されたrunでの再監査

## 4. sandboxの代替にならない

設計書 §3.5:

> Hooksを利用できない環境では、同等の効果をExternal Harness Runner、permissions、sandbox、CIへ移管する。ただしHookだけをサンドボックスやpermissionsの代替にしない。

hookスクリプトが削除された、実行権が落ちた、シェルが無い、といった場合、hookは**何も守らない**。`settings.json` の `permissions.deny` を併記しているのはこのためであり、さらにsandboxとCIを併用すること。

## 5. `SubagentStop` / `Stop` の検査は形式のみ

両hookが確認できるのは成果物の**存在と形式**であって、内容の妥当性ではない。agent-runに記載されたテスト結果が真実かは判定していない。

設計書 §14.2 が求める完全な検査（Git diff、レビュー対象SHA、変更範囲）はExternal Runnerの `quality-gate.sh` / `verify-agent-result.sh` が担う。**本hookを通ったことを工程完了の根拠にしない。**

---

# 実装上の注意（移植性）

このHook群はBash 3.2とmacOS標準awkで動作する必要がある。以下は実際に踏んだ落とし穴である。

| 事象 | 対処 |
|---|---|
| `\y`（単語境界）はGNU awk拡張。macOSでは**黙ってマッチせず検出漏れになる** | 使用しない |
| awkの `exit` は `END` ブロックを抑止しない。判定が複数行になり比較が壊れる | 判定出力に `END` を使わない |
| awkの `BEGIN` では `$0` が未設定 | 入力を読む処理はレコード処理ブロックへ置く |
| awk `-v` は代入時にエスケープを解釈し、改行を含む値で異常終了する | 複数行の値はstdin経由で渡す |
| `"$VAR（..."` は全角括弧まで変数名と解釈され、`set -u` で落ちる | `${VAR}` で明示的に閉じる |

# テスト

```bash
bash scripts/test-verify-bash-command.sh
bash scripts/test-verify-write-scope.sh
bash scripts/test-pre-tool-use-hook.sh
bash scripts/test-post-tool-use-hook.sh
bash scripts/test-stop-hooks.sh
```

各テストは「拒否されるべきものが素通りしないこと」を主眼に置く。**この種のガードは、壊れても出力が静かなため、変異テスト（検査を1つずつ無効化してテストが落ちることの確認）で実効性を確かめること。** 検査を無効化してもテストが通る場合、そのテストは何も守っていない。
