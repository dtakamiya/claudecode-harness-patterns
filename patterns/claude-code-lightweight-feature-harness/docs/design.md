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
| Branch | git状態を確認し、featureブランチを作成または選択 | main/master以外で、開始時SHAを記録済み |
| Explore / Baseline | `CLAUDE.md`等の規約、類似実装、テスト、コマンドを確認し、変更前検証を実行 | 変更候補とbaseline証跡が存在 |
| Micro Plan | 対象ファイル、RED、最小実装、検証を最大5項目にする | 各受入条件に検証方法がある |
| TDD | RED → GREEN_CONFIRMATION → REFACTOR → POST_REFACTOR_GREENを小さく反復 | POST_REFACTOR_GREENを確認済み |
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

main/master上ではファイルを書き換えない。既存作業を保護したうえで、事前許可された命名規則のfeatureブランチを作成する。既にfeatureブランチ上ならそのまま開始できる。個別承認が必要なリスク条件ではHuman Gateを先に通す。

### TDDと検証証跡

- REDでは、追加したテストが期待した理由で失敗することを確認する。
- production code変更前に、採用する既存のtest/typecheck/lint/buildを実行し、開始時Git SHA、コマンド、終了コード、結果要約をbaselineとして保存する。実行不能な項目は理由を記録し、完了時に未検証として扱う。
- GREEN_CONFIRMATIONでは、そのテストを通す最小差分だけを実装する。
- REFACTORは重複除去など現在の差分に必要な範囲に限る。
- REFACTOR後に新規・関連テストを再実行し、終了コード0の`POST_REFACTOR_GREEN`を確認してからVerifyとレビューへ進む。
- テストの削除・変更・skip、assertionの弱体化でGREENにしない。
- `PREPARATORY_REFACTOR`が必要なら実装せず、別Development taskへ昇格する。
- コードだけでは復元しにくい判断は[Change Intent Record](../../change-intent-record.md)に従い、Git/version control内の既存成果物へ目的、理由、制約、対象外、テスト参照を短く残す。独自成果物やゲートは増やさない。
非自明な設計意図の正本はGit/version control内の既存成果物へ置き、PR、issue、外部文書は固定revision、commit SHAまたはimmutable snapshot付きのsource/mirrorとしてのみ参照する。
- AIの内部思考や完全な会話transcriptは保存しない。
- 障害対応または本番操作が必要になった場合は、[Incident Response Harness](../../claude-code-incident-response-harness/README.md)へ昇格する。
- Verifyではプロジェクト既存のコマンドを使い、コマンド、終了コード、結果要約を残す。失敗を無視するフラグ、テスト削除、型エラー抑制でゲートを通さない。
- baseline由来の既知の失敗と新規失敗を区別する。新規失敗は完了をブロックする。

## 4. スコープ制御と失敗上限

次のいずれかが判明したら変更を拡大せず、現状、理由、選択肢をユーザーへ返してDevelopment Harnessへの昇格を提案する。

- 10ファイル超、複数コンポーネント、複数セッションが必要
- 要件またはアーキテクチャの選択が必要
- DB migration、公開APIの破壊的変更、本番操作、高リスク権限が必要
- 既存テスト基盤がなく、その新設自体が独立した設計課題になる
- 大規模リファクタリング、複数責務・コンポーネント境界の再設計、または機能差分と分離すべき構造変更が必要
- 同じ原因に対する修正が2回連続で失敗した
- レビュー修正後も同じblocking指摘が再発した

失敗時はエラーを抑制せず、根本原因、試行内容、残る不確実性を記録する。スコープ内の別原因ならMicro Planを一度だけ更新できる。

## 5. 権限とHooks

- permissionsはdeny優先とし、`.env*`、秘密鍵、credential、`.git`内部、本番操作を拒否する。
- `.env*`、OS Keychain、cloud/CI credentialを読み取らず、秘密値をログ、差分、handoffへ出力しない。証跡はsecretをredactする。
- 書込みは対象コンポーネント、テスト、必要な文書に限定する。Networkと外部サービス更新は既定で許可しない。
- `git push`、PR作成、依存追加、migration実行などはHuman Gate Policyで分類する。有効なpre-authorization grantに束縛されたprivate repositoryのfeature branchへのpushとdraft PRだけをTier 1として扱い、merge、public repository、外部公開、依存追加、migrationへ許可を継承しない。
- Hooksは必須ではない。既存Hookがある場合だけ、保護ファイルの書込み防止、編集後format、終了時verifyなど決定論的な規則に利用する。初回実行前にHook本体と呼出先をread-onlyで確認し、外部通信、secret参照、危険コマンド、対象外への書込みがないことを確かめる。
- Hookはユーザー権限で実行されるため、入力検証、変数のquote、絶対パス、secret除外を徹底する。Hook不在時は同じ検証コマンドを手動で実行する。
- 検証scriptと推移的な呼出先も初回実行前にread-onlyで確認する。`rm`、`git reset --hard`、強制checkoutなど変更を失う操作は既定でdenyする。
- shell scriptを追加・変更する場合はBash 3.2互換とし、`BASHPID`、連想配列、`declare -A`等を使わない。

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
| Human Reviewer | 固定差分、テスト、設計意図を理解して一致を判定 | 認証済みproviderまたはsigned attestationの参照 |

