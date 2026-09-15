# カンペき 音声

iPhoneで発表を録音し、Mac内で話し方を分析する独立モジュール。
カンペき本体との統合に向けた、SwiftUIアプリとPythonのローカル分析サーバーです。

本体の Issue #12 に紐づく音声検証モジュールです。本体 `KanpekiPhone` の未接続ホーム「音声を試す」からも同じ録音・分析画面を使えます。発表UUIDへの明示録音・終了停止は本体iPhoneへ部分統合済み（[範囲](../../docs/AUDIO_CAPTURE.md)）。Mac音声ホストは未マージPR #72、時計・スライド履歴は未接続。作業状態・引き継ぎは [Issue #12](https://github.com/MinobeRyo/kanpeki/issues/12) を参照してください。

## 初版の範囲

- iPhone：マイク許可、録音開始/終了、入力レベル、経過時間、最大15分、割り込み時の停止。
- 録音終了後にWAVをMacへ送信。失敗した録音は保持し、同じIDで再送可能。
- Mac：日本語文字起こし、認識文字数/分の推移、フィラー候補、低音量区間。
- iPhone：分析結果、話速グラフ、候補の文脈と時間範囲、文字起こしを表示。
- スライド切替履歴をAPIで受け取れば、各訪問の所要時間を集計。単体アプリでは履歴未取得。
- モデル未設定/失敗、発話未認識は未計測として表示。架空のスコアを生成しない。

**初版は録音終了後の一括送信です。** 連続ストリーミング、リアルタイム通知、Mac本体とのページ同期、原稿比較、カメラ分析は今後の統合対象です。

## 1. Macを起動する

Python 3.10以上。サーバー本体に追加のPythonパッケージは不要です。

```sh
git clone https://github.com/MinobeRyo/kanpeki.git
cd kanpeki/experiments/AudioCapture
sh scripts/start_mac.sh
```

この起動ではMac内からのみ接続できます。モデル未設定でも低音量区間の分析を確認できます。

### 文字起こしを有効にする

以下は明示的なセットアップです。アプリ起動や画面遷移ではダウンロードしません。

```sh
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install whisper-cpp
mkdir -p .tools/models
curl --fail --location https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin \
  --output .tools/models/ggml-base.bin
sh scripts/start_mac.sh --host 0.0.0.0 \
  --whisper-cli "$(command -v whisper-cli)" \
  --model .tools/models/ggml-base.bin
```

多言語baseモデルは約142 MiB。日本語で使うため `.en` モデルを選ばないでください。
モデルとバイナリはリポジトリに含みません。実装/ライセンスは [whisper.cpp](https://github.com/ggml-org/whisper.cpp) と [モデル配布元](https://huggingface.co/ggerganov/whisper.cpp) を参照。

起動したターミナルに接続コードが表示されます。コードはサーバーの再起動ごとに変わります。
Macのローカル名は `scutil --get LocalHostName` で確認できます。
iPhoneには `http://その名前.local:8765` と接続コードを入力します。`0.0.0.0` は入力しません。

## 2. iPhoneアプリを起動する

本体のTestFlightで試す場合は [本体での試験手順](../../docs/AUDIO_CAPTURE.md) を参照。以下は独立アプリをXcodeで起動する手順。

1. `ios/KanpekiAudio.xcodeproj` をXcodeで開く。
2. Signing & Capabilitiesで自分のTeamを選び、必要ならBundle IDを変更。
3. iOS 17以上のiPhoneを選んでRun。
4. Macと同じ信頼できるWi-Fiにつなぎ、URLと接続コードを入力して「接続を確認」。
5. 「録音をはじめる」→ マイク許可 → 話す →「録音を終了」→「Macで分析する・再取得」。

マイク/ローカルネットワーク権限を拒否した場合はiPhoneの設定から変更してください。
画面を背景へ移すと録音を終了します。着信等でも停止し、無断で録音を再開しません。
録音中はスリープを抑止します。分析中の待機は取り消せますが、受信済みのMacの処理は続きます。
接続コードはアプリで永続保存しません。入力するURLは自分のMacのものを使ってください。

### 開発用ネットワーク

初版は認証付きHTTPのLAN開発用です。通信は暗号化されていません。
信頼できるLANで利用し、インターネットへの公開・ポート転送はしないでください。
会場Wi-Fiの端末間通信制限では接続できないことがあります。Macのファイアウォールと同一ネットワークを確認してください。
共有ネットワークや製品配布にはTLSと本体のペアリング方式への統合が必要です。

## 3. iPhoneなしで分析処理を試す

16kHz・モノラル・16bit PCM WAVを指定します。

```sh
python3 scripts/analyze_wav.py /path/to/recording.wav \
  --whisper-cli "$(command -v whisper-cli)" \
  --model .tools/models/ggml-base.bin
```

変換が必要なら `ffmpeg -i input.m4a -ar 16000 -ac 1 -c:a pcm_s16le output.wav` を使用。
実際の録音や結果はGitに入れず、`.data/` 等に保存してください。

## 分析値の意味

| 項目 | 初版の定義・制約 |
|---|---|
| 話速 | 認識文字数/分。句読点等を除外。15秒ごとの値は認識文の時間範囲へ文字数を比例配分する推定値。厳密な発音速度ではない |
| フィラー候補 | 認識文中の「えー」「あの」「えっと」等。モデルの省略/誤認識、普通の指示語の誤検出がある。位置は単語時刻ではなく文の範囲 |
| 低音量区間 | -40 dBFS未満が1秒以上続く区間。発話区間検出モデルは未導入。雑音・距離に影響され、沈黙や意図的な間を判別しない |
| スライド時間 | 録音開始を0秒とした切替時刻の差。戻ったページは別の訪問として保持。履歴なしは未計測 |

マイク入力の欠落を話者の沈黙と扱わないため、iPhoneは中断箇所以降を録音に足しません。
全ゼロの音声には入力確認を促します。厳密なフィラー検出や雑音下の精度は実録音で別途検証が必要です。

## 保存と削除

- iPhone：送信失敗に備えて一時WAVを保持。ユーザーの「破棄」操作か次のアプリ起動時に削除。
- Mac：認識時だけ一時ファイルを作り、成功/失敗後に削除。異常終了時はOS一時領域に残る可能性あり。
- 結果：Macのメモリに最長約1時間（定期削除の間隔は0.5秒）、またはサーバー終了まで。削除APIあり。
- 外部音声APIやクラウドへの自動フォールバックなし。アクセスログに音声/原稿/認証情報を出さない。

## 開発・検証

```sh
PYTHONPATH=backend python3 -m unittest discover -s backend/tests -v
xcodebuild -project ios/KanpekiAudio.xcodeproj -scheme KanpekiAudio \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

プロジェクト設定を変更する場合は `ios/project.yml` を編集し、`cd ios && xcodegen generate` で再生成。
本体の `.github/workflows/audio.yml` が、このディレクトリのバックエンドテストを実行します。本体ターゲットの音声画面はNative checksと既存TestFlight CDの対象です。単体 `KanpekiAudio` の署名・配布は接続していません。

- [APIと統合ポイント](docs/INTEGRATION.md)
- [検証記録](docs/VALIDATION.md)
