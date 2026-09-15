> 移植元の操作説明。現在の有効化・検証状況はMIGRATION.mdとSLACK.mdを優先する。

# 4人チームの作業共有

## 共通の入口

- [作業一覧](https://github.com/MinobeRyo/kanpeki/issues?q=is%3Aissue+is%3Aopen+-label%3Ateam-room)
- [作業中](https://github.com/MinobeRyo/kanpeki/issues?q=is%3Aopen+label%3Astatus%3Adoing)
- [ブロック中](https://github.com/MinobeRyo/kanpeki/issues?q=is%3Aopen+label%3Astatus%3Ablocked)
- [チーム連絡室](https://github.com/MinobeRyo/kanpeki/issues?q=is%3Aopen+label%3Ateam-room)

Issueの担当者、状態ラベル、最新の進捗コメントで「誰が何をしているか」を見る。ローカルで動くAIやworktreeは自動監視されない。AIに開始・区切り・終了時の報告を指示する方式。オフライン中は他人に見えない。
チーム連絡室のコメントをグループチャット代わりにする。タスク固有の話は担当Issueに書き、決定事項は連絡室からリンクする。通知は各自GitHubのWatch/Subscribeで設定する。配布通知と実機フィードバックはSlackへ接続できる（docs/SLACK.md）。担当と進捗の正本は引き続きIssues。

## メンバー（担当を推測しない）

| GitHub | 現在確認できている担当 |
|---|---|
| takurateruyoshi | スライド読み込み・Mac/iPhone連携。現在の状態は担当Issueを参照 |
| ini-ei | 現在の担当は本人の申告待ち |
| MinobeRyo | 現在の担当は本人の申告待ち |
| mao-sonobe | 現在の担当は本人の申告待ち |

これは開始時の情報。以降の現状はIssueを参照する。

## 各自の最初の操作

1. GitHub招待を受諾。Git、GitHub CLI、Python 3、Xcodeを用意し `gh auth login`。
2. `gh repo clone MinobeRyo/kanpeki` してCodexで開く。コードと `.agents/skills` が一緒に届く。
3. 自分の作業Issueをテンプレートから作り、担当者・変更予定箇所・完了条件を記載する。
4. 下記の依頼文でCodexに開始を頼む。

> AGENTS.mdに従い、Issue #番号を担当してください。このIssueへの開始・進捗・終了コメントと自分への担当設定を許可します。別worktreeで実装し、PRを作成してください。docs/MERGE.mdに従い、確認に成功したらこの作業のPRをマージしてよいです。

## worktreeの実例

```sh
python3 scripts/team.py board
python3 scripts/team.py start 2 slide-sync
# 表示されたworktreeディレクトリに移動
# Codex側ですでにworktreeを作った場合は start の代わりに bind 2
python3 scripts/team.py report --state doing --body-file /tmp/progress.md
```

`progress.md` に「目的、変更予定のファイル、今回の完了条件」を書く。レビュー待ちは `--state review`、困っている場合は `blocked`、次に再開する状態は `todo`。完了時は `done` と検証結果を報告し、PRマージ後にIssueを閉じる。reportはIssueを勝手にcloseしない。

startはoriginのデフォルトbranchをfetchし、隣の `<repo>-worktrees/<login>/` に `work/<login>/<issue>-<slug>-<短いID>` branchを作成する。削除は自動では行わない。マージと未コミット変更の有無を確認して `git worktree remove PATH` を実施する。`--force`は使わない。
紐付け情報は `git rev-parse --git-path kanpeki-task.json` に保存されるためworktreeごとに独立し、Git管理外。DerivedDataも各worktreeの `.build/` に分離する。
同じMacでアプリを同時起動する場合、同じBundle IDやBonjourサービスが干渉し得るので、E2E検証は一つのペアずつ実施する。

## 更新のルール

開始前、変更範囲を変えた時、ブロック時、PR作成時、終了時に報告する。長時間作業でも進捗が変わった区切りで報告する。
Issue本文は目的と完了条件のために使い、進捗は追記コメント。人やAIが同時に本文を上書きするのを避ける。
他担当に依存するときはIssue番号と期待する入出力を明記する。`Shared/`変更は両側担当と合意して小さいPRにする。
切断中の投稿は成功したことにしない。reportは投稿IDを返す。失敗後はIssueに同じ `update-id` がないか確認してから再送する。
GitHubのラベル変更とコメント追加はトランザクションではない。部分失敗時は最後のコメントとラベルの両方を確認する。

## 統合とリリース

mainへの直接pushは初回設営のみ。以後PRを経由し、レビュー承認は任意。本人または本人のCodexが、マージ依頼の範囲でdocs/MERGE.mdの確認後に統合できる。実際のサーバー側保護を毎回確認する。
Mac/iPhoneの署名・TestFlight配布はリリース担当が行う。GitHub招待はApple Developerチームへの招待を兼ねない。
CIは署名なしビルドとコアテスト。画面収録、PowerPoint、実機接続は人が検証する。

## 壁打ちとAIによる進行管理

[AI_TEAM.md](AI_TEAM.md)を参照。AIは相談の選択肢・反論・検証、担当/依存関係と次の一手を整理する。発言とIssueを根拠にし、本人が未受諾の担当・期限は提案と明記する。開始/進展/詰まり/確認依頼/終了をreportで共有する。Slack受信には公式@Codex連携などの接続が別途必要。
