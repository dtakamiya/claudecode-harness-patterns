# Excel コンテキスト化リサーチ：ドキュメント索引

調査日: 2026-09-05  
対象: 要件定義・設計工程の Excel 資料を AI（Claude）に読み込ませるための包括的リサーチ  
成果物数: 3 つのドキュメント + テンプレート集

---

## 📑 ドキュメント一覧

### 1. **excel-context-engineering-comprehensive-guide.md** ★ メイン

完全な理論・実装ガイド（約8000行）

**内容:**
- セクション 1-2: 理論基礎（フォーマット変換、入力方法）
- セクション 3: ツール・ライブラリ比較（Python/JS/CLI）
- セクション 4: ベストプラクティス（大規模対応、スキーマ保持、数式処理）
- セクション 5: コスト最適化（段階的処理、Batch API、キャッシング）
- セクション 6: このリポジトリとの統合パターン
- セクション 7: シナリオ別実装フロー
- セクション 8: チェックリスト

**対象者:** アーキテクト、実装者

**読み方:**
- 理論→セクション 1-2
- 実装→セクション 3, 4
- 最適化→セクション 5-7

---

### 2. **excel-implementation-templates.md** ★ 実装用

実行可能なテンプレート・スクリプト・設定集（約3000行）

**テンプレート:**
1. Python 変換パイプライン（`excel_to_context.py` 完全版）
2. Context Manifest 設定（YAML）
3. スナップショット正規化（YAML フォーマット）
4. MCP Excel Server 設定（`.claude/mcp-servers.json`）
5. Batch API 処理スクリプト（`excel_batch_analysis.py` 完全版）
6. CI/CD パイプライン（GitHub Actions）
7. Claude Code Skill（`.claude/skills/excel-analyzer.md`）

**対象者:** 実装エンジニア

**使い方:**
1. テンプレートをプロジェクトにコピー
2. パス・API キー・設定を自プロジェクトに合わせて調整
3. チェックリストを実行

---

### 3. **本ドキュメント（EXCEL-CONTEXT-ENGINEERING-INDEX.md）**

リサーチ全体の索引・ナビゲーションガイド

**内容:**
- ドキュメント概要
- セクション横断的なナビゲーション
- クイックスタート（15分、1時間、1日コース）
- よくある質問と回答
- 関連リンク

---

## 🚀 クイックスタートガイド

### 15分コース：「まず理解したい」

1. `excel-context-engineering-comprehensive-guide.md`
   - 結論を読む
   - セクション 2（入力方法比較表）を読む
   
2. `excel-implementation-templates.md`
   - テンプレート 1（Python スクリプト）の概要を把握

**成果:** Excel コンテキスト化の全体像を理解

---

### 1時間コース：「小規模プロジェクト向けに準備したい」

1. `excel-context-engineering-comprehensive-guide.md`
   - セクション 2（入力方法）を選定
   - セクション 3（ツール）から推奨ツールを選択

2. `excel-implementation-templates.md`
   - テンプレート 1（Python スクリプト）をコピー
   - テンプレート 2（Context Manifest）を自プロジェクト用に調整

3. チェックリスト実行
   - 環境準備
   - ファイル構成確認

**成果:** 小規模（<5MB）Excel の変換パイプライン完成

---

### 1日コース：「本番環境に統合したい」

**午前（2-3時間）：準備と理解**
1. `excel-context-engineering-comprehensive-guide.md` 全体を読む
2. このリポジトリの既存パターンを確認
   - `patterns/claude-code-development-harness/docs/design.md`（Context Manifest）
   - `patterns/claude-code-jira-ticket-harness/docs/design.md`（TicketSnapshot）

**午後（2-3時間）：実装**
1. `excel-implementation-templates.md` の各テンプレートをコピー
2. テンプレート 4（MCP 設定）と 5（Batch API）を統合
3. テンプレート 6（CI/CD）を GitHub Actions に配置
4. チェックリスト実行

**夕方（1-2時間）：テスト・最適化**
1. サンプル Excel で動作確認
2. トークン消費量を測定
3. 必要に応じてセクション 5（最適化）を適用

**成果:** 本番環境統合完了、定期自動処理実装

---

## ❓ よくある質問（FAQ）

### Q1: 「どの入力方法を選べばいい？」

→ **`excel-context-engineering-comprehensive-guide.md` セクション 2.2**

