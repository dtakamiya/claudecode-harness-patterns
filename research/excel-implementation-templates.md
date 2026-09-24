# Excel コンテキスト化：実装テンプレート集

このドキュメントは、`excel-context-engineering-comprehensive-guide.md` の理論を実装するための実行可能なテンプレート・スクリプト・設定ファイルをまとめたものです。

---

## テンプレート 1: Python 変換パイプライン

### ファイル: `scripts/excel_to_context.py`

```python
#!/usr/bin/env python3
"""
Excel を AI コンテキスト化形式に変換するパイプライン

使用方法:
  python excel_to_context.py input.xlsx --format json --output output.json
  python excel_to_context.py input.xlsx --format markdown --max-rows 1000
  python excel_to_context.py input.xlsx --format snapshot --schema
"""

import argparse
import json
import sys
import hashlib
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any

import pandas as pd
import yaml

def calculate_digest(df: pd.DataFrame) -> str:
    """DataFrame のコンテント ダイジェストを計算"""
    content = df.to_csv(index=False).encode('utf-8')
    return f"sha256:{hashlib.sha256(content).hexdigest()}"

def extract_schema(df: pd.DataFrame) -> Dict[str, Any]:
    """DataFrame からスキーマを抽出"""
    schema = {
        "properties": {},
        "required": []
    }
    
    for col in df.columns:
        dtype_str = str(df[col].dtype)
        
        # 型推測
        if "int" in dtype_str:
            col_type = "integer"
        elif "float" in dtype_str:
            col_type = "number"
        elif "datetime" in dtype_str:
            col_type = "string"
            col_type_format = "date-time"
        elif "object" in dtype_str:
            col_type = "string"
        else:
            col_type = "string"
        
        # Null 値をチェック
        if df[col].isnull().sum() == 0:
            schema["required"].append(col)
        
        schema["properties"][col] = {
            "type": col_type,
            "description": f"{col} (from Excel)"
        }
    
    return schema

def to_markdown_table(df: pd.DataFrame, max_rows: int = 100) -> str:
    """DataFrame を Markdown テーブルに変換"""
    if len(df) > max_rows:
        df = pd.concat([df.head(max_rows // 2), df.tail(max_rows // 2)])
        df = df.reset_index(drop=True)
    
    markdown = df.to_markdown(index=False)
    return f"## データテーブル\n\n{markdown}\n"

def to_json_with_schema(df: pd.DataFrame, include_schema: bool = True) -> Dict[str, Any]:
    """DataFrame を JSON（スキーマ付き）に変換"""
    result = {
        "metadata": {
            "rows": len(df),
            "columns": len(df.columns),
            "extracted_at": datetime.now().isoformat()
        },
        "data": df.to_dict('records')
    }
    
    if include_schema:
        result["schema"] = extract_schema(df)
    
    return result

def to_snapshot_yaml(
    excel_path: str,
    df: pd.DataFrame,
    sheet_name: str = "Sheet1"
) -> Dict[str, Any]:
    """DataFrame を正規化スナップショット（YAML 形式）に変換"""
    
    snapshot = {
        "schema_version": 1,
        "data_source": str(excel_path),
        "sheet_name": sheet_name,
        "file_revision": datetime.now().isoformat(),
        "snapshot_created": datetime.now().isoformat(),
        "content_digest": calculate_digest(df),
        
        "metadata": {
            "total_rows": len(df),
            "columns": len(df.columns),
            "columns_list": list(df.columns)
        },
        
        "schema": extract_schema(df),
        
        # 統計情報
        "statistics": {
            "row_count": len(df),
            "column_count": len(df.columns),
            "null_counts": df.isnull().sum().to_dict()
        },
        
        # サンプル（全体の 5% または最大 50 行）
        "sample_rows": df.sample(
            n=min(50, max(1, len(df) // 20)),
            random_state=42
        ).to_dict('records'),
        
        # 実際のデータ
        "data": df.to_dict('records')
    }
    
    return snapshot

def main():
    parser = argparse.ArgumentParser(
        description="Excel を AI コンテキスト化形式に変換"
    )
    parser.add_argument("input", help="入力 Excel ファイル")
    parser.add_argument(
        "--format",
        choices=["json", "markdown", "snapshot", "csv"],
        default="json",
        help="出力形式（デフォルト: json）"
    )
    parser.add_argument("--output", "-o", help="出力ファイルパス")
    parser.add_argument("--sheet", "-s", default=None, help="シート名")
    parser.add_argument("--max-rows", type=int, default=1000, help="最大行数")
    parser.add_argument("--schema", action="store_true", help="スキーマを含める")
    
    args = parser.parse_args()
    
    # ファイル読み込み
    try:
        if args.sheet:
            df = pd.read_excel(args.input, sheet_name=args.sheet)
        else:
            df = pd.read_excel(args.input)
        
        print(f"✓ 読み込み完了: {len(df)} 行, {len(df.columns)} 列", file=sys.stderr)
    except Exception as e:
        print(f"✗ エラー: {e}", file=sys.stderr)
        sys.exit(1)
    
    # 変換
    if args.format == "json":
        output = json.dumps(
            to_json_with_schema(df, include_schema=args.schema),
            indent=2,
            ensure_ascii=False
        )
    elif args.format == "markdown":
        output = to_markdown_table(df, max_rows=args.max_rows)
    elif args.format == "snapshot":
        output = yaml.dump(
            to_snapshot_yaml(args.input, df, sheet_name=args.sheet or "Sheet1"),
            allow_unicode=True,
            sort_keys=False
        )
    elif args.format == "csv":
        output = df.to_csv(index=False)
    
    # 出力
    if args.output:
        Path(args.output).write_text(output, encoding='utf-8')
        print(f"✓ 出力完了: {args.output}", file=sys.stderr)
    else:
        print(output)

if __name__ == "__main__":
    main()
```

