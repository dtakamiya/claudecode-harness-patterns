# Jev（TypeSafe AI）調査レポート

調査日: 2026-09-29 / 対象バージョン: jev-1.13.0

## 結論

- Jev は **文章を生成する LLM ではない**。型付きの判定値（確率・信頼度つき）を返す「System One モデル」。
- 用途は分類・ルーティング・フィルタ・安全性判定・LLM-as-a-Judge など「出力形式が事前に決まっている小さな判断」。
- 自然言語生成・計算・日付比較・敵対的入力の扱いは苦手。**既存 LLM の置き換えではなく補完**として使う。
- 速度・コストの倍率は **ベンダー自社ベンチ**。導入前に自社データで検証すること。

## 概要

| 項目 | 内容 |
|---|---|
| 開発元 | TypeSafe AI（サンフランシスコ、2024 年創業。CEO: Diogo Almeida、元 OpenAI） |
| 公開 | 2026-09-15 限定アーリーアクセス。$40M シード（DCVC 主導） |
| 名称の由来 | 経済学者 William Stanley Jevons（TechCrunch） |
| アーキテクチャ | Transformer ベース、合成データのみで学習、RLCD（Reinforcement Learning for Calibrated Decisions）。重み・詳細は非公開 |
| モデル ID | `jev-latest` / `jev-preview`（いずれも `jev-1.13.0`） |
| エンドポイント | `POST https://api.typesafe.ai/v1/systemone` |

## 3 つの質問プリミティブ

- **Noul**: yes/no の確率
- **Choice**: 定義した選択肢から 1 つ選び、確率分布を返す
- **Score**: 順序付きの記述レベルに対して評価

- 複数の質問は並列処理され、質問を増やしても遅延はほぼ変わらない（追加分はトークン課金のみ）。
- 出力は事前定義された型に限られるため、ハルシネーションの余地が小さい。

## 性能・価格（公式ドキュメント／ベンダー主張）

- 応答時間: 70〜500ms
- 価格: 入力 **$42 / 10 億トークン**（= $0.042 / 100 万）、出力は無料
- レート制限: 250,000 tokens/秒、1,200 req/分（高需要のため動的に調整中）
- コンテキスト: 1 リクエスト 64k トークン、テキストのみ（英語が最高精度）
- データ: 顧客リクエストは学習に不使用、ゼロデータ保持オプションあり
- 速度・コスト倍率の主張: 「40〜200 倍高速・40〜400 倍安価」（最大 193.6 倍 / 444.6 倍）
- 事例（TechCrunch）: Vercel の安全性分類で ChatGPT 比 5〜18 倍高速かつ高精度。Bryo AI のメール分類は Gemini より 10〜20 倍安価だが、Gemini のほうが僅かに高精度

## 既知の制約（公式 Known Issues, jev-1.13）

- 指示を字義通りに解釈し、暗黙の意図を汲まない
- 文字数・出現回数などのカウント、算術、16 進数・RGB 等の数値表現が弱い
- 日付・時刻を順序量ではなくテキストとして扱う
- 二重否定・多段推論で精度低下
- 無関係な文脈が多いと精度低下（ディストラクタ化）
- **入力を敵対的とみなさない（プロンプトインジェクション耐性なし）**
- 指示と criteria が矛盾すると混乱
- Noul と Choice の確率間に算術的整合性の保証なし
- テキスト生成は非対応

## 注意点・未検証事項

- 公開情報は限定アーリーアクセス段階。Wikipedia 上は公開 API 価格・待機リスト詳細の記載なし（ドキュメント側には価格記載あり）。
- ベンチマークはすべて TypeSafe 自社ワークフロー由来で、第三者検証なし（TypeSafe 自身も「実環境の上限側の値」と認めている）。
- 情報源間で SDK 名が異なる: 公式は `typesafe-sdk`、LangChain 連携は `langchain-typesafe`（後者は LangChain 記事のみで確認、未検証）。
- The Register・arXiv 論文（ペンテスト用途）は本文未確認。

## 活用パターン（公式ドキュメント）

- Speculative Fan-out: 複数の質問を並列に投げ、関連性はコード側で判定
- Confidence-gated Routing: 回答＋信頼度でルーティング（低信頼は LLM / 人間へ）
- Composite Scoring: 原子的なスコアをコード側の重みで合成
- Intent Routing: 意図分類 → 最適ハンドラへ
- 連携: LangChain（モデルルーティング、`AutoModeMiddleware` によるツール呼び出しの安全性分類）、DeepEval（`hybrid` / `system_one` 評価モード）
- ハーネス用途の想定: ツール呼び出しの事前リスク判定、LLM 出力のガードレール、モデル振り分け

---

# 導入手順（macOS / zsh 環境向け）

## 現環境の確認結果

