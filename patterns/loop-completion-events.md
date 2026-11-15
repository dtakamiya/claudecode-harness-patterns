# Loop Completion Events

## 1. 目的と適用範囲

本規約は、無人ループの親が子へ作業を委譲したとき、その結果を受け取る方法を定める。親は子の様子を定期的に見に行かない。子が終わったときに必ず完了イベントが出るようにし、親はそのイベントで次の処理を始める。

成功の判定と予算は[Loop Guard Policy](loop-guard-policy.md)、項目の状態とleaseは[Loop State Handoff](loop-state-handoff.md)を正本とする。本規約は、その2つをつなぐ「子の結果が親へ届く経路」を扱う。

適用対象は、ループの1回の中で子セッションや`claude -p`の子プロセスへ作業を渡す構成である。親と子が同じ1つのプロセスで完結するループには適用しない。

## 2. 観測した問題

[Loop Guard Policy](loop-guard-policy.md)と同じ個人環境の定期実行基盤について、委譲の放置を見回るジョブの指示文と実行記録を2026-11-15に確認した。

| 観測 | 内容 |
|---|---|
| 見回りジョブ | 2時間ごと・1日6回、約1か月で128回実行された。全セッションの一覧を取得し、子セッションのうち「90分以上活動がなく、親へ報告していないもの」を探す |
| 判定の材料 | 放置かどうかを、セッションのタイトルや直近のメッセージからAIが読み取って判断していた |
| 催促 | 放置と判定した子へ「進捗を1メッセージで報告してください」と送る。この催促文は36回送られた |
| 見回り自体の停滞 | 128回のうち12回は1時間を超えて実行され、前回の見回りが終わる前に次が始まった回が10回あった |

ここから次の3つが分かる。

- **結果が届く経路が保証されていない。** 子が報告するかどうかは子への指示文頼みで、報告しないまま止まる子が出るたびに見回りと催促で補っている。
- **見回りの判定が決定論的でない。** 「報告済みかどうか」をAIが会話から推測しており、同じ状態でも判定が揺れる。
- **見回りのコストが仕事の量に比例しない。** 委譲が無い時間帯も2時間ごとにモデルを起動し、全セッションを調べている。

## 3. 原則

1. **完了イベントは子の指示文ではなく、子を起動する仕組みが出す。** 子が正常に終わっても、失敗しても、強制終了されても、起動したラッパーが必ず1つのイベントを残す。
2. **親は待たない。** 親は委譲を記録したら、その回を終える。結果はイベントとして次の回、またはイベントを契機にした起動で受け取る。
3. **期限切れはスクリプトが判定する。** 委譲には期限を付ける。期限までにイベントが無ければ、スクリプトが`TIMED_OUT`として扱う。AIに会話を読ませて推測させない。
4. **催促しない。** イベントを出さずに止まった子へ「報告してください」と送らない。イベントが無いのはラッパーの不具合か強制終了であり、その委譲は失敗として扱い、項目を[Loop State Handoff](loop-state-handoff.md)の規則で戻す。
5. **イベントは何度届いても1回分として処理する。** イベントには一意のIDを付け、処理済みのIDは無視する。

## 4. 委譲の記録

親は子を起動する前に、[Loop State Handoff](loop-state-handoff.md)の項目のleaseへ委譲の情報を加える。

```json
"lease": {
  "run_id": "2026-11-15T09:17:01Z-dev-cycle",
  "expires_at": "2026-11-15T11:17:01Z",
  "delegation": {
    "delegation_id": "dlg-7f3a",
    "child": "claude-p:pid-48213",
    "deadline": "2026-11-15T10:47:01Z"
  }
}
```

- `deadline`は子の実行時間の上限（[Loop Guard Policy](loop-guard-policy.md)4.2）に余裕を足した時刻とし、`expires_at`より前に置く。期限切れの処理がleaseの回収より先に走るようにするためである。
- 1つの項目に同時に2つ以上の委譲を持たせない。

## 5. 完了イベント

### 5.1 形式

```json
{
  "event_id": "evt-dlg-7f3a",
  "delegation_id": "dlg-7f3a",
  "item_id": "item-042",
  "kind": "completed",
  "exit_code": 0,
  "result_file": "runs/dlg-7f3a.result.json",
  "finished_at": "2026-11-15T09:58:44Z"
}
```

| `kind` | 出す条件 |
|---|---|
| `completed` | 子のプロセスが終了コード0で終わり、構造化した結果のファイルがある |
| `failed` | 終了コードが0以外、または結果のファイルが無い・schemaに合わない |
| `killed` | timeoutやシグナルで止められた |