---

## テンプレート 2: Context Manifest 設定

### ファイル: `docs/context/manifests/REQUIREMENTS.context.yaml`

```yaml
# Context Manifest: 要件定義フェーズ
#
# 用途: 要件定義・要件レビュー工程で、AI エージェントに提供するコンテキストを定義
# 正本: このファイルと docs/data/requirements/ 以下のスナップショット
# 自動生成: scripts/excel_to_context.py で生成

schema_version: 1

task: requirements-definition
phase: PHASE-2
created: "2026-09-05T11:00:00Z"
last_updated: "2026-09-05T11:00:00Z"
revision: 1

context:
  # 権威ある入力（最初に読むべき正式文書）
  authoritative_inputs:
    - docs/data/requirements/requirements.snapshot.yaml
    - docs/requirements/requirements.md
    - docs/requirements/acceptance_criteria.md
  
  # 実行時探索の起点（ツールで動的に探索される）
  discovery_roots:
    - docs/requirements/
    - docs/project/constraints.md
  
  # 明示的に除外（読み込まない）
  excluded_from_context:
    - docs/requirements/archive/
    - docs/requirements/*.backup.md
    - "**/*.tmp"
  
  # アクセス制御（Permission と連動）
  access_policy:
    readable:
      - docs/data/requirements/
      - docs/requirements/
      - docs/project/
    writable:
      - docs/analysis/requirements-analysis/
    denied:
      - docs/secrets/
      - docs/credentials/
  
  # コンテキストバジェット（トークン、ファイル数の上限）
  context_budget:
    max_files: 10
    max_file_size_mb: 5
    max_tokens_per_file: 15000
    max_tokens_total: 50000

# 入力フォーマット・最適化の指定
input_method:
  primary: "structured_yaml_snapshot"
  schema_format: "json-schema"
  fallback: "markdown_tables"
  
  # プロンプトキャッシング有効化（複数セッション想定）
  caching:
    enabled: true
    ttl_minutes: 30
    cache_keys:
      - "schema"
      - "statistics"
      - "sample_rows"

# 期待される成果物
outputs:
  - docs/analysis/requirements-analysis/extracted-requirements.yaml
  - docs/analysis/requirements-analysis/priority-matrix.md
  - docs/decisions/ADR-*.md

# ハンドオフ先
next_phase: PHASE-3
handed_off_to: design-architect
```

---

## テンプレート 3: スナップショット正規化（YAML 形式）

### ファイル: `docs/data/requirements/requirements.snapshot.yaml`

