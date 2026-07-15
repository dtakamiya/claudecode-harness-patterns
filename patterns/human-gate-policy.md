# Human Gate Policy

## 1. 目的と原則

本ポリシーは、各ハーネスに共通する人間承認の正本である。ヒューマンゲートは工程ごとの儀式ではなく、機械判定できない価値判断、高影響な操作、残存リスクの受容に限定する。テスト結果、終了コード、schema、revision、lease、digest、禁止操作はRunner、CI、permissionsまたは実行基盤で判定し、人間へ再計算させない。

- 人間は`Intent`、`Scope`、`Evidence`、`Risk`、`Recovery`を確認する。
- 機械ゲートが未完了、証跡が古い、承認対象が曖昧な場合は`fail-closed`とする。
- ハーネス固有規則が本ポリシーより厳しい場合は、厳しい規則を優先する。
- AI/LLM ReviewerのPASSは人間Approverを代替しない。
- 承認は権限付与ではなく、denyまたは禁止操作を解除しない。
- Manual modeはPoC限定のままとし、人間承認で機械的guardrailの不足を補わない。

## 2. リスク階層

| Tier | 扱い | 代表例 |
|---|---|---|
| Tier 0 | 自動実行 | read-only調査、ローカルtest・lint・typecheck・build |
| Tier 1 | 自動実行し、監査記録とサンプリングレビューを行う | スコープ内のコード・テスト変更、feature branch、ローカルcommit、有効なpre-authorization grantに束縛されたprivate repositoryのfeature branchへのpush・draft PR |
| Tier 2 | 一名の適格な承認者が事前承認する | protected branchへのmerge、通常の依存追加、Jira遷移・外部writeback、public repositoryまたは外部公開を伴うPR |
| Tier 3 | 独立した二名承認と操作単位の実行制御を行う | 本番・共有データへ適用するmigration、認証・認可・秘密情報境界、破壊的API、広範囲またはrollback困難な変更 |
| Tier 4 | 通常ハーネスでは禁止し、専用手順へ移す | セキュリティインシデント、無制限credential、承認対象を固定できない不可逆操作 |

ファイル数ではなく、利用者影響、データ影響、可逆性、権限、波及範囲、不確実性でTierを決める。Tierは単一操作だけでなく、同一task、同一目的の変更系列、累積差分と副作用で評価し、同じ外部変更を構成するmutationや副作用を操作分割で降格させない。read-only観測と決定論的検証はTier 0のままとするが、高Tierのmutationや外部反映は該当ゲート通過まで実行しない。Tierを確定できない場合は一段上として扱い、人間へ選択肢を提示する。

## 3. 必須ヒューマンゲート

| Gate | タイミング | 人間が決めること | 通過条件 |
|---|---|---|---|
| 要件ゲート | 実装前 | 目的、受入条件、対象外、業務上のトレードオフ | 結果を変える曖昧性がなく、責任者が受入条件を承認 |
| リスク受容ゲート | Tier 2以上の設計・操作前 | リスク階層、影響、代替案、残存リスク | 適格な承認者がDecision Packetの固定revisionを承認 |
| 外部反映ゲート | merge、release、本番、確定writeback前 | 外部状態を変更してよいか | 最新証跡、対象、停止条件、Recoveryが承認と一致 |
| 制御面ゲート | rules、Skills、Hooks、Runner、permissions、品質ゲート変更前 | ハーネス自身の信頼境界を変更してよいか | 所有者承認と独立Harness Reviewが完了 |

feature branch作成、ローカルcommit、スコープ内の編集ごとには人間承認を要求しない。Tier 1のpushやdraft PRはprivate repositoryに限り、機械検証可能なpre-authorization grantにgrant ID、発行者identity、grantee/workload identity、task/run ID、目的、明示的なPR作成Intent、発行時刻、期限、最大使用回数、取消状態、repository ID、source branch・commitまたはscope、branch名前空間、許可する操作種別、PRの可視性、許容するCI・通知・preview等の連携副作用を固定した場合だけ自動化できる。grantは信頼済み鍵による署名またはMAC、もしくはACL保護されたauthority store内のgrant IDと固定digestで認証し、裸のdigestだけを認証根拠にしない。実行直前に認証結果、利用主体、現在task、期限、使用回数、取消状態、実対象を照合し、各使用を監査記録する。不一致は`fail-closed`とする。現在taskのPR作成Intentを証明できない場合、または条件を一つでも満たさないPR作成はTier 2とし、protected branchへのmerge、release、本番変更へ許可を継承してはならない。

## 4. Decision Packet

承認要求は、一画面または一つの構造化成果物にまとめる。まだ生成できない証跡を要求しないよう、段階別に必須項目を分ける。該当しない項目は理由付き`N/A`とする。

設計・実装前のDecision Packet:

- 目的、変更理由、対象外
- リスクTierと判定理由
- 受入条件、代替案、想定する権限・依存・データ・外部影響
- 成功条件、停止条件、rollback計画、Recovery owner
- 推奨判断、承認期限、承認者に必要なrole

