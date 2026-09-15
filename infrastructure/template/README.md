# 仕様書から開発するチーム用リポジトリ

既存の開発基盤を再利用し、アプリ本体は各メンバーの仕様書から新規実装する構成です。アプリのソース・画面素材・旧Git履歴・秘密鍵は含まれていません。

1. `specs/FEATURE_TEMPLATE.md`を各機能の仕様書として埋め、担当Issueを作成します。
2. `infrastructure/BUILD_CONTRACT.md`に合わせてXcodeプロジェクトとテストを新規作成します。
3. `infrastructure/SETUP.md`に従ってGitHub/Apple/Slackを設定します。
4. PRのCI成功後、最新mainと保護設定を確認してマージ。設定済みのCDが配布し、人間がTestFlightで確認します。

アプリが未実装の間、core/mac/phone CIは成功しません。基盤をコピーしただけで製品や配布が完成したとは扱わないでください。
