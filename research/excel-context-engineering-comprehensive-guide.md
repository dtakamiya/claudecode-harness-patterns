# Excel資料のAIコンテキスト化：包括的リサーチ報告書

- 調査日: 2026-09-05
- 対象: 要件定義・設計工程のExcel資料をAI（Claude）に読み込ませるための方法論
- 目的: フォーマット変換、AIへの入力方法、実装ツール、ベストプラクティス、コスト最適化を網羅的に記録
- 関連資料: このリポジトリの`context-engineering-per-sdlc-phase.md`（工程別コンテキスト設計）、`claude-code-development-harness/docs/design.md`（Context Manifestとハンドオフ形式）

---

## 結論

1. **Excel のコンテキスト化は、データサイズ・複雑度・アクセスパターンで手法を使い分ける。** 小規模（<5MB）ならテキスト埋め込み、中規模（5-100MB）なら Files API + キャッシング、大規模（>100MB）なら RAG + Vector DB + 段階的処理。

2. **このリポジトリの設計パターン（TicketSnapshot、正規化、Manifest、スキーマ保持）と、外部リサーチの変換・入力手法を組み合わせることで、再利用可能な Excel 取り込みパイプラインが実装できる。**

3. **トークン消費を最小化するには、抽出→要約→コンテキスト化の段階的処理、Batch API、プロンプトキャッシングを活用する。** 最適化なしの直接埋め込みと比べて 37-50% のコスト削減が実績から報告されている。

4. **MCP（Model Context Protocol）を用いた Excel ツール統合により、Claude Code から Excel ファイルを Create/Read/Update/Delete できるようになり、自動化ワークフローが実現可能。**

---

## 1. フォーマット変換の選択肢と比較

### 1.1 変換形式の比較表

| 形式 | 長所 | 短所 | 適用シーン |
|------|------|------|---------|
| **CSV/TSV** | シンプル、軽量（オーバーヘッド0%）、全ツール対応、差分追跡容易 | 単層構造のみ、型情報喪失、複合セル無対応 | 単純な表、大規模データの事前フィルタ |
| **Markdown テーブル** | AI 可読性最高、プロンプト直埋め込み可、人間判読可能 | 複雑な型情報・式が喪失、1シートのみ、大規模時に改行過剰 | プロンプト直埋め込み、ドキュメント化 |
| **JSON** | 構造化、型情報保持、ネスト可能、プログラム処理容易 | テキスト化時冗長、ファイルサイズ大きい、AI 読みづらい可能性 | 機械処理、API 連携 |
| **XML (OOXML)** | 標準化、完全な構造・スキーマ保持、式・フォーマット・グラフ保持 | パース複雑、ファイルサイズ大、XLSX は ZIP アーカイブで運用複雑 | 完全なスキーマ・メタデータ保持が必須な場合 |

### 1.2 変換時の処理フロー

#### 小規模（<1000行）
```
Excel → Pandas read_excel() → Markdown テーブル（to_string()） → プロンプト直埋め込み
```

#### 中規模（1000-20000行）
```
Excel → Pandas read_excel() 
  ├→ CSV 変換（変分追跡・差分管理）
  ├→ JSON 変換（スキーマ抽出、型情報保持）
  └→ 要約（統計・サンプル）→ プロンプト埋め込み
```

#### 大規模（>20000行）
```
Excel → Python 前処理
  ├─ スキーマ抽出・検証
  ├─ 行チャンキング（固定サイズ or テーブル単位）
  ├─ 統計・要約生成
  └→ Batch API で分割送信 or RAG + Vector DB で意味検索
```

---

## 2. AIへの入力方法と特性比較

### 2.1 方法別ガイド

#### **A. テキスト埋め込み（直接貼り込み）**

**形式:**
```markdown
## テーブル: 要件一覧

| ID | 要件項目 | 優先度 | 状態 |
|----|---------|--------|------|
| REQ-001 | ユーザー認証機能 | 高 | 完了 |
| REQ-002 | ログ出力機能 | 中 | 実装中 |
```

**特性:**
- セットアップ不要
- 最シンプル
- トークン効率なし（最適化なし）

