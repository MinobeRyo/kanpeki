# チーム共有

担当と進捗の正本は[GitHub Issues](https://github.com/DESTINATION_REPOSITORY/issues)。担当や期限を推測しません。
`infrastructure/settings.json`のmembersは参加予定者です。GitHub招待受諾やApple招待とは別です。

1 Issue = 1担当 = 1worktree。`python3 scripts/team.py start ISSUE slug`で作成します。
Codexが既にworktreeを作った場合は`bind ISSUE`。実装前に`report --state doing --body-file FILE`を成功させます。
メタデータはworktree固有のGitディレクトリ、ビルド出力は`.build/`。共有進捗Markdownを全員で書き換えません。
開始・意味のある進展・詰まり・終了をIssueコメントへ追記。Slackは3行200文字を目安に要点とリンクだけ。
マージはdocs/MERGE.mdに従い、現在のGitHub保護・最新main・必須CIを確認します。自己Approveは不要です。

AIへの依頼例: 「AGENTS.mdに従ってIssue #番号を担当してください。開始・進捗・終了報告と自分への担当設定を許可します。別worktreeで実装し、検証後PRを作成してください。」
