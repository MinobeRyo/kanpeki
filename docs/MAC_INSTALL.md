# Macで確認する

TestFlight版の準備・配布状態は[MAC_TESTFLIGHT.md](MAC_TESTFLIGHT.md)を参照。以下はDeveloper ID版の導入手順です。

Mac配布版はDeveloper ID署名とApple公証に成功したDMGのみを公開します。以下は移植元のDeveloper ID配布手順で、現repoのDMG配布成功・現在のSecrets有効性は本監査では未確認。主経路の両内部TestFlightは成功記録があります（[STATUS](STATUS.md)）。配布できる版は[GitHub Releases](https://github.com/MinobeRyo/kanpeki/releases)とSlackのMac配布通知で確認してください。最新の作業状況は[Issue #28](https://github.com/MinobeRyo/kanpeki/issues/28)に記録します。

Slackの「Mac版をダウンロード」から入手できます。非公開GitHubのため初回は招待受諾済みアカウントでログインしてください。macOS 14以降、Apple Silicon/Intel両対応。

1. KanpekiMac.dmgを開き、「カンペき」をApplicationsへドラッグする。
2. Applicationsの「カンペき」を開く。初回に画面収録、PowerPointの操作、ローカルネットワークの利用を許可する。画面収録の許可後はアプリ再起動が必要な場合がある。
3. MacとiPhoneを同じネットワークにつなぎ、PowerPointを開いて接続・スライド同期を確認する。PowerPointは別途インストールが必要。

リンクを押すだけでインストールやOSの権限許可を自動実行するものではありません。iPhone版TestFlightのMac上での実行は、画面収録とPowerPoint制御を担うこのMac companionの代わりにはなりません。

## 配布担当

Apple Developer/XcodeでDeveloper ID Application証明書を発行し、対応する秘密鍵とともにP12へ書き出す。GitHubのtestflight環境Secrets `MAC_DEVELOPER_ID_P12_BASE64` と `MAC_DEVELOPER_ID_P12_PASSWORD` を登録する。既存ASC Secretsは公証に利用する。秘密値をIssue/PRへ載せない。

設定後、repository variable `MAC_DISTRIBUTION_ENABLED=true` を登録し、mainのMac distributionを実行。CI成功→Universalビルド→署名→公証Accepted→DMGへ公証チケット添付・検証→コミット別GitHub Release→Slack通知。署名・公証の失敗時はDMGを公開しない。リリースタグはmac-<commit SHA>。同じSHAの再配布は既存Releaseを確認してから対処し、黙って差し替えない。

各Slack通知のMacリンクは通知時点で存在する直近のMac配布版です。iPhoneの通知ビルドとMacのコミットが同一とは限りません。正確なMacビルドとコミットはMac配布通知/Releaseで確認できます。

P12はmacOSの`security import`で読み込める形式を使います。書き出しツールによってはMAC検証エラーになるため、一時キーチェーンへのimportとDeveloper ID署名IDの認識を確認してからSecretsを更新してください。CIのパスワード値や秘密鍵はログに出さないでください。
