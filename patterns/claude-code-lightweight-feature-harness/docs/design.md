# Claude Code 軽量機能追加ハーネス設計書

## 1. 目的と原則

小規模機能追加に必要な品質だけを、単一セッションで低い運用コストにより保証する。Anthropicの「最も単純な解から始め、必要な場合だけ複雑性を足す」という原則に従い、会話を永続ワークフローエンジンへ変換しない。

- featureブランチ上で、一度に一機能だけを扱う。
- 受入条件をテストへ変換し、REDを確認してからproduction codeを変更する。
- LLMの判断と、終了コードで判定できる検証を分離する。
- 既存構造を踏襲し、抽象化、基盤追加、将来要件への先回りをしない。
- スコープが外れた時点で止まり、Development Harnessへ昇格する。

## 2. 構成

```text
User
  └─ Lightweight Orchestrator（メインセッション）
       ├─ Explore（read-only調査）
       ├─ TDD Implementer（テストと最小実装）
       ├─ Deterministic Verification（既存コマンド）
       ├─ Code Reviewer（正確性）
       └─ Security Reviewer（脆弱性）
```

メインセッションはスコープ判定、順序制御、ゲート判定、最終報告だけを担当する。Explore、TDD実装、レビューは、対象と期待出力を絞ってサブエージェントへ委譲する。常設エージェント定義や独自状態機械は必須にしない。

## 3. ワークフローとゲート

| Phase | 実施内容 | 終了ゲート |
|---|---|---|
| Intake | 目的、受入条件、対象外、規模を確定 | 未確定事項がなく、軽量範囲内 |
| Explore | `CLAUDE.md`等の規約、類似実装、テスト、コマンド、git状態を確認 | 変更候補とbaselineが説明可能 |
| Micro Plan | 対象ファイル、RED、最小実装、検証を最大5項目にする | 各受入条件に検証方法がある |
| TDD | RED → GREEN → REFACTORを小さく反復 | 新規・関連テストが成功 |
| Verify | test、typecheck/lint/build、UIを検証 | 必須コマンドが終了コード0 |
| 2軸Review | 正確性とセキュリティを別観点で評価 | blocking指摘が0件 |
| Handoff | 差分と証跡を最終回答へ記録 | 必須項目がすべて存在 |

### Intakeの最小形式

```text
目的: <1文>
受入条件:
- <観測可能な条件>
対象外: <1文>
想定範囲: <コンポーネント、3〜10ファイル程度>
```

不明点は推測せず、結果を変える選択肢を提示してユーザーへ確認する。

### TDDと検証証跡

- REDでは、追加したテストが期待した理由で失敗することを確認する。
- GREENでは、そのテストを通す最小差分だけを実装する。
- REFACTORは重複除去など現在の差分に必要な範囲に限る。
- Verifyではプロジェクト既存のコマンドを使い、コマンド、終了コード、結果要約を残す。失敗を無視するフラグ、テスト削除、型エラー抑制でゲートを通さない。
- baseline由来の既知の失敗と新規失敗を区別する。新規失敗は完了をブロックする。

## 4. スコープ制御と失敗上限

次のいずれかが判明したら変更を拡大せず、現状、理由、選択肢をユーザーへ返してDevelopment Harnessへの昇格を提案する。

- 10ファイル超、複数コンポーネント、複数セッションが必要
- 要件またはアーキテクチャの選択が必要
- DB migration、公開APIの破壊的変更、本番操作、高リスク権限が必要
- 既存テスト基盤がなく、その新設自体が独立した設計課題になる
- 同じ原因に対する修正が2回連続で失敗した
- レビュー修正後も同じblocking指摘が再発した

失敗時はエラーを抑制せず、根本原因、試行内容、残る不確実性を記録する。スコープ内の別原因ならMicro Planを一度だけ更新できる。

## 5. 権限とHooks

- permissionsはdeny優先とし、`.env*`、秘密鍵、credential、`.git`内部、本番操作を拒否する。
- 書込みは対象コンポーネント、テスト、必要な文書に限定する。Networkと外部サービス更新は既定で許可しない。
- `git push`、PR作成、依存追加、migration実行など外部状態や影響範囲を変える操作は明示承認を要する。
- Hooksは必須ではない。既存Hookがある場合だけ、保護ファイルの書込み防止、編集後format、終了時verifyなど決定論的な規則に利用する。初回実行前にHook本体と呼出先をread-onlyで確認し、外部通信、secret参照、危険コマンド、対象外への書込みがないことを確かめる。
- Hookはユーザー権限で実行されるため、入力検証、変数のquote、絶対パス、secret除外を徹底する。Hook不在時は同じ検証コマンドを手動で実行する。

## 6. UI変更

UI変更では、通常のtest/typecheckに加えて利用可能なpreview/browser機能で次を確認する。

- 対象画面を実際に表示し、主要状態をスクリーンショットで確認
- 受入条件に関わる操作を実行
- browser consoleに新規errorがない
- narrow/wide viewportなど、変更に直接関係する表示幅を確認

ブラウザ確認が利用できない場合は完了扱いにせず、未検証項目として明記する。

## 7. 2軸レビュー

| Reviewer | 確認事項 | 出力 |
|---|---|---|
| Code Reviewer | 受入条件、正確性、回帰、境界値、テスト品質、不要な複雑性 | blocking / non-blocking、根拠のファイル位置 |
| Security Reviewer | 入力検証、認可、情報漏えい、command/path injection、依存・権限の拡大 | blocking / non-blocking、攻撃条件と対策 |

Reviewerは原則read-onlyとし、修正はImplementerへ返す。blocking修正後は関連検証を再実行する。non-blockingは小規模スコープを超えてまで対応せず、残課題へ記録する。

## 8. Handoff

最終回答だけを軽量なhandoffとし、次を箇条書きで含める。

- 変更概要
- 変更ファイル一覧
- `command`、`exit code`、結果要約
- Code/Security Reviewの結果
- UI確認結果（該当時）
- 残課題、未検証事項、昇格判断

## 9. 公式情報との対応

- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents): 複雑性は必要時のみ増やすため、単一オーケストレーターと短い固定フローを採用する。
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices): 探索、計画、実装、検証を分離し、明確な検証手段を与える。
- [Configure permissions](https://code.claude.com/docs/en/permissions): allow/ask/denyを使い、deny優先の最小権限を適用する。
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide) / [Hooks reference](https://code.claude.com/docs/en/hooks): Hooksを決定論的制御に限定し、終了コードと安全上の注意に従う。
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html): 小さく自己完結した変更は、レビューを詳細にし、不具合を推論しやすくするため、規模上限とscope escalationを設ける。

これらは設計根拠であり、プロジェクト固有の`CLAUDE.md`、テスト規約、permissionsを優先して具体化する。
