# 音声取得・解析モジュール

## 移植元と構成

ユーザーの指示により、別リポジトリに作成した音声初版を `experiments/AudioCapture/` に移した。
移植元: `mao-sonobe/kanpeki-audio`、コミット `12f4a30d02d951e491232fbde53d2b5487f99000`。
ソース・実テスト・Xcodeプロジェクト・手順を取り込み、Git履歴・モデル・録音・秘密情報は含めていない。
アイコン/ロゴは本体の `assets/brand/app-icon.png` に合わせた。

## 本体iPhoneで音声を試す

`KanpekiPhone` の未接続ホームに「音声を試す」を追加した。同じ録音・通信・結果画面を単体アプリと本体で共有する。`KanpekiAudioApp.swift` と単体アプリの署名設定は本体ターゲットへ含めない。本体のBundle ID・署名・配布先は既存設定を維持する。

これは音声の試験入口。発表タイマーやスライドのセッションとはまだ連動しない。共有接続を切ったホームから開き、カメラを停止して試す。録音画面を戻る/バックグラウンドへ移すと録音は停止し、次に音声画面を開いて取得済み音声を分析できる。分析中に戻ると待機をキャンセルする。画面を開くだけではマイクを要求しない。

1. この変更を含む本体iPhoneビルドをインストールして、ホームの「音声を試す」を開く。TestFlight配布状態は [Issue #28](https://github.com/MinobeRyo/kanpeki/issues/28) で確認する。PR作成・マージ・ローカルビルド成功だけではTestFlight更新済みとはしない。
2. Macでは本体リポジトリの `experiments/AudioCapture/` から [README](../experiments/AudioCapture/README.md) の手順で音声分析サーバーを起動する。iPhone接続には `--host 0.0.0.0` を明示する。Macネイティブアプリにはサーバー・Whisperモデルの自動起動をまだ組み込んでいない。
3. iPhoneとMacを同じ信頼できるWi-Fiへ接続し、`http://Macのローカル名.local:8765` とMacに表示された接続コードを入力する。これは音声サーバー用のコードで、本体スライド接続とは別。初版はLAN内のHTTP通信。
4. 「接続を確認」→「録音をはじめる」→マイク許可→30〜60秒話す→「録音を終了」→「Macで分析する・再取得」。モデル未設定なら文字起こし・話速・フィラーは未計測になる。
5. 話速、フィラー候補、低音量区間、文字起こしを確認する。録音を破棄する前に、必要なら元の声と候補を照合する。

未検証：実iPhoneの権限・録音品質・LAN通信、会場音声精度、長時間録音。実機での確認は #39 に記録する。

## 発表に関連付けて録音する（部分統合）

本体iPhoneの「…」→「発表の音声 · このiPhone」から、発表タイマーが進行中または一時停止中のときだけ明示操作で録音を開始できる。カメラ分析は開始時に停止し、録音中のカメラ入口は無効化する。録音を使わなくても発表できる。

発表UUIDと録音UUIDは別々に保持する。既存の単体試験録音や前回発表の録音は、新発表へ付け直さない。詳細シートを閉じても発表録音は継続し、明示停止、発表終了、切断、状態更新が3秒以上途切れたとき、背景移行で停止する。権限要求中に同じ条件が起きたら開始を取り消し、遅れて許可されても録音しない。

録音終了後は同発表の欄から「音声を分析・結果を見る」で既存の音声画面を開く。MacサーバーURL・コードを利用者が入力し、分析ボタンで明示送信する。送信も自動化しない。API受付・結果のIDは要求した録音UUIDと照合し、不一致なら表示しない。旧録音の終了・エラーコールバック、取消後の古い通信は現録音へ反映しない。

結果の録音時間はbackendの0.1〜900秒、全区間は録音時間内・昇順、数値は有限かつ非負で検証する。backendのミリ秒丸めは許容し、未計測nullはそのまま保持する。不正応答は表示しない。時刻表示も別途範囲を確認し、巨大値・NaN・無限大を整数へ変換しない。話速の精度や良し悪しを判定する閾値ではない。

録音時間は録音の時計であり、発表タイマーの時間ではない。発表中の途中開始や一時停止区間を含むことがある。Mac/iPhoneの時計対応は未接続なので、スライド履歴は空のまま送る。受信時刻を録音時刻に見せない。カメラとの同時計測、Mac本体へのサービス起動・音声結果同期、共通結果サマリーの音声詳細は残件。今回のMacビルド成功はMac音声解析の製品統合完成を意味しない。

検証は`bash scripts/check.sh core`内の音声IDチェック（録音や外部通信なし）、既存音声バックエンドテスト、本体Mac/iPhoneビルドで行う。実機の録音品質・割り込み・切断停止・録音画面往復・実API精度は未検証、#38/#39に残す。

## 単体音声アプリ

Xcodeで `experiments/AudioCapture/ios/KanpekiAudio.xcodeproj` を開く。Bundle IDは `dev.kanpeki.audio`。この単体アプリ自体のTestFlight配布設定は未接続。本体TestFlightでは上記のホーム入口を使う。

音声は16kHz mono PCM16 WAVを録音終了後に一括送信する。Mac内のwhisper.cppで文字起こしし、話速・フィラー候補・低音量区間を返す。モデル未設定/失敗は未計測として扱う。詳細は [API契約](../experiments/AudioCapture/docs/INTEGRATION.md)。

## 残作業の受け取り方

[Issue #12](https://github.com/MinobeRyo/kanpeki/issues/12) が音声全体の入口。本文の完了条件と直近コメント、関連する未担当Issueを確認する。
手が空いた人は、未担当・未着手の項目を選び、着手コメントと自分への担当設定を行ってから専用branch/worktreeで始める。担当済みの作業は既存担当と調整する。

引き取り可能な残件の入口（担当の最新状態は各Issueで確認）：

- [#38 本体の発表セッションへの組み込み](https://github.com/MinobeRyo/kanpeki/issues/38)
- [#39 実iPhone・実会場での検証](https://github.com/MinobeRyo/kanpeki/issues/39)
- [#40 VADと日本語フィラー候補の改善](https://github.com/MinobeRyo/kanpeki/issues/40)
- [#41 連続送信と発表中通知](https://github.com/MinobeRyo/kanpeki/issues/41)

関連する本体作業：

- #10：iPhone画面。音声のON/OFF・権限・録音状態を既存画面へ組み込む。
- #13：結果画面。`AudioReport` を渡し、未計測と0件を区別する。
- #17 #20：タイムラインとスライド切替。録音の時刻基準へ変換する。
- #19 #22：接続とMac Bridge。接続先/認証・受信経路を本体へ統合する。
- #18：通知。連続分析と通知条件を検証してからつなぐ。

これらの担当や完了状態は固定表に複製せず、最新Issueを正本にする。

## 初回移植時の検証（試験入口の追加前）

2026-09-15、移植先の専用worktreeで以下を確認した。

- バックエンド18件成功（音量・時刻・未計測・実HTTP・認証・再送・削除）。
- 本体 `bash scripts/check.sh core` 成功（チーム管理4テスト、Swiftコア17チェック）。
- 単体音声アプリのiPhone Simulator向け署名なしビルド成功。
- 同じ `AudioAPI.swift` の実通信クライアントから、日本語合成音声17.712秒を送信→Macでwhisper.cpp実分析→Swiftで結果取得まで成功。

実行コマンド：

```sh
cd experiments/AudioCapture
PYTHONPATH=backend python3 -m unittest discover -s backend/tests -v
xcodebuild -project ios/KanpekiAudio.xcodeproj -scheme KanpekiAudio \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

本体の音声CIは `.github/workflows/audio.yml`。移植前の結果は [初版の検証記録](../experiments/AudioCapture/docs/VALIDATION.md) で区別する。
実iPhoneの録音・LAN接続・会場音声の精度は未検証。VAD、リアルタイム分析/通知、Mac/iPhoneの時計対応とスライド履歴同期は未実装。発表UUIDへの部分的な関連付けは上記を参照。

## 本体の試験入口の検証（2026-09-15）

- 最新mainを音声ブランチへ通常マージし、本体core検証、Mac/iPhone Simulatorの署名なしビルド成功。
- iPhone 17 Pro / iOS 26.5 Simulatorでホーム「音声を試す」→録音準備画面→戻る→再度開くを確認。ブランド画像と接続入力、録音ボタンを表示。画面を開くだけではマイク権限を要求しない。
- 今回のUI確認ではマイクを起動していない。実音声の実機録音、画面を閉じた録音の再取得、TestFlight実配布は別途確認する。