```yaml
# Excel スナップショット（正規化形式）
#
# 用途: 要件定義書を YAML 化し、バージョン管理・AI 入力の正本とする
# 生成: scripts/excel_to_context.py --format snapshot --schema
# 更新頻度: 要件変更時（Git で追跡）

schema_version: 1

# ソース情報
data_source:
  file: "requirements.xlsx"
  path: "要件一覧"  # シート名
  file_revision: "2026-09-05T10:30:00Z"
  snapshot_created: "2026-09-05T11:00:00Z"
  source_url: "https://sharepoint.example.com/requirements.xlsx"

# コンテント完全性チェック
integrity:
  content_digest: "sha256:abc123def456789..."
  row_count: 150
  column_count: 4
  last_verified: "2026-09-05T11:00:00Z"

# スキーマ定義（AI が値を正確に型解釈できるように）
schema:
  $schema: "http://json-schema.org/draft-07/schema#"
  type: object
  properties:
    id:
      type: string
      pattern: "^REQ-\\d{3}$"
      description: "要件一意識別子"
    item:
      type: string
      maxLength: 200
      description: "要件の項目名または説明"
    priority:
      type: string
      enum: ["高", "中", "低"]
      description: "実装優先度"
    status:
      type: string
      enum: ["新規", "実装中", "完了", "保留", "キャンセル"]
      description: "現在の実装状態"
  required: ["id", "item", "priority", "status"]

# メタデータ
metadata:
  total_rows: 150
  columns: ["ID", "要件項目", "優先度", "状態"]
  data_types:
    id: string
    item: string
    priority: enum
    status: enum
  
  # 関連ドキュメント
  related_documents:
    - docs/requirements/requirements.md  # 詳細説明
    - docs/requirements/acceptance_criteria.md  # 受入基準
    - docs/design/design.md  # 設計ドキュメント
  
  # テスト関連
  test_mapping:
    test_suite: "tests/requirements/"
    test_framework: "pytest"

# 統計情報（AI が「全体像」を効率的に理解）
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
    "キャンセル": 0
  
  estimated_effort:
    high_priority_items: 45
    estimated_dev_days: 90
    estimated_test_days: 30

# サンプルデータ（全体の 5%、ただし最大 50 行）
samples:
  - id: "REQ-001"
    item: "ユーザー認証機能"
    priority: "高"
    status: "完了"
  
  - id: "REQ-002"
    item: "ログ出力機能"
    priority: "中"
    status: "実装中"
  
  - id: "REQ-048"
    item: "データベース接続プーリング"
    priority: "中"
    status: "新規"
  
  # ...（計 50 行または全体の 5%）

# 完全データ（すべての行）
data:
  - id: "REQ-001"
    item: "ユーザー認証機能（OAuth 2.0）"
    priority: "高"
    status: "完了"
  
  - id: "REQ-002"
    item: "ログ出力機能（JSON フォーマット）"
    priority: "中"
    status: "実装中"
  
  - id: "REQ-003"
    item: "エラーハンドリング（400/500 レスポンス）"
    priority: "高"
    status: "新規"
  
  # ... 全 150 行
  
  - id: "REQ-150"
    item: "ドキュメント生成（Swagger/OpenAPI）"
    priority: "低"
    status: "新規"

# 変更履歴（append-only）
changelog:
  - revision: 1
    timestamp: "2026-09-05T11:00:00Z"
    author: "context-builder-agent"
    changes:
      - "初回スナップショット作成"
      - "150 行の要件を正規化"
      - "スキーマ定義を追加"
```

---

## テンプレート 4: MCP Excel Server 設定

### ファイル: `.claude/mcp-servers.json`

```json
{
  "mcpServers": {
    "excel-readonly": {
      "command": "python",
      "args": ["-m", "excel_mcp_server"],
      "env": {
        "EXCEL_MCP_MODE": "readonly",
        "EXCEL_MCP_ALLOWED_PATHS": "docs/data/**:docs/requirements/**:docs/design/**",
        "EXCEL_MCP_MAX_FILE_SIZE": "104857600",
        "EXCEL_MCP_TIMEOUT": "30"
      },
      "description": "Excel ファイルの読み取り専用アクセス（MCP）"
    },
    
    "excel-readwrite": {
      "command": "python",
      "args": ["-m", "excel_mcp_server"],
      "env": {
        "EXCEL_MCP_MODE": "readwrite",
        "EXCEL_MCP_ALLOWED_PATHS": "docs/analysis/**:docs/data/outputs/**",
        "EXCEL_MCP_MAX_FILE_SIZE": "104857600",
        "EXCEL_MCP_TIMEOUT": "30",
        "EXCEL_MCP_BACKUP_BEFORE_WRITE": "true"
      },
      "description": "Excel ファイルの読み書きアクセス（分析結果出力専用）"
    }
  }
}
```

