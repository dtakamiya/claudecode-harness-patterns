<!--
出典: Claude Code Development Harness 設計書 Version 1.10
https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md

この雛形は上記パターンリポジトリの`templates/rules/`が配布元であり、
利用者の`.claude/rules/`へコピーして使う。本文中の「設計書 §N」は
すべて上記URLの設計書の該当節を指す。コピー先のリポジトリに設計書は
存在しないため、相対パスでは参照しない。

正本: 設計書 §3.8（Worktree Isolationとレビュー対象固定）,
      §10.2（競合・破損時の扱い）, §11（IMPLEMENTATION_REVIEW_TARGET /
      CODE_REVIEW_TARGET / STATE_REVISION）, §6.5〜§6.6, §7.2

--- 段階導入 ---

設計書 §17は、Worktreeを段階導入できる要素と位置づける
（「並列化が必要になった時点でworktree隔離を導入する」設計書 §16-13）。
一方、**レビュー対象の固定は段階導入できない。** 設計書 §3.8は
「対応する不変なレビュー対象が存在しない場合、
`IMPLEMENTATION_EVALUATION`と`CODE_REVIEW`ゲートを開始してはならない」と
定めており、worktreeを使わない構成でも本規則§3以降は必須である。

本規則は両者を分けて記す。
  §1〜§2: worktree隔離（段階導入可）
  §3〜§7: レビュー対象の固定（必須）
-->

# Worktree Isolation / レビュー対象固定 規則

本規則は、並列実行時のworktree隔離と、**Evaluatorが受け取る不変なレビュー対象**の固定方法を定める。設計書 §3.8の正本である。

> **worktreeは段階導入できるが、レビュー対象の固定はできない。** 設計書 §3.8は「対応する不変なレビュー対象が存在しない場合、`IMPLEMENTATION_EVALUATION`と`CODE_REVIEW`ゲートを開始してはならない」と定める。単一checkoutで運用する場合も§3以降を適用する。

---

# Part 1: Worktree隔離（段階導入可）

## 1. 構成

並列実行は**依存関係の薄い作業だけ**に限定し、各GeneratorへGit worktreeを割り当てる。

```text
repository/            # 追跡対象。ここにworktreeを作らない
└─ main

<repo外の隔離領域>/    # 例: sandbox内のscratch、コンテナ、tmpfs
├─ TASK-101/
├─ TASK-102/
└─ REVIEW-201/
```

生成は`WorktreeCreate` Hook、または`scripts/create-task-worktree.sh`による明示生成とする（設計書 §3.5.1 Hooks対応表）。

> 設計書 §3.8の構成図は`repository/.worktrees/`を示すが、これはworktreeとタスクの**対応関係**を表す概念図である。ビルド・テストを実行するworktreeの**配置**は§2.2に従い、リポジトリルート外へ解決されなければならない（設計書 §3.6.3）。

> **worktreeを作成しただけでは、親セッションの未コミット変更や意図したタスク状態が自動的にレビュー側へ引き継がれるとは限らない**（設計書 §3.8）。分岐元SHAを明示すること。§3を参照。

## 2. 並列化の可否

| 並列化できる作業 | 並列化しない作業 |
|---|---|
| 異なるモジュールの独立タスク | 同一クラス、同一設定、同一DBスキーマの変更 |
| **対象commitが固定された**読み取り専用レビュー | 前後依存のあるタスク |
| 異なる文書の作成 | 一つのRED-GREEN-REFACTORサイクル内部 |
| 競合しないテスト追加 | 同一成果物に対する複数Generatorの直接編集 |
| | **未コミット変更を暗黙に引き継ぐ前提のReviewer worktree起動** |

### 2.1 worktree内のAgentは中央状態を触らない（設計書 §10.2）

- **worktree内のAgentは中央の`progress.yaml`を直接編集しない。**
- `progress.yaml`の更新者はDevelopment Orchestratorだけである（設計書 §3.4.1 実行規則6）。Agentは更新を**要求**できるが、直接更新しない。
- 状態ファイルとGitの`current_commit`が一致しない場合は、**次工程をブロックする**（`STATE_REVISION`ゲート）。

### 2.2 実行時作業領域との関係

設計書 §3.6.3は使い捨てworktreeを実行時作業領域の一例として挙げるが、同節は**「リポジトリ外の使い捨て領域」であり「canonical pathがリポジトリルート外へ解決されること」を条件**とする。

> **未信頼コードを実行するworktreeを、リポジトリ配下（`<repo>/.worktrees/`）へ置いてはならない。** テストコードやビルドスクリプトの子プロセスは、相対パスで親checkoutと`.git`へ到達できる。§1の構成図はworktreeの**論理的な対応関係**を示すものであり、未信頼コードを実行する領域の配置ではない。

