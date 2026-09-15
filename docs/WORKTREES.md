# 作業を分けて始める

1つの担当Issueに1つのworktreeを用意する。同じcloneから何個でも追加できるが、1つのworktreeを複数のCodexで同時編集しない。他人の担当Issueは使わない。

## 最初に一覧を見る

リポジトリのフォルダ内で実行する。

```sh
python3 scripts/team.py board
python3 scripts/team.py list
```

boardはチーム全員のGitHub Issue、listはこのPCの同じcloneに属するworktree・branch・Issue・担当者を表示する。listはGitHub接続が不要。別PCや別cloneのworktree一覧までは取得しない。

## 新しい作業フォルダを作る

自分が担当するIssueを選び、番号と短い英小文字の作業名を指定する。例えば、Issue #20「スライド表示とページ同期」を担当することが決まった場合：

```sh
python3 scripts/team.py start 20 slide-sync
```

これは例で、#20を自動的に担当済みにしたわけではない。ツールが最新mainから一意なbranchとworktreeを作り、保存先の絶対パスを表示する。元のフォルダの未コミット変更は持ち込まない。
表示されたフォルダをCodexで開いて作業する。端末ではそのフォルダへcdする。

```sh
python3 scripts/team.py report --state doing --body-file /tmp/start-report.md
```

start-report.mdには目的・変更範囲・完了条件を短く書く。report成功後、Issueに担当者と状態が反映され、設定済みのSlack通知へつながる。startだけでは他メンバーに開始を共有したことにはならない。

Codexが既に独立worktreeを作った場合は、そこで `python3 scripts/team.py bind 20` を使う。startでさらに二重に作らない。

## Codexにそのまま頼む文

> AGENTS.mdに従い、Issue #番号を担当してください。最新のIssueと既存worktreeを確認し、なければscripts/team.py startで作成してください。表示されたworktreeで作業し、開始・進捗・終了をIssueへ共有してください。今回の担当範囲で修正・テスト・PRを進め、マージ前は最新mainと実際の保護ルールを確認してください。

## 分割先を選ぶ

既存Issueを優先し、重複したIssueを作らない。例として、iPhone UI #10、タイマー #11、音声 #12、結果画面 #13、カメラ #14、翻訳 #15、ポインター #16、接続 #19、スライド同期 #20、PowerPoint #21、Bridge #22がある。番号と担当の最新状態はboardで確認する。ここは担当割当ではない。
依存する機能はIssue同士をリンクし、Shared/Models.swiftやXcodeプロジェクトの変更を先に共有する。

## 分離されるもの・共有されるもの

- ソース、作業branch、未コミット変更、`.build/`、タスク紐付けはworktreeごとに分離する。
- Gitのオブジェクト・remote・通常のGit設定は同じclone内で共有される。
- 同じIssueがローカルの別worktreeに紐付いていれば作成を止め、既存の場所を案内する。
- この重複チェックは全PCの分散ロックではない。同時開始の競合はIssueの担当者と直近コメントで確認する。
- 同じBundle IDのアプリやポート、カメラ、PowerPointは共有するため、実機検証はペアごとに順番に行う。

## 終了・片付け

PRを出す前にreview、完了したらdoneをreportする。done報告はIssueを閉じる前に行う。マージはdocs/MERGE.mdに従う。
完了したworktreeは未コミット／未追跡の必要ファイルがないことと、作業がmainへ統合済みであることを確認してから `git worktree remove 対象パス` で削除する。強制削除は使わない。作業branchは自動削除しない。