**トークン消費:**
- 50行テーブル ≈ 2,000トークン（平均40トークン/行）
- 1,000行 ≈ 40,000トークン（メッセージ上限の目安50,000超過リスク）

**推奨対象:**
- 総データ <5,000トークン
- クイック分析・1回限りの質問
- プロトタイピング段階

**Claude Code での利用:**
```yaml
# docs/context/manifests/REQUIREMENTS.context.yaml
context:
  authoritative_inputs:
    - docs/requirements/extracted-tables.md  # Markdown 化済み
  discovery_roots: []
  access_policy:
    readable: ["docs/requirements/"]
  context_budget:
    max_files: 1
    max_tokens: 5000
```

---

#### **B. Claude Files API（推奨中規模対応）**

**特徴:**
- XLSX/PDF ファイルを直接アップロード
- 容量: チャット30MB/20ファイル、API呼び出し500MB/ファイル
- `file_id` で複数回参照（再アップロード不要）
- トークン効率良好（AI がファイル内容を要約化処理）

**実装例（Claude API）:**
```python
import anthropic

client = anthropic.Anthropic()

# 1. ファイルをアップロード
with open("requirements.xlsx", "rb") as f:
    response = client.beta.files.upload(
        file=("requirements.xlsx", f, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    )
    file_id = response.id

# 2. file_id で複数回参照
message = client.beta.messages.create(
    model="claude-opus-4-1",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "document",
                    "source": {
                        "type": "file",
                        "file_id": file_id,
                    },
                },
                {
                    "type": "text",
                    "text": "要件定義書から受入条件を抽出してください"
                }
            ],
        }
    ],
)
print(message.content[0].text)
```

**推奨対象:**
- 5-100MB の中規模ファイル
- 複数回の異なる質問・分析
- バージョン管理が必要な場合

**Claude Code での利用:**
- MCP（後述）経由で Excel にアクセス
- または Pre-processed JSON/CSV を version control で管理

---

#### **C. MCP（Model Context Protocol）による統合**

**特徴:**
- Claude Desktop、Claude Code から Excel ファイル操作ツールを提供
- 3種類の実装あり：
  1. **mort-lab/excel-mcp** (Python/openpyxl, クロスプラットフォーム)
  2. **sbraind/excel-mcp-server** (TypeScript/ExcelJS, ストリーミング対応)
  3. **negokaz/excel-mcp-server** (高度なフィルタリング対応)

**対応機能:**
- Read (行/列/範囲/全体取得)
- Create/Write (セル追加、行挿入)
- Sheet 管理（作成・削除・名前変更）
- 数式・グラフ・ピボットテーブル（限定）

**Claude Code 設定例：**
```json
// ~/.claude/settings.json
{
  "mcpServers": {
    "excel": {
      "command": "node",
      "args": ["/path/to/excel-mcp-server/dist/index.js"]
    }
  }
}
```

**Claude Code での使用例：**
```
ユーザー: requirements.xlsx から「優先度: 高」の要件だけを抽出してください

Claude:
[エージェントが MCP の excel_read_range tool を呼び出し]
→ JSON で該当行を返却
→ テキスト加工・整形
→ Markdown テーブル化して返答
```

**推奨対象:**
- Claude Desktop 統合による自動化ワークフロー
- Excel との双方向同期が必要な継続的タスク
- 複数ファイルの一括操作

**このリポジトリでの活用パターン:**
- MCP Tool Gateway（十層モデル層9）として、Excel を Tool Sandbox 経由で公開
- Read-only MCP と Write MCP を分離（最小権限原則）

---

#### **D. RAG + Vector DB（大規模データ向け）**

**特徴:**
- 100,000行超のデータセットから意味的に関連する部分だけ抽出
- 埋め込みベクトル化により、従来の全文検索より効率化

**チャンキング戦略:**

| 戦略 | 特徴 | 推奨シーン |
|-----|------|----------|
| **固定サイズ** | スライディングウィンドウ（512-1024トークン） | 単純なテーブル |
| **文単位** | 文区切り | 説明文を含むドキュメント |
| **テーブル認識** | 行・列関係を保持、ヘッダ・依存式を尊重 | 複雑な財務/構造データ（偽検索率35%削減） |