- ビルド・テストを実行するworktreeは、**リポジトリルート外**のパスへ作成する（`scripts/create-task-worktree.sh`が配置先を決める）。`.claude/rules/permissions.md` §5と同一の条件である。
- 出力先をリポジトリ外へ向ける設定は**強制側が与える。** 与えられない場合、当該Agentはそのコマンドを実行せず、Runnerが自らの権限で実行して結果を証跡として渡す（設計書 §3.6.3）。
- `.git`、親checkout、`docs/**`、`.claude/**`への到達を遮断する。**追跡対象ファイルとレビュー対象コードへの書込みは、実行時作業領域を理由に許可しない。**
- **run終了時に破棄し、次のrunへ状態を持ち越さない。** 持ち越すとテスト結果が前のrunに依存し、証跡がcommitへ束縛されなくなる。

読み取り専用レビュー用のworktree（コードを実行しないもの）にはこの制約は及ばないが、実行を伴うなら上記を適用する。

---

# Part 2: レビュー対象の固定（必須）

## 3. Evaluatorは作業ディレクトリ名を受け取らない

> **Evaluatorは、作成者の作業ディレクトリ名ではなく、不変なレビュー対象を受け取る**（設計書 §3.8）。

```yaml
# docs/features/<feature-id>/reviews/targets/TASK-004-implementation.yaml
review_target:
  kind: implementation_review
  task: TASK-004
  commit_sha: abc123def456
  diff_base_sha: 789xyz000111
  changed_files_manifest: docs/status/changes/TASK-004.yaml
  preparatory_refactor_used: true
  preparatory_checkpoint_ref: docs/status/checkpoints/TASK-004-preparatory-refactor.yaml
  artifact_hashes:
    docs/features/order/design/order-component.md: sha256:...
    docs/status/checkpoints/TASK-004-preparatory-refactor.yaml: sha256:...
  worktree_source_verified: true
```

### 3.1 `commit_sha`はtargetファイル自身を含まない

`commit_sha`は**レビュー対象のコード（production codeとテスト）を固定したcommit**を指し、review target成果物そのものを含まない。

> targetファイルは`commit_sha`が指すcommitより**後に**作成されるため、自身を含むcommitのSHAを自身へ記載することはできない（記載した時点でSHAが変わる）。

- Generatorのagent-runでは、**レビュー対象を固定したcheckpoint commit**と、**run全体の最終`result_commit`**を区別して記録する。
- Evaluatorは`commit_sha`からコードを読む。targetファイル自身は`commit_sha`に含まれないため、別途§3.4の方法で解決する。

### 3.2 固定方式（設計書 §3.8）

次のいずれかを採用する。

1. Generatorがチェックポイントコミットを作成し、そのcommit SHAからReviewer用worktreeを作成する。
2. Reviewerを現在のcheckout上で**read-only実行**し、未コミット差分を直接レビューさせる。
3. `WorktreeCreate` Hookまたは専用スクリプトで**分岐元SHAを明示する。**
4. パッチと成果物ハッシュを生成し、Reviewer環境へ適用・検証する。

採用案2を採る場合、**base commitと変更ファイル一覧をレビュー成果物へ明記し、working treeがdirtyであることを記録する。何を読んだかを特定できない状態で評価を開始してはならない**（設計書 §3.8）。

### 3.3 PREPARATORY_REFACTOR使用時の追加要件（設計書 §3.8, §6.5）

`preparatory_refactor_used: true`の場合、

- `IMPLEMENTATION_REVIEW_TARGET`のschemaに`preparatory_checkpoint_ref`を**必須**とする。
- `artifact_hashes`のcheckpoint hashを、GateRunの`checkpoint_artifact_hash`と**一致させる。**
- **欠落・不一致・形式不正はfail-closedとする。**
- `preparatory_refactor_used`、`preparatory_checkpoint_ref`、checkpoint artifact mappingを**singleton key**とし、各出現回数が1でなければfail-closedとする。

Implementation Evaluatorは**production diffとこの宣言の一致を検査し、不一致ならfail-closedで差し戻す**（設計書 §6.6）。

### 3.4 targetファイル自身の固定（TOCTOU対策）

設計書 §3.8はtargetファイルを「現在のcheckoutから読む」と記すが、**この読み方をそのまま実装すると検証と読取りの間に差し替えられる**（TOCTOU）。§7の機械検証がPASSしたtargetと、Evaluatorが実際に読むtargetが同一である保証がない。target自身が改変可能なら、`commit_sha`や`artifact_hashes`を書き換えてレビュー対象全体をすり替えられる。

強制側は次のいずれかでtargetファイル自身を固定する。

| 方式 | 内容 |
|---|---|
| **envelope commit（推奨）** | targetファイルを含むcommitを作成し、その**envelope SHA**をEvaluatorへ渡す。Evaluatorはenvelope SHAからtargetを読む。`commit_sha`（コード）とenvelope SHA（target）の2つを受け取る形になり、循環参照は生じない |
| **immutable store** | 検証時点のtarget内容をcontent-addressableに保存し、そのhashをEvaluatorへ渡す。Evaluatorはhashで取得した内容だけを読む |

