# Mac/iPhone本体を開いて確認する

基準は[STATUS](STATUS.md)のmainスナップショット。未マージPRの画面を現行手順へ混ぜない。実装出所は[MIGRATION](MIGRATION.md)、配布は[AUTOMATIC_DELIVERY](AUTOMATIC_DELIVERY.md)。サンプル画面は[SCREEN_REVIEW](SCREEN_REVIEW.md)。

## アプリを用意する

チームの主経路はMac/iPhoneそれぞれの内部TestFlight。AppleとTestFlightの招待受諾・対象ビルドのインストールが必要。最新mainのマージ通知だけでは更新済みと判断しない。[CD](CD.md)、[Mac](MAC_TESTFLIGHT.md)。

開発時は`Kanpeki.xcworkspace`または`Kanpeki.xcodeproj`を開き、`KanpekiMac` / `KanpekiPhone`を選ぶ。本体はmacOS 14以降/iOS 17以降。実機署名は各自が使える設定をローカルで指定し、共有Bundle ID・配布設定を無断変更しない。カメラ用ローカルSwift Packageを含む。基本スライド操作にクラウドAPIキーは不要。

## mainの基本導線

1. MacでPowerPointと保存済みPPTXを用意する。最初は1資料・ウィンドウ表示のスライドショーで確認する。
2. Macの準備パネルから画面を検索し、対象ウィンドウを選び共有する。プレビューで原稿/デスクトップを誤共有していないか確認する。
3. 同じPPTXの原稿を取り込み、PowerPoint操作を有効にする。画面収録とオートメーションは必要な操作時にOSで許可する。許可後の再起動が必要な場合がある。
4. Macの接続待機を開始し、iPhoneで近くのMacを検索・選択する。Macで本人の端末を確認して許可する。まず同じ信頼できるネットワークで試す。
5. 時間を調整→入力→確認→適用。準備完了後、発表を開始する。iPhone下部スライドの右/左を短くタップして送り戻り、指の移動でポインター。離した時にページを送らない。
6. タイマー詳細から一時停止/再開、終了確認を行う。時間切れで自動送り・強制終了しない。終了後の「発表の結果」は実測時間と関連付いた当端末カメラを示す。

PR #67の準備カード・統合開始、PR #70の簡素化、PR #71のQR直接接続は、この監査時点では未マージ。導入時は対象版の手順へ更新する。現在の基本通信は暗号化MultipeerConnectivityで、QR/WebSocketへ全面移行したとは扱わない。

## 任意の分析

- カメラ：Macの準備パネル/iPhone「…」の設定・結果から対象/前後を確認して明示開始。閉じても計測を続ける。端末内メモリのみ。[カメラ](CAMERA_DEVELOPMENT.md)。
- 音声：未接続ホームの試験入口、または発表中「…」→発表の音声から明示録音。カメラを停止する。同発表の終了/切断/背景で停止し、取得済み録音を明示送信。[音声手順](AUDIO_CAPTURE.md)。mainはMacのPython音声サーバーを別起動する。ネイティブ音声ホストは未マージPR #72。
- 音声の結果とカメラ終了サマリーはまだ別表示。統一時系列・原稿への改善適用は未接続。見本のスコア/結果は実データではない。

## 実機で確認すること

両端末を同じ対応版へ更新する。画像identity v2対応前との混在は受け付けない。

- ページ・画像・原稿一致、PowerPoint側手動変更、先頭/末尾、連打、ドラッグ後の指離し。
- 共有停止/画像停止/切断時の表示と操作禁止、再接続の最新状態。古い操作を再送しない。
- 時間・振動、背景/ロック復帰、権限拒否、カメラ/録音の終了停止。
- 外部ディスプレイ、縦横比、文字拡大/VoiceOver、長時間負荷。

ノートは保存済PPTXの取込時点。資料のパス・枚数・ID・順序不一致では表示しない。PowerPointのアニメーション段階や実描画時刻との厳密な同期は保証しない。ログ時刻はMacの観測時刻であり音声との同期時刻ではない。[PowerPoint検証](POWERPOINT_VALIDATION.md)、[画像同期](SLIDE_FRAME_SYNC.md)。

## SlidePacerの独立実験

同workspaceの`SlidePacer`は別ターゲット（最低macOS設定26.5）。モデルなしでUI・回帰テストを確認でき、分析時だけOllama/FoundationModelsを用意する。[説明](../experiments/SlidePacer/README.md)、[セットアップ](../experiments/SlidePacer/docs/TEAM_SETUP.md)、[任意のチーム共有](../experiments/SlidePacer/docs/LLM_SHARING.md)。チームホストへ接続すると本文・ノート・プロンプトが送信される。自動fallbackはしない。

MCPによる資料/発表振り返りは未マージPR #58、事前結果の本体適用は #34/#15。実験の成功を本体完成と扱わない。

## ビルドとテスト

```sh
bash scripts/check.sh core
bash scripts/check.sh mac
bash scripts/check.sh phone
swift test
npm test
```

対象に応じて実行する。これらは実機権限・ペアリング・精度・配布検証を代替しない。[チーム手順](TEAM.md)、[現在の根拠](STATUS.md)。
