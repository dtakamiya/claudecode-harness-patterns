# PHASE-9: コード・セキュリティ・人間レビュー

<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/workflows/`が配布元であり、
利用者の`.claude/workflows/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

PhaseDefinition (正本: 設計書 §3.4.1 PhaseDefinition実値表, §8.4):
  id: PHASE-9
  inputs: code-review-target, test-evidence, ui-evidence-or-na
  outputs: code-review, security-review, human-review-evidence-ref
  entry_gate: CODE_REVIEW_TARGET
  exit_gate: CODE_REVIEW
  allowed_agents: code-reviewer, security-reviewer, context-builder
-->

## 目的

固定されたレビュー対象を、Code Reviewer・Security Reviewer・責任ある人間Reviewerがそれぞれ独立に評価する（設計書 §8.4）。

## 開始条件

`CODE_REVIEW_TARGET`がPASSしていることをOrchestratorが検証する。**対応する不変なレビュー対象が存在しない場合、`CODE_REVIEW`ゲートを開始してはならない**（設計書 §3.8）。

## 入力

- `kind: code_review`のreview target（PHASE-8で固定）
- test evidence
- UI証跡またはnot applicable判定

## 担当Agent / Actor

| 役割 | Agent / Actor | profile |
|---|---|---|
| Evaluator | `code-reviewer` | evaluator |
| Evaluator | `security-reviewer` | evaluator |
| 人間Actor | Human Reviewer | AgentDefinitionではない。tool権限を持たない |
| コンテキスト編成 | `context-builder` | context_builder |

Evaluator専用工程とする（設計書 §3.4 工程別の適用レベル）。

## 手順

1. Code Reviewerが要件適合性、ロジック、保守性、回帰を検査する。**機械テスト成功だけで承認しない**（設計書 §8.4）。
2. Security Reviewerが認証・認可、入力検証、秘密情報、injection、依存・権限拡大を**独立**評価する。**Code Reviewerの承認を代用しない**（設計書 §8.4）。
3. Human Reviewerが固定されたコード、テスト、設計意図を理解し、責任ある人間として一致を判定する。
4. Runnerが Human Review Evidence を検証する。
5. blocking指摘がゼロで、検証済みHuman Review Evidenceのverdictが`approved`の場合だけ`CODE_REVIEW`をPASSとする。

**AI/LLM ReviewerのPASSは補助証拠に限る。変更を理解した人間Reviewerがコード、テスト、設計意図の一致を確認するまで完了としない**（設計書 §5 工程表）。

## Evaluatorの直列化（設計書 §10.1）

PhaseRunはEvaluatorごとに一つのstepを順序付きで持ち、**PHASE-9ではCode ReviewerとSecurity Reviewerを別stepとして直列化する。二つのreviewとagent-runを一つのstepへまとめない。**

- 各stepのinputは直前stepのoutput（先頭だけ`evaluated_commit`）とする。
- PhaseRunの`result_commit`は末尾stepのoutputと一致させる。
- `evaluation_output_commit`はEvaluator成果物へ自己記載せず、commit作成後に信頼済みRunnerがGateRunとPhaseRunへ記録する。

許可差分は、各`evaluation_step_input_commit`から対応する`evaluation_output_commit`まで、当該Evaluatorが新規作成するreview結果とagent-runの**正確な2パスだけ**とする。production codeまたはテストコード、他taskの成果物、既存証跡の変更が含まれる場合はfail-closedで拒否する。

## Human Review Evidence（設計書 §8.4）

Git内の自己申告を権威として扱わない。authenticated review provider、protected branch approvalまたはtrusted keyによるsigned attestationから**read-onlyで取得**する。

- **AI/LLM、Implementer、レビュー対象を変更できるworkloadには、Human Review Evidenceの発行・更新・失効権限またはprovider credentialを与えない。**
- 必須field: `issuer`、PIIを複製しないopaqueな`stable_subject_id`、`verdict`、`issued_at`、排他的な`target`、およびimmutable evidence URLと`revision`の組または信頼済み`signature`。
- committed targetは完全な40桁または64桁hexの`commit_oid`だけを持つ。uncommitted targetは完全な40桁または64桁hexの`base_oid`と、canonical diff bytesの`sha256:<64hex>`である`diff_hash`を持つ。**両形態のfieldが混在または欠落した証跡は拒否する。**
- Runnerはprovider APIの認証結果またはsignatureを検証し、issuer、subjectのrole binding、verdict、target、issued_at、evidence revisionを現在対象と照合する。**取得不能、形式不正、不一致、未認証はfail-closedとする。**
- blocking修正または対象変更時は、旧attestation本体を変更せずappend-onlyの失効eventを記録し、新対象に束縛された証跡を権威ある発行元から再発行する。
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
    diff_hash: sha256:<64hex>
    manifest_hash: sha256:<64hex>
  issued_at: "2026-07-15T10:00:00+09:00"
  signature: sigstore:opaque-signature-bundle-ref
```

canonical diff bytesは信頼済みRunnerが固定`base_oid`と対象manifestから、external diffとtextconvを無効化し、full-index、binaryを含む決定論的なpath順で生成する。対象のtracked、staged、unstaged、意図したuntracked fileをmanifestへ列挙し、同じbytesをReviewerと検証側でhashする（設計書 §8.4）。

## 成果物

- `docs/features/<feature-id>/reviews/<task>-code-review.md`
- `docs/features/<feature-id>/reviews/<task>-security-review.md`
- 検証済みHuman Review Evidenceへの参照
- `docs/status/agent-runs/<task>/<run-id>.yaml`（Evaluatorごとに別run）

## ゲート

| ゲート | 種別 | 条件 |
|---|---|---|
| `CODE_REVIEW` | exit gate | Code ReviewerとSecurity Reviewerのblocking指摘ゼロ、認証済みHuman Review Evidenceのtargetが現在対象と一致し、責任ある人間のverdictが`approved`（設計書 §11） |
| `ACCESS_POLICY` / `STATE_REVISION` | cross-cutting | 設計書 §11.0 |

## ブロック時の戻り先

実装（設計書 §11）。

## 注意事項

- Evaluatorはプロダクションコードを直接修正しない。書込みはレビュー成果物とagent-runだけとする（設計書 §3.6）。
- evaluator profileのagent-runは**ログファイルを作成しない**。コマンド出力を`summary`へ要約し、保存前にredactionする。secret検出時はrunを`failed`とする。全出力の保全が必要な場合は信頼済みRunnerが自らの権限で出力し、agent-runからは参照だけを行う（設計書 §10.1）。
- 変更範囲の逸脱のような「無いことの証明」は、Runnerまたは`PostToolUse`が生成した変更一覧の証跡を入力として与える。証跡が無い場合はPASSとせず、`residual_risks`へ記録してOrchestratorへ機械的検証を要求する（設計書 §11.1）。
- PHASE-8以後にファイルまたは証跡が変わった場合は`CODE_REVIEW_TARGET`とCode/Security Reviewをstale化し、再固定してから再評価する（設計書 §3.8）。

## 次工程

`CODE_REVIEW`がPASSした場合だけPHASE-10を`ready`へ遷移させる。
