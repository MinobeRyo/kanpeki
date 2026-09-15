# チーム全員が確認・マージする手順

2026-09-15確認：MinobeRyoはAdmin、takurateruyoshi・ini-ei・mao-sonobeはWrite。mainのbranch保護は無効、適用中rulesetsは空。レビューの必須承認はない。現在値は毎回取得し、この文書だけで判断しない。
ユーザーは各担当とそのCodexが依頼範囲の修正・テスト・PR・マージを進める運用を承認している。別メンバーの承認待ちや自己Approveの操作は不要。

1. `git status --short`で他の作業を上書きしないことを確認する。
2. `git fetch origin main`、`git show origin/main:AGENTS.md`で最新ルールを確認。必要に応じて自分のbranchへmainを通常mergeする。共有worktreeのcheckoutを勝手に変えない。
3. 対象差分を読み、変更に必要なテストを実施。Shared通信契約なら両アプリ、通知なら送信条件・短さ・秘密情報の扱いを確認。
4. `python3 scripts/merge_preflight.py PR番号`で現行ルールとmain、対象SHA、GitHubチェック、競合を確認。無効化された任意CIのskipと必須CIの未成功を区別する。取得失敗・未知のrulesetは原因を解消して再確認。
5. 表示されたコミット固定のマージコマンドを実行する。force push、--admin、自己承認の偽装は不要。
6. 複数PRは一つずつ。mainが更新されたら次のPRを更新して再確認。
7. Issueで結果を報告。マージとアプリ配布は別なので、TestFlightの利用可能状態を確認するまで配布完了とは書かない。

古いworktreeのスクリプトが旧リポジトリの3チェックを必須とする場合は、最新mainへ更新してから実行する。GitHubの公開ルールを確認しただけでは実機の正常動作は保証されない。
