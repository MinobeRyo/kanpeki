# カメラ解析の開発と組み込み

共通モジュールはローカルSwift Packageとして既存のKanpekiMac／KanpekiPhoneターゲットへ接続する。外部パッケージ依存はない。既存のアプリ識別子・配布先・署名設定は維持し、カメラ利用説明とMacのカメラ権限を追加した。

## テストと起動

```sh
npm test
swift test
bash scripts/check.sh core
bash scripts/check.sh mac
bash scripts/check.sh phone
```

Nodeは共通エンジンの回帰テスト、SwiftはJavaScriptCoreへの接続と結果集計。core/mac/phoneは既存のチーム検証手順。実動画の一般精度を採点する試験ではない。

Kanpeki.xcworkspaceをXcodeで開き、KanpekiMacまたはKanpekiPhoneで起動する。Macは左の補助領域の「カメラ分析」、iPhoneは「…」の「カメラの設定・結果」から準備画面を開く。撮影対象を確認して開始し、パネルを閉じて元のスライド画面へ戻る。分析なしでも元の画面に進める。カメラ解析の終了は詳細パネルから操作する。

シミュレーターは画面確認用で、カメラ解析は実機が必要。実機署名・TestFlightは既存のAPP_SETUP／CD手順を使う。

## UIと処理の境界

MacScreen／PhoneScreenがCameraControllerを保持し、CameraPanelへ渡す。補助パネルを閉じても計測を続け、アプリの背景化や画面の終了時は停止する。新規開始時に新しいセッションを作り、古い非同期結果を新しい画面へ反映しない。

カメラの追加はスライド・原稿・ページ送りの既存実装を変更しない。Issue #24のロゴ・配色・下部スライド配置を取り込み、既存メニューに接続した。ポインターはIssue #16の範囲。撮影対象と結果は端末内のみで、Shared/Models.swiftの通信契約に追加していない。接続相手への集計同期は後続の範囲。

## チームとCI

Issue #14、branch `codex/camera-analysis`、専用worktreeで進める。カメラの入力状態・顔向き・頷き候補の実装と回帰テストを今回のPRで扱い、笑顔判定と実会場検証を残すためIssue全体は閉じない。

Camera analysisはUbuntuでNode回帰テストを実行する。ネイティブ検証は既存Native checksにパスとSwiftテストを追加し、NATIVE_CI_ENABLEDの設定に従う。CI未実行やskipを実機成功と扱わない。マージはdocs/MERGE.mdのpreflightを使い、配布は別工程とする。