### インストール

```bash
# 1. MCP サーバーをインストール
pip install excel-mcp-server

# 2. Claude Code 設定ディレクトリに配置
mkdir -p ~/.claude
cp .claude/mcp-servers.json ~/.claude/

# 3. Claude Code 再起動
# (Desktop app: コマンドパレット → "Claude Code: Reload"
#  CLI: 新しいセッション開始)
```

---

## テンプレート 5: Batch API 処理スクリプト

### ファイル: `scripts/excel_batch_analysis.py`

```python
#!/usr/bin/env python3
"""
複数の Excel ファイルをバッチ処理で Claude に分析させる

コスト削減: 50% (synchronous API 比)
適用対象: 中〜大規模ファイル、非同期処理で OK な場合

使用方法:
  python excel_batch_analysis.py --input "docs/data/*.xlsx" --batch-size 10
"""

import json
import argparse
import time
from pathlib import Path
from typing import List, Dict, Any

import anthropic
import pandas as pd

def chunk_dataframe(df: pd.DataFrame, chunk_size: int = 5000) -> List[Dict[str, Any]]:
    """DataFrame を chunk_size 行単位で分割"""
    chunks = []
    for i in range(0, len(df), chunk_size):
        chunk = df.iloc[i:i+chunk_size]
        chunks.append({
            "start_row": i,
            "end_row": min(i + chunk_size, len(df)),
            "data": chunk.to_dict('records'),
            "sample_count": min(5, len(chunk))
        })
    return chunks

def create_batch_request(
    file_path: str,
    chunk_idx: int,
    chunk_info: Dict[str, Any],
    analysis_type: str = "requirements"
) -> Dict[str, Any]:
    """バッチリクエストエントリを作成"""
    
    if analysis_type == "requirements":
        prompt = f"""
以下は要件定義書の一部（行 {chunk_info['start_row']}-{chunk_info['end_row']}）です。

スキーマ：
- ID: 要件一意識別子
- 要件項目: 実装内容
- 優先度: 高/中/低
- 状態: 新規/実装中/完了/保留

データサンプル（最初の 5 行）:
{json.dumps(chunk_info['data'][:chunk_info['sample_count']], indent=2, ensure_ascii=False)}

タスク:
1. この部分の要件を分類（セキュリティ/パフォーマンス/UI など）
2. 優先度別に整理
3. 実装リスク（高/中/低）を評価
4. JSON 形式で結果を返却

出力形式:
```json
{{
  "chunk_id": {chunk_idx},
  "classifications": [...],
  "priority_groups": {...},
  "risks": [...]
}}
```
"""
    else:
        prompt = f"Analyze chunk {chunk_idx} of {file_path}"
    
    return {
        "custom_id": f"{Path(file_path).stem}-chunk-{chunk_idx:03d}",
        "params": {
            "model": "claude-opus-4-1",
            "max_tokens": 2048,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }
    }

def submit_batch(client: anthropic.Anthropic, requests: List[Dict[str, Any]]) -> str:
    """バッチを Claude API に送信"""
    batch = client.beta.messages.batches.create(requests=requests)
    print(f"✓ バッチ送信完了: ID={batch.id}, リクエスト数={len(requests)}")
    return batch.id

def retrieve_batch_results(client: anthropic.Anthropic, batch_id: str) -> Dict[str, Any]:
    """バッチ処理結果を取得"""
    max_wait = 300  # 5 分
    wait_interval = 5
    elapsed = 0
    
    while elapsed < max_wait:
        batch = client.beta.messages.batches.retrieve(batch_id)
        
        if batch.processing_status == "succeeded":
            print(f"✓ バッチ処理完了: ID={batch.id}")
            results = {}
            for message in batch.messages:
                results[message.custom_id] = json.loads(
                    message.content[0].text
                )
            return results
        elif batch.processing_status == "failed":
            print(f"✗ バッチ失敗: {batch.error_message}")
            return {}
        
        print(f"  待機中... ({elapsed}/{max_wait}秒)")
        time.sleep(wait_interval)
        elapsed += wait_interval
    
    print(f"✗ タイムアウト: バッチ {batch_id} が {max_wait} 秒以内に完了しませんでした")
    return {}

def main():
    parser = argparse.ArgumentParser(
        description="Excel ファイルをバッチ分析"
    )
    parser.add_argument(
        "--input",
        required=True,
        help="入力 Excel ファイル（glob パターン対応）"
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=10,
        help="1 バッチあたりのリクエスト数"
    )
    parser.add_argument(
        "--chunk-rows",
        type=int,
        default=5000,
        help="Excel を分割する行数"
    )
    parser.add_argument(
        "--output",
        "-o",
        default="batch_results.json",
        help="出力ファイル"
    )
    parser.add_argument(
        "--wait",
        action="store_true",
        help="バッチ完了を待つ（デフォルト: 送信のみ）"
    )
    
    args = parser.parse_args()
    
    # ファイル探索
    input_path = Path(args.input)
    excel_files = []
    
    if "*" in str(input_path):
        excel_files = list(Path(".").glob(input_path))
    else:
        excel_files = [Path(input_path)]
    
    print(f"✓ 対象ファイル: {len(excel_files)} 個")
    
    # バッチリクエスト作成
    all_requests = []
    chunk_metadata = {}
    
    for file_path in excel_files:
        df = pd.read_excel(file_path)
        chunks = chunk_dataframe(df, chunk_size=args.chunk_rows)
        
        for chunk_idx, chunk in enumerate(chunks):
            request = create_batch_request(
                str(file_path),
                chunk_idx,
                chunk
            )
            all_requests.append(request)
            
            chunk_metadata[request["custom_id"]] = {
                "file": str(file_path),
                "chunk": chunk_idx,
                "rows": (chunk["start_row"], chunk["end_row"])
            }
    
    print(f"✓ リクエスト生成: {len(all_requests)} 件")
    
    # バッチ送信
    client = anthropic.Anthropic()
    batch_ids = []
    
    for i in range(0, len(all_requests), args.batch_size):
        batch_requests = all_requests[i:i+args.batch_size]
        batch_id = submit_batch(client, batch_requests)
        batch_ids.append(batch_id)
    
    # 完了待ち（オプション）
    if args.wait:
        all_results = {}
        for batch_id in batch_ids:
            results = retrieve_batch_results(client, batch_id)
            all_results.update(results)
        
        # 結果を出力
        output_data = {
            "batch_ids": batch_ids,
            "total_requests": len(all_requests),
            "metadata": chunk_metadata,
            "results": all_results
        }
        
        Path(args.output).write_text(
            json.dumps(output_data, indent=2, ensure_ascii=False),
            encoding='utf-8'
        )
        print(f"✓ 結果を保存: {args.output}")
    else:
        print(f"✓ バッチ ID（結果取得用）: {batch_ids}")
        print(f"  結果取得: python retrieve_batch.py {' '.join(batch_ids)}")

if __name__ == "__main__":
    main()
```