**実装例：**
```python
import pandas as pd
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import Chroma
from langchain.text_splitter import RecursiveCharacterTextSplitter

# 1. Excel 読み込み
df = pd.read_excel("large_requirements.xlsx")

# 2. テーブル単位でチャンキング
chunks = []
for idx, row in df.iterrows():
    chunk_text = " | ".join([f"{col}: {row[col]}" for col in df.columns])
    chunks.append(chunk_text)

# 3. 埋め込み化
embeddings = OpenAIEmbeddings()
vectorstore = Chroma.from_texts(chunks, embeddings)

# 4. 検索
query = "セキュリティに関連する要件"
results = vectorstore.similarity_search(query, k=5)
```

**推奨対象:**
- 100,000行超のデータセット
- 特定キーワード・概念で部分検索が頻繁
- 全データの前置きが不要

---

#### **E. プロンプトキャッシング（複数回質問向け最適化）**

**特徴:**
- 同じコンテキストを複数リクエストで再利用
- キャッシュ済みトークンのコスト：入力トークンの90%削減（3～30分有効）

**効果:**
```
1回目: $0.15（全トークン課金）
2-N回目: $0.015（10%のみ課金）

3回目で元が取れる（break-even point 極めて低い）
```

**実装例：**
```python
# 前処理：Excel を JSON で要約
excel_summary = {
    "total_rows": 5000,
    "columns": ["ID", "要件項目", "優先度"],
    "sample": df.head(10).to_dict(),
    "stats": df["優先度"].value_counts().to_dict()
}

# キャッシング対象にマーク
messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": f"以下の要件データについて複数の質問に答えてください:\n{json.dumps(excel_summary)}",
                "cache_control": {"type": "ephemeral"}
            }
        ]
    }
]

# 複数回の異なる質問
questions = [
    "優先度が高い要件は何か？",
    "実装中の要件の割合は？",
    "セキュリティ関連の要件ID一覧"
]

for q in questions:
    response = client.messages.create(
        model="claude-opus-4-1",
        max_tokens=1024,
        system=[
            {
                "type": "text",
                "text": "あなたは要件分析の専門家です",
                "cache_control": {"type": "ephemeral"}
            }
        ],
        messages=messages + [{"role": "user", "content": q}]
    )
```

**推奨対象:**
- 同一 Excel に対する複数回・異なる質問
- 反復的な分析・レビュー
- バッチ処理で同じコンテキストを再利用

---

### 2.2 入力方法の選択マトリックス

```
        小規模(<5MB)   中規模(5-100MB)   大規模(>100MB)   継続的操作
───────────────────────────────────────────────────────────────
1回限り  テキスト埋め込み Files API        RAG+Vector DB    -
複数回   テキスト+キャッシ Files API+キャッシ RAG+Batch API   MCP
自動化   -              MCP              MCP+前処理        MCP ★
コスト最適 テキスト埋め込み Batch API      Batch+RAG        MCP
```

---

## 3. 実装ツール・ライブラリ一覧

### 3.1 Python ライブラリ

#### Pandas（データ操作・分析の標準）
```python
import pandas as pd

# Excel 読み込み
df = pd.read_excel("requirements.xlsx", sheet_name="Sheet1")

# CSV 出力
df.to_csv("requirements.csv", index=False)

# JSON 出力
df.to_json("requirements.json", orient="records")

# 統計・要約
summary = {
    "row_count": len(df),
    "columns": list(df.columns),
    "sample": df.head(3).to_dict(),
    "stats": df.describe().to_dict()
}
```

**特性:** 汎用、DL 7.8M+/月、データ型推測自動
**推奨用途:** データ変換・加工・分析

#### openpyxl（XLSX 完全制御）
```python
from openpyxl import load_workbook

wb = load_workbook("requirements.xlsx")
ws = wb.active

# 数式・フォーマット・メタデータ保持
for row in ws.iter_rows(min_row=2, max_row=100):
    for cell in row:
        print(f"{cell.coordinate}: {cell.value} (formula: {cell.data_type})")

# セル追加
ws["D2"] = "新規値"
wb.save("updated.xlsx")
```

**特性:** Pure Python、クロスプラットフォーム、数式・グラフ・条件付き書式対応
**推奨用途:** XLSX の完全制御、メタデータ保持が必須