| ファイルサイズ | 用途 | 推奨方法 |
|---|---|---|
| <1MB | クイック分析 | テキスト直埋め込み |
| 1-100MB | 複数回質問 | Files API + キャッシング |
| >100MB | 大規模自動化 | RAG + Batch API |

---

### Q2: 「MCP（Model Context Protocol）を使うべき？」

→ **`excel-context-engineering-comprehensive-guide.md` セクション 2.1-C**

**MCP を使う場合：**
- Claude Desktop 統合
- Excel との双方向同期が必要
- 複数エージェントで共有

**MCP 不要な場合：**
- クイック分析（1-2回）
- 小規模ファイル
- ローカル処理で十分

---

### Q3: 「トークン消費を最小化するには？」

→ **`excel-context-engineering-comprehensive-guide.md` セクション 5**

推奨順序：
1. **段階的処理**（抽出→要約→埋め込み）→ 37% 削減
2. **Batch API** → さらに 50% 削減
3. **プロンプトキャッシング** → 複数回使用で 90% 削減

---

### Q4: 「複数 Excel を一度に処理したい」」

→ **`excel-implementation-templates.md` テンプレート 5（Batch API）**

```bash
python excel_batch_analysis.py --input "docs/data/*.xlsx" --wait
```

---

### Q5: 「スナップショット YAML のスキーマ定義がわからない」

→ **`excel-implementation-templates.md` テンプレート 3**

テンプレート内のコメント説明を参照。
基本：JSON Schema Draft 7 形式

---

### Q6: 「GitHub Actions で自動化したい」

→ **`excel-implementation-templates.md` テンプレート 6**

- `.github/workflows/excel-context-sync.yaml` をコピー
- 日次実行、変更自動検出、Git commit

---

## 🔗 関連リソース

### このリポジトリ内

| ドキュメント | 関連性 | 参照理由 |
|---|---|---|
| `context-engineering-per-sdlc-phase.md` | 高 | Excel コンテキスト化は工程別コンテキスト設計の一部 |
| `patterns/claude-code-development-harness/docs/design.md` | 高 | Context Manifest と十層モデルの実装例 |
| `patterns/claude-code-jira-ticket-harness/docs/design.md` | 中 | TicketSnapshot 正規化パターンを Excel に適用 |
| `patterns/claude-code-incident-response-harness/docs/design.md` | 中 | 構造化データ管理の best practice |

### 外部リソース