---

## テンプレート 6: CI/CD パイプライン（GitHub Actions）

### ファイル: `.github/workflows/excel-context-sync.yaml`

```yaml
name: Excel Context Sync

on:
  schedule:
    # 毎日 10:00 UTC に実行
    - cron: "0 10 * * *"
  
  workflow_dispatch:
    inputs:
      excel_files:
        description: "処理対象（デフォルト: docs/data/*.xlsx）"
        default: "docs/data/*.xlsx"

jobs:
  sync:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - uses: actions/setup-python@v4
        with:
          python-version: "3.11"
      
      - name: Install dependencies
        run: |
          pip install pandas openpyxl pyyaml
      
      - name: Convert Excel to YAML snapshots
        run: |
          python scripts/excel_to_context.py \
            docs/data/requirements.xlsx \
            --format snapshot \
            --schema \
            --output docs/data/requirements/requirements.snapshot.yaml
      
      - name: Convert Excel to JSON
        run: |
          python scripts/excel_to_context.py \
            docs/data/requirements.xlsx \
            --format json \
            --schema \
            --output docs/data/requirements/requirements.json
      
      - name: Generate schema files
        run: |
          python -c "
import json, yaml
df_dict = json.load(open('docs/data/requirements/requirements.json'))
schema = df_dict.get('schema', {})
with open('docs/data/requirements/schema.json', 'w') as f:
    json.dump(schema, f, indent=2, ensure_ascii=False)
          "
      
      - name: Commit changes
        run: |
          git config user.name "Excel Sync Bot"
          git config user.email "bot@example.com"
          git add docs/data/requirements/
          git diff --cached --quiet || git commit -m "chore: sync Excel snapshots ($(date -u +'%Y-%m-%d %H:%M:%S UTC'))"
      
      - name: Push changes
        run: |
          git push origin HEAD:main
```

