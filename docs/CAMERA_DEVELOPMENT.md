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

### 取消・再開始のライフサイクル保護

UIと撮影キュー間でrun UUIDを同期して検証し、取消済みのpermission後configure、旧outputのフレーム、旧runの中断通知・heartbeat・較正要求を新計測へ適用しない。中断通知observerはrun別に登録・停止時に解除する。`startRunning()`自体は同期APIのため呼出中の取消を中途中断できないが、戻り直後に再検証して停止し、取消後の入力を分析・表示しない。カメラを自動再開しない。

CameraRunGateの合成回帰テストは取消・再開始・旧入力・旧failureを確認する。実OSのpermissionダイアログ、遅延通知、背景復帰を実カメラで検証したことは意味しない。

Issue #14、branch `codex/camera-analysis`、専用worktreeで進める。カメラの入力状態・顔向き・頷き候補の実装と回帰テストを今回のPRで扱い、笑顔判定と実会場検証を残すためIssue全体は閉じない。

Camera analysisはUbuntuでNode回帰テストを実行する。ネイティブ検証は既存Native checksにパスとSwiftテストを追加し、NATIVE_CI_ENABLEDの設定に従う。CI未実行やskipを実機成功と扱わない。マージはdocs/MERGE.mdのpreflightを使い、配布は別工程とする。