| リソース | 用途 |
|---|---|
| [Claude Files API Docs](https://platform.claude.com/docs/en/build-with-claude/files) | Files API 実装詳細 |
| [Prompt Caching Docs](https://platform.claude.com/docs/en/build-with-claude/caching) | キャッシング実装 |
| [Batch API Docs](https://platform.claude.com/docs/en/build-with-claude/batch) | バッチ処理実装 |
| [MCP Protocol](https://modelcontextprotocol.io/) | MCP 仕様 |
| [mort-lab/excel-mcp](https://github.com/mort-lab/excel-mcp) | MCP 実装サンプル（Python） |
| [JSON Schema](https://json-schema.org/) | スキーマ定義標準 |

---

## 📊 コンテンツマップ

```
excel-context-engineering-comprehensive-guide.md
  ├─ § 結論（2分読み）
  ├─ § 1. フォーマット変換
  │  ├─ 1.1 変換形式の比較表
  │  └─ 1.2 変換フロー（行数別）
  ├─ § 2. AIへの入力方法 ★
  │  ├─ 2.1 5 つの方法
  │  │  ├─ A. テキスト埋め込み
  │  │  ├─ B. Files API
  │  │  ├─ C. MCP
  │  │  ├─ D. RAG + Vector DB
  │  │  └─ E. プロンプトキャッシング
  │  └─ 2.2 選択マトリックス
  ├─ § 3. ツール・ライブラリ
  │  ├─ 3.1 Python（Pandas/openpyxl）
  │  ├─ 3.2 JavaScript（SheetJS/ExcelJS）
  │  └─ 3.3 CLI（ssconvert/LibreOffice）
  ├─ § 4. ベストプラクティス ★
  │  ├─ 4.1 大規模対応（行数別）
  │  ├─ 4.2 スキーマ保持
  │  ├─ 4.3 数式処理
  │  └─ 4.4 複数シート・リンク
  ├─ § 5. コスト最適化 ★
  │  ├─ 5.1 トークン削減（37-50%）
  │  ├─ 5.2 Batch API
  │  └─ 5.3 プロンプトキャッシング（90%削減）
  ├─ § 6. 統合パターン
  │  ├─ 6.1 Context Manifest
  │  ├─ 6.2 正規化（TicketSnapshot）
  │  └─ 6.3 MCP Tool Gateway
  ├─ § 7. シナリオ別実装
  │  ├─ A. 小規模（即座分析）
  │  ├─ B. 中規模（複数回分析）
  │  └─ C. 大規模（自動化）
  ├─ § 8. チェックリスト
  └─ § 参考資料・次ステップ

excel-implementation-templates.md
  ├─ テンプレート 1: Python 変換パイプライン
  ├─ テンプレート 2: Context Manifest YAML
  ├─ テンプレート 3: スナップショット正規化 YAML
  ├─ テンプレート 4: MCP サーバー設定
  ├─ テンプレート 5: Batch API スクリプト
  ├─ テンプレート 6: CI/CD 自動化（GitHub Actions）
  ├─ テンプレート 7: Claude Code Skill
  └─ チェックリスト（環境準備）
```

---

## ⭐ 特に重要なセクション

読む順序と学習効果：

1. **入門者向け（15分）**
   - `excel-context-engineering-comprehensive-guide.md` § 結論
   - `excel-context-engineering-comprehensive-guide.md` § 2.2（選択マトリックス）

2. **実装者向け（1-2時間）**
   - `excel-context-engineering-comprehensive-guide.md` § 3-5
   - `excel-implementation-templates.md` § テンプレート 1-3

3. **最適化・統合向け（2-4時間）**
   - `excel-context-engineering-comprehensive-guide.md` § 5-7
   - `excel-implementation-templates.md` § テンプレート 4-7
   - このリポジトリの既存パターン

---

## 📈 期待される効果

### コスト削減

| 施策 | 削減率 | 実装難度 |
|---|---|---|
| 標準（最適化なし） | - | - |
| 段階的処理 | 37% ↓ | 低 |
| Batch API 活用 | 50% ↓ | 中 |
| プロンプトキャッシング | 90% ↓ | 中 |
| 全て組み合わせ | 90% ↓ | 高 |

### 開発時間削減

| 段階 | 実装時間 | 自動化後の削減 |
|---|---|---|
| 小規模（<5MB） | 1-2時間 | 50% |
| 中規模（5-100MB） | 3-4時間 | 70% |
| 大規模（>100MB） | 5-6時間 | 80% |

---

## 🎯 次のステップ

### Phase 1: 環境準備（1日）
- [ ] `excel-context-engineering-comprehensive-guide.md` 全体読破
- [ ] `excel-implementation-templates.md` テンプレート 1-3 をコピー
- [ ] 環境セットアップ（Python + ライブラリ）

### Phase 2: パイロット実装（3-5日）
- [ ] サンプル Excel で変換実行
- [ ] Context Manifest を作成
- [ ] Claude Code で動作確認

### Phase 3: 本番統合（1-2週間）
- [ ] MCP サーバー設定（テンプレート 4）
- [ ] CI/CD 自動化（テンプレート 6）
- [ ] チーム向けドキュメント作成

### Phase 4: 継続的改善（恒常）
- [ ] トークン消費量を監視
- [ ] キャッシング・Batch API の効果を測定
- [ ] このリポジトリの既存パターンとの統合を深める

---

## 📝 作成情報

**調査日:** 2026-09-05

**情報源:**
- Anthropic 公式ドキュメント（Claude API、Claude Code）
- オープンソース実装（MCP サーバー、ライブラリ）
- 業界ベストプラクティス（RAG、データパイプライン）
- このリポジトリの既存設計パターン

**対象者:**
- ソフトウェアアーキテクト
- AIアシスタント統合エンジニア
- DevOps エンジニア
- プロダクトマネージャー

**更新予定:** 2026-10-05（1ヶ月ごと）

---

**このリサーチ全体は、要件定義・設計工程の Excel 資料を効率的に AI に読み込ませ、コスト を最適化し、開発サイクルを加速させることを目的としています。**

質問や実装相談は、プロジェクト内の Issue / Discussion を利用してください。
