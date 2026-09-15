> 2026-09-15更新：現行は両アプリの内部TestFlight状態を定期確認する。実行根拠は[STATUS](STATUS.md)、配布手順は[AUTOMATIC_DELIVERY](AUTOMATIC_DELIVERY.md)。

# Slack配布通知

CD終了時に、親メッセージへ対象バージョン・ビルド番号・Appleの内部配布状態・CI結果を投稿し、スレッドへ変更点（PRタイトル最大3件）と短い実機確認項目を返信する。失敗したCDも対象。Apple APIで対象ビルドと内部グループへの割当を照合し、成功ログだけで「配布可能」と表示しない。

ボタンはアプリ・CD結果・変更コミットを開く。TestFlightのテスター向けURLを検証して登録した場合だけ、TestFlightボタンを追加する。URLがない段階では招待メール/インストール済みTestFlightから開く。Slackのリンクを押すだけでアプリのインストールや端末の現在バージョン取得は行わない。

## 初回接続

1. Slackの対象ワークスペースで通知用Botを作成/インストールし、Bot Token Scopeはchat:write。Botを通知先チャンネルへ招待する。全チャンネルの履歴閲覧権限は不要。
2. GitHub repository Secret `SLACK_BOT_TOKEN`にBotトークンを登録する。トークンをチャット・PR・gitへ貼らない。
3. repository Variable `SLACK_CHANNEL_ID`を登録。必要なら `TESTFLIGHT_TESTER_URL`へ動作検証したAppleのHTTPSリンクを登録する。公開招待リンクは自動作成しない。
4. **repository variable** `SLACK_NOTIFY_ENABLED=true`で有効化。未設定では通知ジョブをスキップする。
5. Slack release notificationをworkflow_dispatchで最新の完了済みCD run ID指定で実行し、親＋スレッドとボタン遷移を確認する。重複がないことを確認してから再送する。

## Codexが更新PRへ記載すること

利用者に何が変わるか、理由、確認してほしい操作、既知の制約をPR本文に書く。技術変更だけなら「アプリ機能の変更なし」と明記する。通知ではPR本文をplain_textで扱い、Slackの@channel等として解釈させない。長文は省略しPRリンクへ誘導する。全履歴の自動要約や、そのビルド以降の変更は混ぜない。現行の1 PRずつmainへ統合する運用を前提に、CD対象コミットへ紐づくマージ済みPRを表示する。

## 状態と制限

通知はCD完了後と毎時に確認し、変化があれば元投稿を更新する。キャッシュ失効や不確かな送信は重複確認が必要。クリック時のSlack本文更新には別途Slackインタラクションの受信サーバーが必要で、この構成には含まない。通知のリンク先では現在の情報を確認できる。

Slack障害はCDと別のworkflowで失敗するためアップロード結果を変更しない。親投稿成功・返信失敗の可能性があるため、POST失敗時に無条件再試行しない。CIログには投稿本文・署名情報を出さない。

[Slack公式 chat.postMessage](https://docs.slack.dev/reference/methods/chat.postmessage)のthread_tsで返信する。

## AIの進捗・相談

配布通知とは別に `SLACK_PROGRESS_ENABLED=true`（repository variable）でteam.pyの進捗コメントを転記できる。Slack Botとチャンネルは既存設定を共用。進捗から実装AIを再起動しない。入力側の公式@Codex接続、壁打ち、役割整理は[AI_TEAM.md](AI_TEAM.md)。


## 移植元のアプリ確認手順（履歴）

以下の公開リンク/DMG説明は2026-09-14時点。現行の内部TestFlightは[AUTOMATIC_DELIVERY](AUTOMATIC_DELIVERY.md)を優先する。

2026-09-14、公開チャンネル89_codexハッカソンへの進捗/変更内容共有はユーザー承認済み。通知Botの参加と実送信は確認済み。TestFlight参加リンクをtestflight環境変数TESTFLIGHT_TESTER_URLに登録した。

iPhoneは通知の「iPhoneで試す」からTestFlightへ進む。初回はTestFlightのインストールと参加/インストールが必要。通知のバージョンと端末の表示を確認する。参加リンクは更新ごとに変えない。

Macは署名・公証済みGitHub Releaseが存在した時に「Mac版をダウンロード」が追加される。Mac配布完了時にも独立して通知する。まだ配布がなければ架空のリンクは出さない。詳細はMAC_INSTALL.md。

## AIを呼ぶ（接続後）

公式Codex SlackアプリをCodex設定から接続し、kanpekiのクラウド環境を用意してチャンネルに@Codexを追加する。現在のkanpeki-team通知Botとは別アプリ。

例: `@Codex MinobeRyo/kanpeki のこの更新について、確認するポイントを3つ教えて。`
例: `@Codex MinobeRyo/kanpeki の kanpeki-facilitator に従い、このスレッドの相談を整理して。候補と反論、次の検証を出して。`

人間がメンション→その発言とスレッド履歴を入力→クラウドタスク→同じスレッドへ結果。追加相談は同じスレッドで再度メンションする。相談のみでは勝手にマージせず、修正依頼はIssue/PR/CIを経由する。全チャンネル投稿を無条件にAIへ流す方式ではない。公式連携のインストールと実応答確認は未完了。

[公式Codex Slack連携](https://learn.chatgpt.com/docs/third-party/slack)

## Slackは要点だけ

- 通常の投稿は3行・200文字以内を目安に「結果／次に必要な操作／リンク」。進展のない繰り返し報告はしない。
- Issue報告の冒頭3行に要点を書く。Branch・Session・Update-idや作業ログはSlackへ転記しない。詳細はIssue/PRに残す。
- PRタイトルは利用者に分かる変更点にする。配布通知はバージョン・配布状態・アプリのリンク、スレッドは変更点と確認事項だけ。PR本文を全文転載しない。
- 未接続の状態を伝える場合は「Slack通知は稼働中。AIの自動返信は未接続。」の一文でよい。既知の状態を毎回付記しない。