`kind`は子の終わり方だけを表す。項目が`done`になるかどうかは、親が`verify`を実行して[Loop Guard Policy](loop-guard-policy.md)3章の規則で決める。`completed`であっても検証に落ちれば`FAILED`である。

### 5.2 出し方

子を起動するラッパースクリプトが、終了時に必ずイベントを書く。シェルスクリプトはBash 3.2で動く書き方にする。

```bash
#!/bin/bash
# run-child.sh <delegation_id> <item_id> <events_dir>
DELEGATION_ID=$1
ITEM_ID=$2
EVENTS_DIR=$3
RESULT_FILE="runs/$DELEGATION_ID.result.json"
KIND=failed

write_event() {
  exit_code=$1
  tmp="$EVENTS_DIR/.evt-$DELEGATION_ID.tmp"
  printf '{"event_id":"evt-%s","delegation_id":"%s","item_id":"%s","kind":"%s","exit_code":%s,"result_file":"%s","finished_at":"%s"}\n' \
    "$DELEGATION_ID" "$DELEGATION_ID" "$ITEM_ID" "$KIND" "$exit_code" "$RESULT_FILE" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp"
  mv "$tmp" "$EVENTS_DIR/evt-$DELEGATION_ID.json"
}

trap 'write_event $?' EXIT
trap 'KIND=killed; exit 143' TERM INT

claude -p ... --output-format json > "$RESULT_FILE"
status=$?
if [ "$status" -eq 0 ] && [ -s "$RESULT_FILE" ]; then
  KIND=completed
fi
exit "$status"
```

- イベントは一時ファイルに書いてから`mv`で置き換え、書きかけのファイルを読ませない。
- 子を`claude -p --bare`で起動する場合、hooksは動かない。イベントの発行をhooks（`Stop`など）に頼らず、ラッパーで行う。
- `kill -9`や電源断ではtrapも動かない。その場合は6.2の期限切れで扱う。

## 6. 親の処理

### 6.1 イベントを受け取る

親のループは、[Loop Guard Policy](loop-guard-policy.md)4.1の事前ゲートの前に、届いているイベントを処理する。

1. `events/`のイベントを`finished_at`の古い順に読む。
2. 処理済みの`event_id`なら捨てる。
3. 対応する委譲がleaseに無ければ（期限切れで回収済みなど）、記録だけ残して捨てる。
4. `verify`を実行し、結果に応じて項目の状態を進め、leaseを外す。
5. 処理済みの`event_id`を記録し、イベントを`events/processed/`へ移す。

イベントが届いたらすぐ処理したい場合は、イベントのディレクトリへの書き込みを契機に親を起動する（例: launchdの`WatchPaths`）。この場合も処理の中身は上と同じであり、定時の起動とイベント契機の起動が重なっても、lockと`event_id`で二重処理を防ぐ。

### 6.2 期限切れを扱う

同じく事前ゲートの前に、`deadline`を過ぎた委譲を探す。

- `deadline`を過ぎ、対応するイベントが無い委譲は`TIMED_OUT`とする。子のプロセスが残っていれば止める。
- 項目は[Loop State Handoff](loop-state-handoff.md)5.2の規則で`todo`か`blocked`に戻す。
- 期限切れは異常として数え、[Loop Guard Policy](loop-guard-policy.md)4.5の連続失敗の判定に含める。

この判定はスクリプトが時刻とファイルの有無だけで行い、モデルを起動しない。そのため、2時間ごとに見回るジョブは不要になる。念のための確認を残す場合も、1日1回、期限切れが0件であることを記録するだけにする。

## 7. 指標

[Loop Guard Policy](loop-guard-policy.md)6章の指標に、次を加えて週次で見る。

| 指標 | 見る理由 |
|---|---|
| 期限切れ（イベント無し）の件数 | ラッパーか子の起動方法に問題が無いか。0件が正常 |
| `killed`の件数 | 実行時間の上限が仕事の大きさに合っているか |
| 委譲からイベントまでの時間（p50・p95） | `deadline`の設定が妥当か |
| 催促メッセージの送信数 | 0件であること。0でなければ本規約を外れた運用が残っている |

## 8. 段階導入

1. **ラッパーの導入**: 子の起動をラッパー経由に切り替え、イベントを書かせる。既存の見回りジョブはそのまま動かし、見回りで見つかった放置とイベントの有無を突き合わせる。
2. **期限切れの判定**: 委譲に`deadline`を付け、6.2の判定をスクリプトで始める。見回りと結果が一致することを確認する。
3. **見回りの停止**: 1〜2週間、見回りでしか見つからない放置が0件であることを確かめてから、見回りジョブと催促を止める。
4. **イベント契機の起動**: 必要なら6.1の即時起動を有効にする。
