# CI/CDと新規アプリの接続点

現在の配布スクリプトを再利用するため、当日作成するプロジェクトには以下の名前を使います。製品名を変更するときはスクリプト・workflow・Fastfileの参照も一緒に変更します。

- `Kanpeki.xcodeproj`、共有scheme `KanpekiMac` / `KanpekiPhone`
- Mac target成果物 `KanpekiMac.app`（各packageスクリプトの参照を確認）
- `Config/Mac-Info.plist`、`Config/Phone-Info.plist`
- `Config/Mac.entitlements`、`Config/Mac-AppStore.entitlements`。権限は新しい仕様に必要なものだけ設定する。
- `Tests/run_tests.sh` は新規アプリのコア仕様を検証し、失敗時に非0終了する。空の成功スクリプトで代用しない。
- `Shared/Models.swift`などの通信契約は仕様書から合意・新規実装する。
- アイコン、画面、アプリSwiftコード、Xcodeプロジェクトはこのパッケージに含まれない。

移植済みPythonテストは配布・通知・worktreeの基盤テストです。製品の受入テストではありません。
署名なしCI、署名とアップロード、Apple審査、実機での配布確認を別々に記録します。