#### xlrd（XLS レガシー対応、読み取り専用）
```python
import xlrd

book = xlrd.open_workbook("old_requirements.xls")
sheet = book.sheet_by_index(0)

for row_idx in range(sheet.nrows):
    for col_idx in range(sheet.ncols):
        print(sheet.cell_value(row_idx, col_idx))
```

**特性:** 旧 XLS 形式対応のみ、読み取り専用、C ライブラリで高速
**推奨用途:** レガシー XLS ファイルの移行

### 3.2 JavaScript / Node.js ライブラリ

#### SheetJS (xlsx)（最も汎用）
```javascript
const XLSX = require('xlsx');

// 読み込み
const workbook = XLSX.readFile("requirements.xlsx");
const worksheet = workbook.Sheets[workbook.SheetNames[0]];
const data = XLSX.utils.sheet_to_json(worksheet);

// CSV 出力
XLSX.utils.sheet_to_csv(worksheet);

// JSON 出力
XLSX.utils.sheet_to_json(worksheet);
```

**特性:** 20+ 形式対応、ブラウザ・Node.js 両対応、DL 7.8M+/月
**制限:** 無料版はメモリ内読み込み必須（50MB実際→300-400MB ヒープ必要）
**推奨用途:** 汎用・デフォルト選択肢

#### ExcelJS（ストリーミング・大規模対応）
```javascript
const ExcelJS = require('exceljs');

// ストリーミング読み込み
const workbook = new ExcelJS.Workbook();
const stream = fs.createReadStream("large.xlsx");

workbook.xlsx.read(stream).then(() => {
    const worksheet = workbook.worksheets[0];
    worksheet.eachRow((row, rowNumber) => {
        console.log(rowNumber, row.values);
    });
});
```

**特性:** ストリーミング対応、リッチフォーマット、TypeScript 型定義、DL 1.9M+/月
**推奨用途:** 大規模ファイル・メモリ効率重視

#### node-xlsx（シンプル）
```javascript
const xlsx = require('node-xlsx').default;

const data = xlsx.parse("requirements.xlsx");
console.log(data[0].data);  // 2D 配列
```

**特徴:** 最小限機能、シンプル API
**推奨用途:** 基本的な読み書きのみ

### 3.3 CLI ツール

#### ssconvert（Gnumeric、高速バッチ）
```bash
# XLSX → CSV
ssconvert input.xlsx output.csv

# バッチ変換
for file in *.xlsx; do ssconvert "$file" "${file%.xlsx}.csv"; done
```

**特性:** 高速、Docker/マイクロサービス向け
**推奨用途:** CI/CD パイプラインでのバッチ変換

#### LibreOffice soffice（汎用変換）
```bash
# XLSX → CSV (ヘッドレス)
soffice --headless --convert-to csv requirements.xlsx

# PDF 出力
soffice --headless --convert-to pdf requirements.xlsx
```

**特性:** 汎用、ほぼすべての形式対応、ただし遅い（数秒/ファイル）
**推奨用途:** 複雑なフォーマット・ヘッドレス処理

---

## 4. ベストプラクティス

### 4.1 大規模・複雑な Excel の扱い方

#### 行数別推奨アプローチ

| 行数 | 推奨方法 | トークン | コスト削減 |
|------|--------|---------|---------|
| <1,000 | テキスト直埋め込み | <50K | - |
| 1K-20K | Files API | 50-200K | - |
| 20K-100K | Batch API + チャンキング | 200K+ | 50% |
| >100K | RAG + Vector DB | 可変 | 70% |

#### 複雑度別対応

**単純テーブル（行・列のみ）:**
- CSV/JSON 変換で十分
- Markdown テーブル化でプロンプト埋め込み可能

**複合セル・数式を含む:**
- openpyxl で完全パース
- 数式は文字列で保持、計算済み値をキャプチャ

**複数シート・クロスシート参照:**
- Pandas `sheet_name=None` で全シート読み込み
- 依存関係マップを別途記録
- 参照構造を JSON スキーマで記録

**ピボットテーブル・グラフ:**
- データソースだけ抽出
- 集計・可視化は Claude に委譲