- AI/LLM ReviewerのPASSは補助証拠に限る。変更を理解した人間Reviewerがコード、テスト、設計意図の一致を確認するまで完了としない。
- Human Review EvidenceはGit内の自己申告を権威として扱わず、authenticated review provider、protected branch approvalまたはtrusted keyによるsigned attestationからread-onlyで取得する。
- AI/LLM、Implementer、レビュー対象を変更できるworkloadにはHuman Review Evidenceの発行・更新・失効権限またはprovider credentialを与えない。
- 必須fieldは`issuer`、PIIを複製しないopaqueな`stable_subject_id`、`verdict`、`issued_at`、排他的な`target`、およびimmutable evidence URLと`revision`の組または信頼済み`signature`とする。
- committed targetは完全な40桁または64桁hexの`commit_oid`だけを持つ。uncommitted targetは完全な40桁または64桁hexの`base_oid`と、canonical diff bytesの`sha256:<64hex>`である`diff_hash`を持ち、必要なら`manifest_hash`も束縛する。両形態のfieldが混在または欠落した証跡は拒否する。
- canonical diff bytesは信頼済みRunnerが固定`base_oid`と対象manifestから、external diffとtextconvを無効化し、full-index、binaryを含む決定論的なpath順で生成する。対象のtracked、staged、unstaged、意図したuntracked fileをmanifestへ列挙し、同じbytesをReviewerと検証側でhashする。
- Runnerはprovider APIの認証結果またはsignatureを検証し、issuer、subjectのrole binding、verdict、target、issued_at、evidence revisionを現在対象と照合する。取得不能、形式不正、不一致、未認証はfail-closedとする。
- blocking修正または対象変更時は旧attestation本体を変更せずappend-onlyの失効eventを記録し、新対象に束縛されたHuman Review Evidenceを権威ある発行元から再発行する。
- Human Review Evidenceは品質上の完了条件であり、操作を許可するHuman Gateや新しいgate/stateを追加するものではない。

### Committed target例

```yaml
human_review_evidence:
  issuer: github-protected-review
  stable_subject_id: account:opaque-7f3a
  verdict: approved
  target:
    kind: committed
    commit_oid: 0123456789abcdef0123456789abcdef01234567
  issued_at: "2026-07-15T10:00:00+09:00"
  evidence_url: https://review.example.invalid/attestations/review-123
  revision: review-123:v3
```

### Uncommitted target例

```yaml
human_review_evidence:
  issuer: organization-review-signing-key
  stable_subject_id: maintainer:opaque-a19c
  verdict: approved
  target:
    kind: uncommitted
    base_oid: 0123456789abcdef0123456789abcdef01234567
    diff_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    manifest_hash: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  issued_at: "2026-07-15T10:00:00+09:00"
  signature: sigstore:opaque-signature-bundle-ref
```

レビュー開始前に対象commit SHA（未コミット差分ならbase SHA、diff hash、変更ファイル一覧）を固定する。Reviewerは固定対象だけをread-onlyで評価し、レビュー中の変更を禁止する。修正はImplementerへ返し、blocking修正後は対象を再固定して関連検証を再実行する。non-blockingは小規模スコープを超えてまで対応せず、残課題へ記録する。

## 8. Handoff

作業中は一時checkpointにRED証跡、現在の仮説、レビュー結果、次actionだけを保存し、完了時に削除できる。compactionや再起動後に一意に復元できない場合はDevelopment Harnessへ昇格する。最終回答をhandoffとし、次を箇条書きで含める。

- 変更概要
- 変更ファイル一覧
- `command`、`exit code`、結果要約
- Code/Security Reviewの結果
- Handoffには権威ある発行元のimmutable evidence URLとrevisionまたはsignature、stable subject ID、target、verdict、issued_at、およびRunnerの検証結果を含める。Git内の自己申告で代用しない。
- UI確認結果（該当時）
- 残課題、未検証事項、昇格判断

PR作成を依頼された場合だけ、CodeRabbitの全レビューコメントを解消し、影響する検証を再実行してから完了とする。

## 9. 公式情報との対応

人間承認の共通基準は[Human Gate Policy](../../human-gate-policy.md)を正本とする。スコープ内の編集、feature branch、ローカルcommitを操作ごとに承認させず、protected branchへのmerge、外部公開、高リスク変更だけをリスク階層に従ってゲートする。本設計の昇格条件は追加条件として適用する。

- [Building Effective AI Agents](https://www.anthropic.com/engineering/building-effective-agents): 複雑性は必要時のみ増やすため、単一オーケストレーターと短い固定フローを採用する。
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices): 探索、計画、実装、検証を分離し、明確な検証手段を与える。
- [Configure permissions](https://code.claude.com/docs/en/permissions): allow/ask/denyを使い、deny優先の最小権限を適用する。
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide) / [Hooks reference](https://code.claude.com/docs/en/hooks): Hooksを決定論的制御に限定し、終了コードと安全上の注意に従う。
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html): 小さく自己完結した変更は、レビューを詳細にし、不具合を推論しやすくするため、規模上限とscope escalationを設ける。

これらは設計根拠であり、プロジェクト固有の`CLAUDE.md`、テスト規約、permissionsを優先して具体化する。
