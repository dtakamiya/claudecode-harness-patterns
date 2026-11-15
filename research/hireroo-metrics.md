# HireRoo 指標調査レポート

調査日: 2026-09-30 / 対象: 株式会社ハイヤールー（hireroo.io）

## 結論

- 成果（正解・速度・可読性）と行動（タブ離脱・ペースト等）の両方をブラウザ上で自動計測している。
- 得点は「正解率・パフォーマンス・可読性」に絞り、不正シグナルは得点に混ぜず別枠（不審度）で表示する設計。
- 新製品 Skill Interview では、全操作ログと AI との対話履歴を記録し「AI 協働力」を 5 領域で評価する。
- 画面・音声・映像の録画やカメラ監視は確認できなかった。
- 不審度と AI 協働力の算出ロジックは非公開。LLM 採点という見方は**推測**。

## 製品概要

- 「エンジニアのAI協働力」を可視化する組織開発プラットフォーム。採用（Skill Interview）、評価（Skill Assessment）、育成（Skill Development、Coming Soon）の 3 製品。 https://hireroo.io/
- Skill Interview は Claude Code / Codex / GitHub Copilot をブラウザ IDE で使うコーディング試験。TypeScript, Python, Go, Java 対応。「21職種」「400問近くの問題集」。 https://hireroo.io/interview/
- 従来機能の問題形式: コーディング（アルゴリズム/SQL）、クイズ、実践、システムデザイン、ライブコーディング。 https://support.hireroo.io/recruiters/question-format-types （検索スニペットのみ）

## 収集している指標

### 成果指標（コーディング形式）

出典: https://support.hireroo.io/recruiters/coding-report （本文で確認）

| 指標 | 収集・算出 |
|---|---|
| 総合得点 | 「正解率： 0.7、パフォーマンス： 0.2、可読性： 0.1」の加重平均 |
| 正解率 | 事前定義のテストケースで提出コードを自動実行 |
| パフォーマンス | 「実行速度が最適解の 3σ（標準偏差）以内に収まっているテストケースの割合を算出」 |
| 可読性 | 循環的複雑度。「複数ある模範解答の最小値と『最大値 × 1.5』した値を比較基準とします」 |
| 相対評価 | 同じ問題を解いた候補者との相対位置（順位・偏差） |
| 解答詳細 | 選択言語、経過時間、実行回数、使用ヒント数、予測計算量、パフォーマンス、メモリ使用量 |

- 循環的複雑度から可読性への具体的な換算式は記載なし。

### 行動指標（不正検知系）

- 同 coding-report: 「離脱回数、ペースト回数、ペースト検知、IPアドレス検知、類似コード」。タブ切替検知は「タブ切り替えや別アプリの操作により、回答画面から離れた回数」。
- ペースト追跡: Monaco Editor の `onDidPaste` で記録し、後続編集でもオフセットを追跡、再生タイムラインでハイライト。「patent-pending」と記載。 https://www.docswell.com/s/hireroo/Z1JX6G-techtalk2-3 （検索経由の要約。原文未確認）
- 不審度: AI が不正の可能性を判定し、候補者一覧とレポートに表示。約 4 万件の蓄積データをエンジニアが分類して学習データ化（検索スニペット由来）。
  - 「AIによる解析の詳細や個別のテストレポートの判定理由は開示できかねます」（公式）。
  - 適用範囲: Standard 以上、コーディング形式を含むテスト。Google 検索や ChatGPT のアシストを有効にしたテストは対象外。
  - 出典: https://support.hireroo.io/recruiters/suspiciousness-feedback 、 https://support.hireroo.io/tips_suspicious_degree

### 面接官評価（ライブコーディング）

- 評価項目を追加し、四段階評価と任意コメントを手動入力。プレイバックの「技術レビュー」から入力。 https://support.hireroo.io/recruiters/evaluate-livecoding （検索スニペットのみ。ラベル詳細は情報なし）

### AI 協働力（Skill Interview / SEI）

