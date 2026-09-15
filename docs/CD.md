# GitHub Actions → 内部TestFlight配布

現在の正規入口は[自動配布の運用](AUTOMATIC_DELIVERY.md)。2026-09-15、PR #32/#52/#53の更新後、Mac/iPhone両方の0.1.0 (1018.1.0)を内部TestFlightへ配布できた記録がある。[根拠と未完了の招待](STATUS.md)。最新mainの配布や全員インストールを保証する記録ではない。

## 現行経路

PRの必要チェック→mainへ統合→TestFlight CDのLinux事前確認→共通core/Mac/iPhone検証→両アプリを同じコミットから署名・アップロード→Apple処理待ち→対象内部グループ割当→Slackで状態確認。旧Mac TestFlight CDは案内のみで二重配布しない。一般App Store公開・外部ベータ審査をこのCDから提出しない。

内部テストはApp Store Connectユーザー招待とTestFlight招待の受諾が必要。外部用公開リンクを内部ビルドの入口にしない。iPhoneとMacは別アプリ・別内部グループ。[Mac手順](MAC_TESTFLIGHT.md)。

## 設定の確認

実装上の参照は `.github/workflows/testflight.yml` と `slack-release.yml`。現在はrepository Secrets/Variablesを参照する。古い文書に従ってEnvironmentだけへ登録しても現在のworkflowへ自動移行しない。値は出力・共有しない。

- Variables: `NATIVE_CI_ENABLED`、`IOS_TESTFLIGHT_ENABLED`、`MAC_TESTFLIGHT_ENABLED`をtrue。配布通知は`SLACK_NOTIFY_ENABLED`。
- Apple Secrets: `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8_BASE64`。
- iPhone署名: `IOS_DISTRIBUTION_P12_BASE64`、`IOS_DISTRIBUTION_P12_PASSWORD`、`IOS_APPSTORE_PROFILE_BASE64`。
- Mac署名: 共用Apple Distributionに加え`MAC_APPSTORE_PROFILE_BASE64`、`MAC_INSTALLER_P12_BASE64`、`MAC_INSTALLER_P12_PASSWORD`。
- Slack: repositoryの`SLACK_BOT_TOKEN`、`SLACK_CHANNEL_ID`。内部テストの案内は[AUTOMATIC_DELIVERY](AUTOMATIC_DELIVERY.md)。

証明書・契約・対象アプリの変更は権限と影響を確認する。既存証明書を勝手に失効させない。Base64は暗号化ではない。秘密値はGit/Issue/チャットへ保存しない。

## 実行と判定

配布は同時実行せず、署名中のrunを新pushで中断しない。concurrencyはFIFOを保証せず、待機が置換される場合がある。配布直前に対象SHAとmainを比較し、古いrunは安全停止する。

ビルド番号は「1000 + TestFlight CD実行番号.再実行回数.0」。旧repoと同じAppleアプリへ同時配布しない。再試行前に対象番号がAppleへ届いていないか確認する。署名一時ファイルは後処理で削除し、生ログ・archiveを成果物へ公開しない。

CI成功、署名成功、アップロード、Apple処理完了、内部割当、招待受諾、端末のインストールを別々に確認する。Macの公証DMGは補助経路で[MAC_INSTALL](MAC_INSTALL.md)参照。マージ方法は[MERGE](MERGE.md)。

## 履歴

移植元の外部TestFlight成功リンクや旧採番は移植当時の実績で、現repoの成功根拠には使わない。[MIGRATION](MIGRATION.md)と[STATUS](STATUS.md)に出所と現repo実行を分離した。
