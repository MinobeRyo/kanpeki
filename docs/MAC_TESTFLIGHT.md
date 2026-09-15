# Mac版TestFlight

Macアプリは `カンペき Mac`（Apple ID `6811774996`、Bundle ID `jp.kanpeki.prototype.mac`）。iPhone版とは別のTestFlight登録です。配布状態は[App Store Connect](https://appstoreconnect.apple.com/apps/6811774996/testflight)と[Issue #22](https://github.com/MinobeRyo/kanpeki/issues/22)で確認します。

外部グループ「カンペき開発チーム」は招待専用です。公開リンクは無効。4人の招待メールをMacで開きTestFlightへ参加します。Apple審査・ビルド処理の完了前はインストールできません。

## CD

main → 必須CI（通常Mac・Sandbox Release・iPhone・コア）→ Mac TestFlight CD → Apple Distribution署名 + Mac App Store profile → Installer Distribution署名PKG → Appleアップロード → 処理待ち → 外部ベータ審査へ提出。

repository variable `MAC_TESTFLIGHT_ENABLED=true` で有効。既存 `testflight` environmentのApple APIとApple Distribution Secretsを再利用し、次を追加します。

- `MAC_APPSTORE_PROFILE_BASE64`
- `MAC_INSTALLER_P12_BASE64`
- `MAC_INSTALLER_P12_PASSWORD`

秘密値はログ・リポジトリへ書きません。署名鍵は一時キーチェーンに読み込み、後処理で削除します。既存のDeveloper ID/DMG配布も継続します。

## Sandboxで確認する項目

画面収録とPowerPoint操作、同一ネットワークでiPhoneとの接続、PPTXノート読み込み、ログ保存を実機で確認します。PowerPoint操作には同アプリだけを対象とするApple Events一時例外を申請します。この例外の承認はAppleが判断します。PPTXは選択時のアクセス権でアプリの一時領域へコピーして読み取り、終了時に削除します。

審査メモにはPowerPointの必要性・検証手順・例外の理由を記載。審査連絡先の個人情報はAppleだけに登録します。本工程はTestFlight外部ベータ審査であり、一般公開のMac App Store審査とは別です。
