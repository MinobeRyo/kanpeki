# Macアプリの音声分析

Issue #63。Macアプリ上部の「音声分析」から専用ウィンドウを開きます。

## 使い方

1. 初回は「モデルを取得」。Whisperの多言語baseモデル（約142MB）をHTTPSで取得し、SHA256を検証してアプリのApplication Supportへ保存します。取得済みの `ggml-base.bin` を選ぶ方法もあります。Python、Homebrew、ターミナル操作は不要です。
2. 「受信を開始」。MacのURLと接続コードが表示されます。
3. 同じ信頼できるWi-FiのiPhoneで「音声を試す」を開き、Mac画面に表示されたURL・コードを入力して「接続を確認」。スライドの接続コードとは別です。
4. iPhoneで録音を終了して「Macで分析する・再取得」。Mac内で文字起こしと集計を行い、両端末に結果を表示します。
5. 「受信を停止して結果を削除」で停止。再開するとコードとポートが変わるため、iPhoneにも新しい値を入力します。Macアプリを終了するとサーバーも終了します。音声ウィンドウを閉じるだけでは受信は継続します。

Wi-Fiを変えたら受信を停止・再開し、新しいURLを使ってください。現在はIPv4のLANアドレスを表示します。端末間通信を禁止する会場Wi-Fiでは接続できません。

## 構成

- `Sources/KanpekiAudioHost/`：SwiftのHTTP受信、PCM WAV検証、指標集計、Whisperの直接呼び出し、モデル準備とSwiftUI画面。
- 公式whisper.cpp **v1.9.2 XCFramework**をSwift Packageのbinary targetで固定。配布ZIPのSHA256 `af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b` を照合します。Mac向けarm64/x86_64を含みます。
- baseモデルのSHA256は `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`。モデルはアプリやGitに同梱せず、初回の明示操作で取得します。以後の分析にクラウド推論APIは使いません。
- TestFlightパッケージ作成では、同じ配布証明書で同梱framework→アプリの順に署名します。Bundle ID・配布先・テスター設定は維持します。
- 旧 `experiments/AudioCapture/backend` は比較・開発用として残ります。本体MacはPythonプロセスを起動しません。

公式配布元：[whisper.cpp v1.9.2](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.2)、[baseモデル](https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-base.bin)。MITライセンス表示をアプリの「使用ライブラリ」に同梱しています。

## 受信とデータ

既存iPhoneの `/health`、`POST /v1/sessions`、`GET/DELETE /v1/sessions/{UUID}` に対応します。Bearerコードは起動ごとに生成し、ログやGitへ保存しません。現在のLAN転送はHTTPです。インターネットへの公開やポート転送を前提としません。

録音は16kHz mono PCM16 WAV、0.1秒〜15分。JSON本文40MiB、ヘッダー16KiB、同時接続4件、リクエスト待機60秒、分析1件、保持結果64件・最大約1時間（30秒ごとに削除）です。処理中は追加録音に429を返し、同じUUID/同じ音声・履歴の再送は重複分析しません。異なる内容で同じUUIDは409です。停止すると進行中の分析をキャンセルし、古い結果を再開後に反映しません。

音声は受信と推論のためメモリ内だけで扱い、MacでWAVをディスクに保存しません。モデルのみ永続保存します。HTTP取得用の結果は最長約1時間、画面に表示した最後の結果は停止/アプリ終了まで保持します。

話速は認識文字数/分、フィラーは認識文内の候補、低音量区間は−40dBFS未満が1秒以上続いた区間です。VAD、厳密な語単位時刻、原稿比較、連続送信、スライド時刻の自動同期は本変更に含みません。文字起こしを取得できなかった場合は話速・フィラーを未計測として返します。

## 検証

`swift test` でWAV境界、指標、HTTP分割、早期認証、再送、競合、結果削除、同時分析と停止後の結果抑止を検証します。
実モデルのテストではMacの音声コントローラを起動し、モデル検証、接続情報の発行、LAN HTTP送信、Whisper分析、結果取得、停止後の消去まで確認します。合成音声とモデルのパスを `KANPEKI_TEST_WAV` / `KANPEKI_TEST_MODEL` に明示した時だけ実行します。指定なしでは明示的にskipし、実モデル検証済みとは扱いません。

`KANPEKI_TEST_SNAPSHOTS` に出力先を指定すると、テスト内のNSHostingViewから準備・接続・結果画面のPNGも出力します。実アプリのクリックや端末間通信の実機検証とは区別します。接続画像にはテスト中のみ有効なコードが含まれるため、画像はGitへ入れません。

実機iPhone録音・会場音声精度・TestFlightでの受け入れは #39 / #28 の状況と区別します。署名なしビルドとローカル検証用署名はAppleへのアップロード成功を意味しません。