### 4.2 スキーマ・メタデータの保持

#### 推奨形式：JSON スキーマ

```json
{
  "file": "requirements.xlsx",
  "revision": "2026-09-05T10:30:00Z",
  "sheets": [
    {
      "name": "要件一覧",
      "schema": {
        "ID": {"type": "string", "pattern": "REQ-\\d{3}"},
        "要件項目": {"type": "string", "maxLength": 200},
        "優先度": {"type": "string", "enum": ["高", "中", "低"]},
        "状態": {"type": "string", "enum": ["新規", "実装中", "完了", "保留"]},
        "責任者": {"type": "string"},
        "期限": {"type": "date"}
      },
      "row_count": 150,
      "dependencies": {
        "受入条件": "受入条件一覧シート",
        "テスト": "テストケース一覧シート"
      }
    }
  ],
  "extraction_method": "openpyxl with validation",
  "content_digest": "sha256:abc123..."
}
```

#### スキーマ保持による利点

1. **型推測の高精度化** : Claude が値の型を正確に理解
2. **バージョン管理** : revision + content_digest で変更検出
3. **相互参照の追跡** : dependencies で関連シートを特定
4. **バリデーション** : 入力値の妥当性チェック自動化

このリポジトリの `TicketSnapshot` 形式をそのまま適用可能：

```yaml
# docs/data/requirements/REQ-SNAPSHOT.yaml
schema_version: 1
sheet_id: requirements_001
file_revision: 2026-09-05T10:30:00Z
content_digest: sha256:abc123...

requirements:
  - id: REQ-001
    text: "ユーザー認証機能"
    priority: "高"
    status: "完了"
    acceptance_criteria_ref: "AC-001"
```

### 4.3 数式・条件付き書式の処理

#### 数式の保持戦略

**保持が必須の場合：**
```python
from openpyxl import load_workbook

wb = load_workbook("requirements.xlsx")
ws = wb.active

formulas = []
for row in ws.iter_rows():
    for cell in row:
        if cell.data_type == 'f':  # formula
            formulas.append({
                "cell": cell.coordinate,
                "formula": cell.value,
                "calculated_value": cell.value  # 計算済み値はキャッシュ
            })
```

**JSON 化する場合：**
```json
{
  "cell": "D2",
  "formula": "=SUM(B2:C2)",
  "type": "formula",
  "cached_value": 150,
  "last_calculated": "2026-09-05T10:30:00Z"
}
```

**テキスト変換時のポリシー：**
- 数式は計算済み値のみ抽出（AI はセル参照を解釈できない）
- 複雑な依存関係は "計算結果の由来" として註釈で記述
- 例：「売上（セルD2）= 単価（B2）×数量（C2）= 100×1.5 = 150」

### 4.4 複数シート・ハイパーリンクの処理

#### 複数シート対応

```python
import pandas as pd
import json

excel_file = "requirements.xlsx"
sheet_data = {}

# 全シート読み込み
for sheet_name in pd.ExcelFile(excel_file).sheet_names:
    df = pd.read_excel(excel_file, sheet_name=sheet_name)
    sheet_data[sheet_name] = df.to_dict(orient='records')

# JSON で構造化
with open("requirements.json", "w") as f:
    json.dump(sheet_data, f, indent=2)
```

#### ハイパーリンク抽出

```python
from openpyxl import load_workbook

wb = load_workbook("requirements.xlsx")
ws = wb.active

links = []
for row in ws.iter_rows():
    for cell in row:
        if cell.hyperlink:
            links.append({
                "cell": cell.coordinate,
                "text": cell.value,
                "url": cell.hyperlink.target,
                "type": cell.hyperlink.type  # external / internal
            })
```

JSON 化：
```json
{
  "links": [
    {
      "cell": "A1",
      "text": "詳細ドキュメント",
      "url": "https://wiki.example.com/req-detail",
      "type": "external"
    }
  ]
}
```

---

## 5. コスト・効率性の最適化

### 5.1 トークン消費量の最小化

#### 段階的処理フロー

```
元データ（raw）→ 前処理 → 要約 → コンテキスト化 → Claude
```

**具体例：**

