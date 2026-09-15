# Mac版TestFlight

Macアプリは「カンペき Mac」（Apple ID `6811774996`、Bundle ID `jp.kanpeki.prototype.mac`）。iPhone版とは別アプリ。主なチーム確認経路は内部TestFlight。[現在の配布根拠](STATUS.md)、[Issue #28](https://github.com/MinobeRyo/kanpeki/issues/28)、[App Store Connect](https://appstoreconnect.apple.com/apps/6811774996/testflight)を参照する。

内部テスターはAppleユーザー招待とTestFlight招待を受諾する。全員共通の公開参加URLはない。外部グループや公開リンクの登録だけで内部ビルドを利用できるとは扱わない。

## CD

共通TestFlight CDがcore/Mac/iPhoneを検証し、MacをApple Distribution + Mac App Store profileで署名、Installer DistributionでPKG署名、Appleへアップロード後に内部割当する。旧Mac TestFlight CDは退役案内。設定は[CD](CD.md)と[AUTOMATIC_DELIVERY](AUTOMATIC_DELIVERY.md)を参照。

両アプリ0.1.0 (1018.1.0)のApple VALID / IN_BETA_TESTING確認記録があるが、最新mainの配布・全員のインストールとは区別する。Mac公証DMGは補助経路。

## Sandboxで実機確認する項目

画面収録、PowerPoint Apple Events操作、同一ネットワーク接続、PPTXノート、ログ保存を実機で確認する。署名なしビルド成功をこの受入成功にしない。PowerPointのApple Events一時例外は対象を限定し、審査上の承認はAppleが判断する。

PPTXは選択したアクセス権で一時領域へコピーして読む。権限の再要求・再起動・資料取り直しの実挙動も確認する。外部ベータ/一般公開審査は内部配布とは別工程で、審査連絡先の個人情報はAppleだけへ登録する。