外部反映前のDecision Packet:

- 設計前Packetの固定revisionと、承認後に生じた差分
- 承認対象のrepository、branch、source commit SHA、merge先base SHA、artifact revisionまたはdigest
- 対象resourceの期待revision、ETag、Jira expected statusなど実行前状態のprecondition
- 受入条件と変更・test・reviewの対応
- test、typecheck、lint、build、UI確認、Code/Security Reviewの結果と終了コード
- 権限、依存、データ、外部状態への差分
- 未検証事項、既知の失敗、残存リスク
- 期待結果、成功条件、停止条件、timeout
- rollback手順とRecovery owner。rollback不能なら理由と代替策
- 承認期限、実行予定者、必要なApprover role

承認者は生ログ全体を読むのではなく、Decision Packetから`Intent`、`Scope`、`Evidence`、`Risk`、`Recovery`を確認し、必要な証拠だけを参照する。証跡の生成者、対象SHA、時刻、終了コードを機械検証できない場合は承認へ進めない。

## 5. 承認の有効性と失効

承認記録には、承認ID、承認者identityとrole、時刻、承認期限、対象、操作、revision、source commit SHAまたはdigest、対象のbase SHA・revision・ETag・expected status等のprecondition、承認範囲、理由を含める。Tier 2以上は、実行直前に承認記録と実対象を再照合し、compare-and-swap、If-Match等の条件付き更新として原子的に適用する。条件付き更新が使えない場合はlock、lease、対象凍結等の同等な排他を必須とし、それも不可能なら上位Tierで明示的にリスク受容するか`fail-closed`とする。

次のいずれかが変更または期限切れになった場合、旧承認を`stale`として自動失効させ、revisionを更新して再承認を得る。

- source commit SHA、対象のbase SHA・revision・ETag・expected status、artifact revision、canonical payloadまたはdigest
- 対象resource、operation、parameters、影響範囲
- 受入条件、権限、依存、migration内容
- 成功条件、停止条件、timeout、rollback条件
- 承認期限、承認者資格、前提となる機械ゲート結果

期限切れ、部分一致、競合する承認、承認者不在は`fail-closed`とする。承認済みimmutable intentの同一payloadを、同じidempotency keyとpreconditionで再送する場合だけ再承認を不要とする。payload、target、expected statusまたはpreconditionが変われば再承認する。Incidentは既存の`incident-action/v1`によるcanonical payloadとdigest束縛を使用し、別schemaを追加しない。

## 6. 役割分離と監査

- Tier 2は、変更作成者、提案者、Executorのいずれとも異なる適格な人間が承認する。依頼者との分離は、利益相反がある場合または組織policyが要求する場合に必須とする。
- Tier 3は、業務・運用上の責任者と技術・セキュリティ上の責任者という異なる二人の人間による二名承認を必須とし、両ApproverをExecutorから分離する。例外は定義済みの`break-glass`だけとする。
- 本番操作はsingle-writerとし、一つの承認で複数の未固定操作を許可しない。
- 承認、却下、取消、実行、停止、rollbackを追記専用の監査証跡へ記録し、秘密情報をredactする。監査storeは最小権限のACL、保持期間、WORMまたはhash chain等の改ざん検知を備える。
- 代理承認は事前登録したroleだけに許可し、本人と同じ責任・証跡要件を適用する。
- 適格な承認者は、ACL保護されたauthority mappingでrepository owner、service owner、security owner等のidentityとroleを解決する。未登録、期限切れ、自己申告だけのroleは無効とする。
- authority mappingとの照合は実行基盤のproduction conditionであり、文書schema上のrole文字列だけで適格性を証明したことにしない。
- `break-glass`は、専用schema、権限、Runner分岐、監査、組織runbookのSLAが実装・検証済みのハーネスだけで使用できる。生命・重大障害など事前定義した条件に限り、二名の事前承認を一名の適格な人間による操作単位の事前承認へ短縮できるが、人間承認自体は省略できない。発動者identity、incident ID、理由、対象、操作、digest、時刻、期限を記録し、関係者へ即時通知する。最小権限の短命credentialを自動失効させ、未承認の二人目を含む二名の事後確認と組織runbook所定期限内のレビューを必須とする。target・digest束縛、single-writer、監査記録は迂回できず、通常の納期都合には使用しない。未実装のハーネスでは`break-glass`を禁止する。

## 7. 運用評価

Human Gate自体もHarness Evalsの対象とし、少なくとも次を定期的に測定する。

- Tier別の承認件数、判断時間、期限切れ率、却下率、取消率
- 承認後の差分変更による失効件数、override率、rollback率
- 誤承認、過剰承認、承認漏れ、同一原因の再発
- Tier 1サンプリングで見つかった重大指摘率
- Decision Packetの不足項目と、承認者が追加確認した証拠

Tier 1のサンプリング率は変更リスクと過去の指摘率から定める。重大な見逃し、制御面の変更、初めて扱う操作はサンプリングではなくTier 2以上へ昇格する。