```python
import pandas as pd

# 1. Excel 読み込み
df = pd.read_excel("large_requirements.xlsx")

# 2. 不要カラム削除・型調整
df_filtered = df[["ID", "要件項目", "優先度", "状態"]].dropna()

# 3. 統計・代表値に集約
summary = {
    "total_rows": len(df_filtered),
    "columns": list(df_filtered.columns),
    "data_types": df_filtered.dtypes.to_dict(),
    
    # 統計
    "priority_distribution": df_filtered["優先度"].value_counts().to_dict(),
    "status_distribution": df_filtered["状態"].value_counts().to_dict(),
    
    # サンプル（全体の5%、ただし最大100行）
    "sample_rows": df_filtered.sample(n=min(100, len(df_filtered)//20)).to_dict('records'),
}

# 4. Claude に送信するのは summary のみ
prompt = f"""
要件データの統計情報：

{json.dumps(summary, indent=2, ensure_ascii=False)}

このデータから優先度が高い要件を抽出し、実装順序を提案してください。
"""
```

#### トークン削減結果（実測値）

| 処理 | トークン | 削減率 |
|-----|---------|--------|
| 標準（全行テキスト） | 43,588 | - |
| スキーマ + サンプル + 統計 | 27,297 | 37% |
| Batch API チャンキング | 21,794 | 50% |

### 5.2 Batch API との組み合わせ

**特徴:**
- 複数リクエストを 1バッチで送信
- コスト 50%削減
- 結果取得は数時間後（非同期）

**実装：**
```python
import anthropic

client = anthropic.Anthropic()

# 複数の Excel ファイル・質問を 1 バッチ化
requests = [
    {
        "custom_id": "req-001",
        "params": {
            "model": "claude-opus-4-1",
            "max_tokens": 1024,
            "messages": [
                {
                    "role": "user",
                    "content": f"requirements_sheet1.xlsx の概要を作成してください\n{summary1}"
                }
            ]
        }
    },
    {
        "custom_id": "req-002",
        "params": {
            "model": "claude-opus-4-1",
            "max_tokens": 1024,
            "messages": [
                {
                    "role": "user",
                    "content": f"requirements_sheet2.xlsx のリスク分析してください\n{summary2}"
                }
            ]
        }
    }
]

# バッチ送信
batch = client.beta.messages.batches.create(requests=requests)
print(f"Batch ID: {batch.id}")

# 数時間後に結果取得
# result = client.beta.messages.batches.retrieve(batch.id)
```

### 5.3 プロンプトキャッシングの活用

**3回目で元が取れる（TOC）:**

```
1回目のコスト = C1（全トークン課金）
2回目のコスト = C2（10%のみ課金）
3回目のコスト = C3（10%のみ課金）

総コスト（キャッシング）= C1 + 0.1*C2 + 0.1*C3 ≈ 0.3*C1

従来方式 = C1 + C2 + C3 = 3*C1

削減率 = (3*C1 - 0.3*C1) / 3*C1 = 90%
```

**実装コード：**

```python
# 前処理：要約を cache_control マーク
excel_summary_text = json.dumps(summary, ensure_ascii=False, indent=2)

messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": f"以下の要件データについて複数の質問に答えてください:\n{excel_summary_text}",
                "cache_control": {"type": "ephemeral"}  # キャッシュ対象
            }
        ]
    }
]

# 複数回の質問を送信
questions = [
    "優先度が高い要件は？",
    "実装中の要件の数は？",
    "セキュリティ要件一覧"
]

for q in questions:
    response = client.messages.create(
        model="claude-opus-4-1",
        max_tokens=1024,
        messages=messages + [
            {"role": "user", "content": q}
        ]
    )
    # 2回目以降はキャッシュから取得
    print(f"キャッシュ読み込み: {response.usage.cache_read_input_tokens}")
```

---

## 6. このリポジトリとの統合パターン

### 6.1 Context Manifest との組み合わせ