---

## テンプレート 7: AI エージェント用 Skill（claude-code）

### ファイル: `.claude/skills/excel-analyzer.md`

```markdown
# Excel Analyzer Skill

Excel ファイルをコンテキスト化し、AI 分析可能な形式に変換する

## 前提条件

- Python 3.9+
- `pandas`, `openpyxl`, `pyyaml` インストール
- `scripts/excel_to_context.py` が利用可能

## 手順

### 1. スナップショット生成

```bash
python scripts/excel_to_context.py {excel_file} \
  --format snapshot \
  --schema \
  --output {output_path}
```

**出力:** YAML ファイル（スキーマ + サンプル + 統計情報）

### 2. Context Manifest 作成

`docs/context/manifests/{TASK_NAME}.context.yaml` を作成し、以下を指定：

- `authoritative_inputs`: スナップショット YAML パス
- `discovery_roots`: 背景資料のディレクトリ
- `access_policy`: 読み取り範囲
- `context_budget`: トークン上限

### 3. MCP 接続確認

```bash
claude --check-mcp excel-readonly
```

レスポンス例：
```
✓ excel-readonly: connected
  available tools: excel_read, excel_read_range, excel_list_sheets
```

### 4. エージェント実行

```bash
claude << 'EOF'
@excel-readonly
requirements.xlsx から優先度が高い要件を 10 件抽出してください
EOF
```

## トラブルシューティング

### MCP 接続エラー

```bash
# MCP サーバー再起動
python -m excel_mcp_server &
```

### スナップショット生成失敗

```bash
# 詳細ログを確認
python scripts/excel_to_context.py input.xlsx -v
```

### メモリ不足（大規模ファイル）

```bash
# チャンキング処理を使用
python scripts/excel_batch_analysis.py --input input.xlsx --chunk-rows 5000
```

## 関連資料

- `excel-context-engineering-comprehensive-guide.md`
- `.claude/mcp-servers.json`
- `scripts/excel_to_context.py`
```

---

## チェックリスト：導入時の確認項目

### 環境準備
- [ ] Python 3.9+ がインストール済み
- [ ] `pip install pandas openpyxl pyyaml anthropic` を実行
- [ ] `scripts/excel_to_context.py` を配置
- [ ] `.claude/mcp-servers.json` を配置

### ファイル構成確認
- [ ] `docs/data/requirements/` ディレクトリを作成
- [ ] `docs/context/manifests/` ディレクトリを作成
- [ ] Context Manifest テンプレートを配置

### MCP 設定確認
- [ ] `python -m excel_mcp_server --version` でバージョン確認
- [ ] Claude Code で MCP 接続テスト
- [ ] Read-only / ReadWrite モード動作確認

### パイプライン実行テスト
- [ ] サンプル Excel で変換実行
- [ ] 生成されたスナップショット YAML を検査
- [ ] Context Manifest で AI に読み込ませるテスト

### CI/CD 設定確認
- [ ] `.github/workflows/excel-context-sync.yaml` を配置
- [ ] GitHub Actions トリガーテスト
- [ ] Git commit / push 動作確認

---

**作成日:** 2026-09-05
**バージョン:** 1.0
**対象:** Excel コンテキスト化パイプラインの実装者向け