- システム Python は 3.9.6（`pip` コマンドなし）→ SDK は **Python 3.10 以上が必須**のため NG
- `uv` 0.11.19、Node v22 は導入済み
- `TYPESAFE_API_KEY` は未設定
- → **`uv` で Python 3.10+ の仮想環境を作る**のが最短

## 1. API キーの取得

1. https://console.typesafe.ai/keys でキーを発行（アーリーアクセスのため承認が必要な可能性あり）
2. https://console.typesafe.ai/playground で動作確認
3. キーを環境変数に設定（リポジトリにコミットしない）

```bash
# ~/.zshrc に追記（または direnv / 1Password CLI 等で管理）
export TYPESAFE_API_KEY="<your-typesafe-api-key>"
```

## 2. Python SDK の導入

```bash
uv init jev-sandbox && cd jev-sandbox
uv python pin 3.12
uv add typesafe-sdk
# HTTP/2 が必要な場合: uv add "typesafe-sdk[http2]"
```

## 3. 動作確認

`smoke.py`:

```python
from typesafe_sdk import Choice, Noul, Score, TypeSafeClient

with TypeSafeClient() as client:
    response = client.system_one(
        state={"document": "I was charged twice. Please fix this ASAP."},
        questions={
            "billing": Noul(instructions="Is this ticket about billing?"),
            "tone": Choice(
                instructions="What is the customer's tone?",
                criteria={"calm": None, "frustrated": None, "angry": None},
            ),
            "urgency": Score(
                instructions="How urgent is this ticket?",
                criteria=["can wait", "this week", "today"],
            ),
        },
    )

print(response.nouls["billing"].noul)
print(response.choices["tone"].choice)
print(response.scores["urgency"].score)
```

```bash
uv run python smoke.py
```

- 期待結果: 各値が出力される（正常終了）。認証エラーなら `TYPESAFE_API_KEY` を再確認。
- 非同期版は `AsyncTypeSafeClient` + `await client.system_one(...)`。
- JavaScript/TypeScript SDK もあり（`docs.typesafe.ai/sdk/javascript`。パッケージ名は本調査で未確認）。

## 4. Claude Code への導入（任意）

TypeSafe 公式の Agent Skill で、Claude Code が API 仕様・パターン・ベストプラクティスを参照できるようになる。

```bash
claude plugin marketplace add typesafe-ai/skills
claude plugin install typesafe@typesafe-ai
```

- 導入後、Claude Code を再起動するか `/reload-plugins` を実行
- 呼び出し: `/typesafe:typesafe-ai` または「TypeSafe skill を使って」と指示
- 更新: `claude plugin marketplace update typesafe-ai` → `claude plugin update typesafe@typesafe-ai`
- 他のエージェント: `npx skills add typesafe-ai/skills --skill typesafe-ai`
- サードパーティ製プラグインなので、導入前に https://github.com/typesafe-ai/skills の内容を確認すること

## 5. ハーネスへの組み込み方針（本リポジトリ向け）

- まず **ツール呼び出しの危険度判定（Noul）** や **入力の意図分類（Choice）** など、低リスクな 1 箇所で試す
- 信頼度が低い場合は LLM / 人間へフォールバックする（Confidence-gated Routing）
- 入力は敵対的と扱われない（既知の制約）ため、**セキュリティ判定を Jev 単独に任せない**。決定的ルールやフックと併用する
- 導入判断の前に、自社データで精度・遅延・コストを Haiku 等の既存構成と比較する

## 6. 運用上の注意

- 送信データは `state` に含まれる全内容。機密情報の送信可否は、ゼロデータ保持オプションを含め契約条件を確認
- レート制限は動的に変更中。リトライ設定（SDK の Retries）を有効にする
- `jev-latest` は版が上がると挙動が変わる。再現性が必要なら `jev-1.13.0` に固定する

---

## 参考資料

- [Jev (AI model) - Wikipedia](https://en.wikipedia.org/wiki/Jev_(AI_model))
- [TypeSafe Docs（Quick Start / Models / Known Issues / Agent Skill / Python SDK）](https://docs.typesafe.ai)
- [TechCrunch: A new kind of AI model from a ChatGPT inventor is thrilling developers](https://techcrunch.com/2026/09/18/a-new-kind-of-ai-model-from-a-chatgpt-inventor-is-thrilling-developers/)
- [LangChain: What Is Jev? Building a harness with Jev](https://www.langchain.com/blog/building-a-harness-with-jev)
- [DeepEval: Introducing Jev for Evals](https://deepeval.com/blog/introducing-jev-in-deepeval)
- 未確認: [The Register](https://www.theregister.com/devops/2026/09/23/shut-up-and-calculate-jevs-new-ai-primitives-for-coders/5298431) / [arXiv 2609.28940](https://arxiv.org/pdf/2609.28940)