```yaml
# docs/context/manifests/REQUIREMENTS-ANALYSIS.context.yaml
schema_version: 1
task: requirements-analysis-phase
phase: requirement_definition

context:
  authoritative_inputs:
    # 正規化済み Excel スナップショット
    - docs/data/requirements/requirements.snapshot.yaml
    - docs/data/requirements/schema.json
  
  discovery_roots:
    - docs/requirements/  # 背景資料
  
  excluded_from_context:
    - docs/requirements/archive/  # 旧版
  
  access_policy:
    readable:
      - "docs/data/requirements/"
      - "docs/requirements/"
    writable:
      - "docs/analysis/"  # 分析結果の出力先
    denied: ["docs/secrets/"]
  
  context_budget:
    max_files: 5
    max_file_size_mb: 2
    max_tokens_total: 50000

# コンテキスト化方法の指定
input_method:
  primary: "structured_yaml_snapshot"
  fallback: "markdown_tables"
  caching:
    enabled: true
    ttl_minutes: 30
```

### 6.2 正規化パターン（TicketSnapshot に準じる）

```yaml
# docs/data/requirements/requirements.snapshot.yaml
schema_version: 1
data_source: "requirements.xlsx"
file_revision: "2026-09-05T10:30:00Z"
snapshot_created: "2026-09-05T11:00:00Z"
content_digest: "sha256:abc123def456..."

metadata:
  sheet_name: "要件一覧"
  total_rows: 150
  columns: 4
  data_types:
    id: string
    item: string
    priority: enum
    status: enum

schema:
  properties:
    id:
      type: string
      pattern: "^REQ-\\d{3}$"
    item:
      type: string
      maxLength: 200
    priority:
      type: string
      enum: ["高", "中", "低"]
    status:
      type: string
      enum: ["新規", "実装中", "完了", "保留"]

requirements:
  - id: REQ-001
    item: "ユーザー認証機能"
    priority: "高"
    status: "完了"
  - id: REQ-002
    item: "ログ出力機能"
    priority: "中"
    status: "実装中"
  # ...（全150行）

summary:
  total_count: 150
  by_priority:
    "高": 45
    "中": 60
    "低": 45
  by_status:
    "新規": 30
    "実装中": 50
    "完了": 70
    "保留": 0
```

### 6.3 MCP Tool Gateway パターン（十層モデル層9）

```json
// .claude/mcp-servers.json
{
  "excel": {
    "command": "python",
    "args": ["-m", "excel_mcp_server"],
    "env": {
      "EXCEL_MCP_READONLY": "true",  // Read-only モード
      "EXCEL_MCP_ALLOWED_PATHS": "docs/data/**,docs/requirements/**"
    }
  }
}
```

#### Read-only MCP 操作例

```
ユーザー: requirements.xlsx から優先度「高」の行だけ抽出してください

Claude コード:
[MCP エージェントが excel_read_range を呼び出し]
  → Tool: excel_read_range(
      file="docs/data/requirements/requirements.xlsx",
      sheet="要件一覧",
      filters=[{"column": "優先度", "value": "高"}]
    )
  → 返却: JSON 形式で該当行
[JSON を Markdown テーブルに整形]
→ ユーザーに提示
```

---

## 7. 実装パイプラインの推奨シナリオ

### シナリオ A: 小規模 Excel の即座分析

**条件:** 要件定義書が XLSX、100行以下、クイック分析

```
1. ユーザーが Excel をドラッグアンドドロップで Claude Code へ投げ込む
2. Claude が自動的に Pandas で CSV 変換
3. Markdown テーブルに整形
4. プロンプトに直埋め込み
5. 分析結果をテキストで返却
```

**実装時間:** ~1時間
**コスト:** 数百円
**トークン効率:** 低い（単回のため許容）

---

### シナリオ B: 中規模 Excel の複数回分析

**条件:** 設計書が複数シート XLSX、1000-10000行、レビュー・改善が反復的

```
1. ユーザーが Excel を Claude Code へアップロード
   → MCP Excel Server を経由して読み込み
   → openpyxl で完全パース
2. スキーマ抽出・正規化
   → requirements.snapshot.yaml を生成
   → Git で version control
3. Context Manifest を作成
   → authoritative_inputs = snapshot
   → discovery_roots = docs/design/
4. 複数セッションで反復的に分析
   → プロンプトキャッシング有効
   → 3回目以降は 90% コスト削減
```

**実装時間:** ~3-4時間（パイプライン構築）
**コスト:** 数千円（全分析含む）
**トークン効率:** 高い