- 全操作ログと AI との対話履歴を記録して評価。 https://hireroo.io/interview/ 、 https://hireroo.io/sei/ai_collaboration/
- 5 領域と `/interview/` 記載の平均値（取得日 2026-09-30）:

| 領域 | 平均 |
|---|---|
| 意図の仕様化 | 69.8% |
| 環境構築 | 64.8% |
| 共同推論 | 51.8% |
| 実行の統制 | 70.7% |
| 出力の品質保証 | 63.9% |

- 平均値は取得元で揺れる（検索結果要約: 68.5% / 60.7% / 51.3% / 69.4% / 63.7%）。引用時は取得日と出典を明記すること。
- 発表資料は、プロンプト品質・コンテキスト提供・ターン数を測定可能な指標として挙げている。 https://www.docswell.com/s/hireroo/K27N1G-qiita_conference_2026
- Skill Assessment は AI ツール利用の「量」（トークン使用量/コスト）と「質」を独自スコアで可視化。 https://hireroo.io/
- 採点方式（LLM 使用の有無・重み・ランク境界）は**公式に明記なし。LLM がルーブリックで評価する方式とみられる（推測）**。

## レポート構成

- コーディング形式: 総合得点、正解率、パフォーマンス、可読性、相対順位、回答詳細、行動指標。
- Skill Interview（3 種）:
  - 定量: SEI スコア/ランク（0-100 点）、テストケース通過率、観測カバレッジ（例: 8/11）。「100万件超 の評価実績と比較して、候補者を位置づけ」。
  - プレイバック: 全ターンの対話とツール実行ログ、タイムスタンプ付き。
  - AI アシスタント: 根拠リンク付きの面接質問推薦。

## プライバシー/データ範囲

- 取得情報（要約）: 基本情報、Coding に関する試験の結果、連絡先。目的はサービス提供、求人企業への提供、サービス改善・新サービス開発。保管先は米国、EU、英国、インド、シンガポール、Google Data Centers。 https://hireroo.io/privacy
- ISMS 認証と P マーク取得（検索結果の要約）。 https://hireroo.io/security-policy/
- 保持期間: プライバシーポリシー全文は未精読のため断定しない。

## 使用しなかった数値（裏取り不能）

- 「導入 320 社・評価 1,170,387 件」「460 の評価観点」: `/interview/` 本文に記載なし（同ページは「300社超」）。検索要約由来のため採用せず。
- 「100M+」: 要約器の取り違え。原文は「100万件超」。
- 領域ごとの観点数（2/3/2/3/3）と 460 は不整合で未解決。

## 未確認・情報なし

- 不審度の入力特徴量・モデル・閾値・表示段階（公式が非開示と明言）。
- AI 協働力の採点ロジック詳細。
- クイズ・システムデザイン・実践形式の採点方法（support ページが 404）。
- ライブコーディング四段階評価の具体ラベル。
- データ保持期間、削除ポリシー、映像・音声収集の有無。
- 価格（「要問い合わせ」のみ）、不審度の精度、特許番号。

## 参照 URL

- https://hireroo.io/ 、 /interview/ 、 /sei/ai_collaboration/ 、 /privacy 、 /security-policy/ 、 /journal/blogs/fraud-prevention （スニペットのみ）
- https://support.hireroo.io/recruiters/coding-report （本文確認）
- https://support.hireroo.io/recruiters/suspiciousness-feedback 、 /tips_suspicious_degree 、 /recruiters/create-livecoding 、 /recruiters/evaluate-livecoding 、 /recruiters/question-format-types
- https://www.docswell.com/s/hireroo/Z1JX6G-techtalk2-3 、 https://www.docswell.com/s/hireroo/K27N1G-qiita_conference_2026
- 第三者: https://sheepdog.co.jp/aptitude_test/hireroo/ 、 https://thebridge.jp/en/2025/02/engineer-focused-platform-hireroo-raises-313-million-yen-in-series-a-funding
