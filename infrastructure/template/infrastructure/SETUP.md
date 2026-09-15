# 新しいGitHubへ移す手順

このディレクトリの内容を新規Gitリポジトリに初回コミットし、`DESTINATION_REPOSITORY`へpushします。既存アプリの履歴を含むforkは不要です。

## GitHub

`github-settings.json`に必要なSecret名、変数名、初期値、メンバー、必須チェックを出力しています。

- `testflight` environmentを作成。deployment branchはmainだけ。
- 各`*_ENABLED`変数は最初はfalse。通知先・実機リンク・署名を確認してから必要なものをtrueへ。
- mainのPR必須、core/mac/phoneチェック必須、最新main追従、承認必須0件。現在のサーバー側設定を`merge_preflight.py`で毎回確認。
- `status:todo/doing/blocked/review/done`、`team-room`ラベルを作成。
- メンバーのWrite招待・受諾を確認。GitHub、Apple、Codex、Slackの権限はそれぞれ別。
- GitHub Secretsの値はAPIで読み戻せません。管理者が元の秘密鍵から新しいenvironmentへ標準入力で登録します。値をJSON/Issue/チャットへ書かない。

## Apple / ビルド

`settings.json`のApple値が未指定なら、コード内に`CONFIGURE_...`を残します。まず元リポジトリで設定ファイルを埋めて再exportするか、全箇所をレビューして設定してください。
既存TestFlightアプリを使うか、新しいアプリ登録をするかを決めます。同一アプリならBundle ID/Teamを維持し、既存より大きなビルド番号から開始する必要があります。新リポジトリのActions run_numberは1からなので、そのまま既存アプリにアップロードすると重複します。ビルド番号戦略を変更・確認してからCDを有効化してください。
新しいApp IDなら証明書/プロファイル、外部テストグループ、審査連絡先、説明を登録。Appleの審査完了は自動化の成功とは別です。
Mac Developer ID配布、iPhone TestFlight、Mac TestFlightを個別に有効化して確認します。

## Slack / Codex

通知Botは移植先のSecretsとチャンネルIDを設定して接続します。元repoと同じBotを使うかを確認し、別アプリならOAuthをやり直します。
相談は[公式Codex Slack設定](https://chatgpt.com/codex/settings/connectors)から接続。新repoを利用できるクラウド環境を作成し、対象チャンネルにCodexを追加します。
`@Codex DESTINATION_REPOSITORY のこのスレッドを整理して。返信は3行200文字以内、相談のみでコード変更なし。`で実際の返信を検証してください。移植だけでこの接続は有効になりません。

## 本番前の確認

相談→AI返信→Issue→worktree→PR→CI→マージ→CD→Slackリンク→Mac/iPhone実機確認を一度通します。
`provenance.json`には再利用基盤の元commitとファイルハッシュを残しています。発表では事前の基盤準備と当日作ったアプリ機能を分けて説明してください。