- **§7の機械検証は、Evaluatorが読むのと同一のcontent（同じenvelope SHAまたは同じhash）に対して行う。** working treeを検証してenvelope SHAを渡す、あるいはその逆は、検証の対象と使用の対象がずれるため無効である。
- 検証したenvelope SHA / hashを**GateRunへ記録する。** 記録がなければ、どのtargetが検証されたか事後に特定できない。
- 採用案2（現在のcheckout上でread-only実行）を採る構成でも、**targetファイル自身はこの固定を要する。** 未コミット差分をレビューすることと、レビュー対象の定義そのものが可変であることは別問題である。

## 4. 2種類のtarget

| kind | 固定時点 | 検証者 | ゲート |
|---|---|---|---|
| `implementation_review` | PHASE-7の`POST_REFACTOR_GREEN`後 | Implementation Evaluator | `IMPLEMENTATION_REVIEW_TARGET` → `IMPLEMENTATION_EVALUATION` |
| `code_review` | **PHASE-8完了後** | Code Reviewer / Security Reviewer | `CODE_REVIEW_TARGET` → `CODE_REVIEW` |

`code_review` targetは、PHASE-8までのコード、テスト、**UI証跡**を含むcommit SHA、diff base、変更一覧、成果物ハッシュを固定する（設計書 §11）。

## 5. PHASE-8途中のレビュー対象（設計書 §3.8）

`INTEGRATION_TEST`は上記2種類の対象に**含まれない。** PHASE-8の完了順序は`INTEGRATION_TEST` → `UI_VERIFICATION` → `CODE_REVIEW_TARGET`であり、`kind: code_review`のtargetは**PHASE-8完了後**に固定されるため、Integration Test ReviewerとUI Verifierの実行時点では存在しない。

> これは構造上不可避であり、両者へ不変なtargetの受領を要求できない。

代わりに次の手順で対象を解決し、結果をレビュー成果物とagent-runへ記録する。**解決できない場合はゲートを開始せずfail-closedとする。**

- PHASE-7の`kind: implementation_review` targetを読み、`commit_sha`を**評価済みproduction codeの基準点**として得る。Integration Test Engineerが`integration_test_engineer_write_allowlist`外を変更していないことの検証は、**この基準点との差分**で行う。
- 評価するITコードは、Integration Test Engineerのagent-runの`result_commit`から読む。**`result_commit`がPHASE-7の`commit_sha`の子孫であることを検証する。** 子孫でなければ、評価済みproduction codeとは別の系統であり**拒否する。**
- 採用案2（現在のcheckout上でread-only実行）を採る構成では、base commitと変更ファイル一覧をレビュー成果物へ明記し、working treeがdirtyであることを記録する。
- UI Verifierのpreviewは、**固定されたcommitからビルドしたもの**とする（設計書 §3.6.5）。証跡は当該commit SHAへ束縛する。

## 6. Stale化（設計書 §3.8）

PHASE-8以後にファイルまたは証跡が変わった場合の扱い。

| 変更の性質 | 扱い |
|---|---|
| PHASE-8以後にファイル・証跡が変わった | `CODE_REVIEW_TARGET`とCode/Security Reviewを**stale化**し、新しいcommit SHA、diff base、変更一覧、成果物ハッシュで**再固定**する |
| 変更がPHASE-7の実装前提、受入条件、production code、Unit Testを変える | `IMPLEMENTATION_REVIEW_TARGET`とImplementation Evaluationも**stale化**し、**PHASE-7から再評価**する |

Integration TestまたはUI検証後にコード・テスト・証跡が変わった場合は、**それ以前の結果を必要な範囲で再実行してから**最終対象を固定する（設計書 §7.2）。

## 7. ゲート開始の必須条件

> **対応する不変なレビュー対象が存在しない場合、`IMPLEMENTATION_EVALUATION`と`CODE_REVIEW`ゲートを開始してはならない**（設計書 §3.8）。

強制側（Runner / Hook）は、ゲート開始前に次を機械検証する（設計書 §14 「レビュー開始前」、§14.2 `verify-review-target.sh`）。

- commit SHAが実在し、`diff_base_sha`から到達可能である
- `changed_files_manifest`が存在し、実際のdiffと一致する
- `artifact_hashes`の各ハッシュが実ファイルと一致する
- `preparatory_refactor_used`宣言がproduction diffと一致する（§3.3）
- singleton keyの出現回数が各1である（§3.3）
- PHASE-8では`result_commit`がPHASE-7 `commit_sha`の子孫である（§5）

**いずれかが不一致・欠落・形式不正ならfail-closedとし、ゲートを開始しない。**

検証は§3.4で固定したtarget content（envelope SHAまたはhash）に対して行い、**Evaluatorへ渡すのと同一のcontent**を対象とする。検証したenvelope SHA / hashをGateRunへ記録する。

## 8. review targetは不変（設計書 §3.8, §3.6.1）

- review targetは「**不変なレビュー対象**」であり、**固定後の更新を拒否する。**
- 再固定が必要な場合は、**新しいcommit SHAで新規targetを作成する。**
- 書込みは現在taskのtargetファイル**一点**へ限定し、**既存ファイルへのWrite/Editを拒否する（create-only）**（`.claude/rules/permissions.md` §2）。

> **証跡を改変できるAgentは、その証跡を根拠とするゲートを無効化する。**
