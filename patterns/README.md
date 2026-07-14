# ハーネス適用ガイド

ファイル数は目安とし、リスク、波及範囲、再開性を優先する。

| 判断軸 | Micro Bugfix | Lightweight Feature | Development |
|---|---|---|---|
| 主用途 | 原因が特定できる局所バグ | 受入条件が確定した小機能 | 要件・設計を含む開発 |
| 規模目安 | 1〜3ファイル | 1〜10ファイル | 10ファイル超または複数コンポーネント |
| 期間 | 単一セッション | 単一セッション | 複数セッション |
| 状態管理 | 一時checkpoint | 一時checkpoint | 永続progress/handoff |
| 即時昇格条件 | 原因不明、認証・認可・秘密情報 | 設計判断、DB migration、破壊的API変更 | — |

1〜2ファイルの機能追加は、リスクが局所的で受入条件が確定していればLightweight Featureを使う。機能固有の文書は原則`docs/features/<feature-id>/`へまとめ、複数機能で共有する規約・ADRだけを共有ディレクトリへ置く。

## 参考資料

- [Claude CodeのモデルとEffortの選び方](assets/claude-code-model-effort-selection-guide.png)