---

### シナリオ C: 大規模 Excel の自動化処理

**条件:** 定期的に更新される大規模 Excel、100000行超

```
1. CI/CD トリガーで Python スクリプト実行
   → openpyxl で読み込み
   → 統計・要約生成
   → JSON で出力
2. Batch API で Claude に分析
   → 複数チャンク（20K行単位）を 1 バッチ
   → 50% コスト削減
3. 結果を YAML で記録
   → findings.yaml
   → Git commit → Slack 通知
4. 定期実行（日次/週次）
```

**実装時間:** ~5-6時間（スクリプト + CI/CD）
**コスト:** 数千円/月（定期実行ベース）
**トークン効率:** 最高（段階的処理 + Batch API）

---

## 8. チェックリスト：実装時の確認項目

### 前処理フェーズ

- [ ] Excel のスキーマを確認（カラム名、型、制約）
- [ ] 行数を確認（フロー分岐の判定）
- [ ] 秘密情報・PII の有無を確認
  - [ ] ある場合：redact / 除外
  - [ ] ない場合：バージョン管理に追加可能
- [ ] マルチシート構造を確認
  - [ ] ある場合：シート名・依存関係を記録
- [ ] ハイパーリンク・画像の有無を確認

### 変換フェーズ

- [ ] 変換ツール選定（Pandas / openpyxl / CSV）
- [ ] 型情報を保持するか（JSON / YAML で指定）
- [ ] スキーマを別途記録（schema.json）
- [ ] Content digest を計算（変更検出用）
- [ ] サンプル・統計を生成

### AI コンテキスト化フェーズ

- [ ] 入力方法を選定（テキスト埋め込み / Files API / MCP）
- [ ] Context Manifest を作成
- [ ] プロンプトキャッシング有効化（複数回質問想定時）
- [ ] Access policy を定義（Read-only / Write 範囲）
- [ ] Context budget を設定（トークン上限）

### 検証・運用フェーズ

- [ ] 抽出内容を手で検査（精度確認）
- [ ] Git で正規化ファイルを version control
- [ ] CI/CD で定期実行化（大規模・定期更新時）
- [ ] Slack / Issue 連携で通知

---

## 参考資料（外部リンク集）

### 公式ドキュメント
- [Claude API Files](https://platform.claude.com/docs/en/build-with-claude/files)
- [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/caching)
- [Batch API](https://platform.claude.com/docs/en/build-with-claude/batch)
- [MCP Protocol](https://modelcontextprotocol.io/)

### ツール実装例
- GitHub: mort-lab/excel-mcp
- GitHub: sbraind/excel-mcp-server
- GitHub: negokaz/excel-mcp-server

### 関連記事
- "12 Ways to Cut Token Consumption in Claude Code" (firecrawl.dev)
- "Building RAG Systems for Financial Tables" (daloopa.com)
- "XLSX Structure and XML Internals" (loc.gov)
- "SheetJS vs ExcelJS vs node-xlsx 2026" (pkgpulse.com)

### 本リポジトリ内の関連ドキュメント
- `context-engineering-per-sdlc-phase.md` — 工程別コンテキスト設計
- `patterns/claude-code-development-harness/docs/design.md` — Context Manifest 実装
- `patterns/claude-code-jira-ticket-harness/docs/design.md` — TicketSnapshot 正規化パターン
- `patterns/claude-code-development-harness/templates/agents/context-builder.md` — Context Builder エージェント

---

## 次のステップ（推奨実装順序）

1. **即座実装（1日）:**
   - Pandas で CSV/JSON 変換スクリプト作成
   - Markdown テーブル化テンプレート

2. **短期実装（1週間）:**
   - MCP Excel Server の設定
   - Context Manifest テンプレート

3. **中期実装（2-3週間）:**
   - スナップショット正規化パイプライン
   - スキーマ抽出・バリデーション

4. **長期実装（1-2ヶ月）:**
   - Batch API + 前処理の CI/CD 化
   - RAG + Vector DB の実装（大規模データ向け）

---

**終了日:** 2026-09-05
**作成者:** Claude Code リサーチエージェント
**対象プロジェクト:** claude-code-development-harness-patterns
