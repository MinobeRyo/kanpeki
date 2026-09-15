# 本体との統合

## 分担の接続点

このモジュールは音声取得・結果生成を担当する。スライド表示、ページ取得、原稿取得、接続の本体実装から以下を受け取る。

- 発表ごとのUUID
- 開始/終了イベント
- スライド番号と切替時刻（録音開始からの秒数）
- 本体が管理するMac接続先・認証情報

`RecorderModel.recordSlideChange(slide:at:)` がiPhone側の統合口。
単体画面ではスライドを操作しないため、履歴を空配列で送る。ページ送りUIを重複実装しない。
Mac側でスライドを取得する構成では、解析リクエストへ同じ形式の履歴を付ける。

**時刻の同期は本体と未接続。** `at` にネットワーク受信時刻を渡さない。
将来の接続層ではMacとiPhoneの単調時計の対応を求め、録音開始の基準に変換する。
原稿の予定時間が未提供のとき「想定の倍」などの比較結果を生成しない。

## HTTP API v1

全エンドポイントで `Authorization: Bearer <起動時の接続コード>` を要求。
結果の保存期間は約1時間。サーバー再起動時には消える。JSON、UTF-8。

### GET /health

```json
{"status":"ok","schema_version":1,"transcription_ready":true}
```

`transcription_ready` は設定があることを示す。認識の成功・精度を保証する値ではない。

### POST /v1/sessions

```json
{
  "id": "f28f605b-232a-4aba-9200-aae7cb80a201",
  "audio_base64": "<WAV全体のBase64>",
  "slide_events": [{"at":0,"slide":1},{"at":12.5,"slide":2}]
}
```

音声は16kHz mono PCM16、0.1秒以上・15分以下。本文は40MiB以下。
`at` は0以上、録音時間以内、厳密な昇順。先頭が0でなければ、それ以前のページは不明。
同じIDと同じ内容は重複処理しない。内容が異なる同じIDは400。同時待機上限に達したとき429。
202で `{"id":"...","status":"accepted"}` を返す。以後結果をポーリングする。

### GET /v1/sessions/{id}

`status`: `queued` / `processing` / `complete` / `failed`。
`complete` の `report` に結果。文字起こしが失敗しても、取得できた音量結果は返る。

- `duration`: 録音時間（秒）
- `transcription_status`: `not_configured` / `complete` / `failed` / `no_speech_recognized`
- `transcript`: `[{start,end,text}]` またはnull
- `pace`: `[{start,end,characters_per_minute}]` またはnull
- `average_characters_per_minute`: 推定平均値またはnull
- `filler_candidates`: `[{text,start,end,context,slide,timing:"segment"}]` またはnull
- `quiet_intervals`: `[{start,end,duration}]`、`quiet_seconds`: 合計
- `slides`: `[{slide,start,end,duration}]`（戻ったページは別行）
- `warnings`: 推定方法や未計測理由

nullは未計測。空配列は測定条件に当てはまる結果なし。音声の欠落を0秒の間や0回のフィラーに置き換えない。
結果の時刻はすべて録音開始基準の秒。フィラーの文がページ境界を跨ぐ場合、`slide` は文の開始時点のページを示す目安。

### DELETE /v1/sessions/{id}

完了/失敗した結果を削除。分析中は409。存在しなければ404。
iPhone側の「待機を終了」は通信の待機を取り消し、サーバー処理を取り消さない。

## 次の開発候補

1. 実機でPCM形式・マイク距離・録音割り込み・LAN接続を確認。
2. 本体の発表セッションとスライド履歴を接続。
3. 日本語フィラーの正解付き録音で検出漏れ/誤検出を評価。
4. 発話区間検出（VAD）を導入し、低音量と発話のない区間を区別。
5. 時刻と連番付きチャンク送信、欠落区間、バックプレッシャー、重複排除を実装。
6. 十分なデータ長と連続超過条件を定義して、リアルタイム通知を接続。

## Sources

- [Apple: AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder)
- [Apple: マイク許可](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
