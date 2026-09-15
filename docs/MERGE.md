> 移植先での優先事項：必須チェック名やレビュー件数を移植元と同じと仮定しない。scripts/merge_preflight.pyは最新のbranchとrulesetsを読む。保護なしをAPIで確認できた場合は旧環境の3チェックを必須としない。取得失敗や未知のルールは停止する。下記の旧環境固有の記述よりこの段落を優先する。

# Codexによるマージ前確認

2026-09-09現在、レビュー必須0件。本人のPRを本人がマージできる。GitHubの自己Approve操作は不要。CI必須、最新main追従、PR経由は維持。

## 古いworktreeから始める場合

作業ツリーを `git status --short` で確認し、他の作業を上書きしない。`git fetch https://github.com/MinobeRyo/kanpeki.git main` の後、`git show FETCH_HEAD:AGENTS.md` と `git show FETCH_HEAD:docs/MERGE.md` を読む。最新ルールを確認してから、自分のbranchへmainを通常のmergeで反映する。force pushや別worktreeのcheckout変更はしない。手元の確認スクリプトが古い場合も最新mainを取り込んでから使う。

## 各PRで実施

1. GitHubでPRのbaseがmain、対象branch/差分が自分の依頼範囲か確認する。最新mainに対する差分を読む。`Shared/Models.swift`の変更はMac/iPhone両側、Xcode設定はBundle ID・Team・署名、CD変更はSecrets名・対象environment・配布先まで確認する。関連Issueと現在のdocs/STATUS.md、docs/CD.mdも参照する。
2. main取り込みによる競合を解消し、影響に合うテストを実行してpushする。共通の進捗ファイルを全worktreeで上書きしない。
3. `python3 scripts/merge_preflight.py PR番号` を実行。現在の保護・main SHA・PR SHA・main取り込み・必須CI・マージ状態を照合する。取得エラー、権限不足、UNKNOWN、pending、失敗は停止扱い。保護を自動解除しない。Write権限で保護APIを読めない場合は、権限のある担当者に確認を依頼する。
4. ユーザーからマージが許可されていて、差分レビューと必要な検証も済んでいれば、表示された `--match-head-commit` 付きコマンドで直ちにマージする。これは自動承認ではない。--adminは使わない。実行が拒否されたらmain/PR/CIを再取得し、原因に対処する。mainが直前に進む競合はGitHubの必須チェックで判定される。
5. 2件以上は1件ずつ。前のマージ後に次のPRへ最新mainを取り込み、CI完了とpreflightを再確認する。
6. マージ結果、対象SHA、テスト結果、未検証の実機項目をIssueへ報告する。ActionsのTestFlight CDも確認し、アップロード済み・Apple審査中・配布可能を区別する。配布が失敗したらCD Issueを完了扱いにしない。

preflightは読み取り専用。エラーがないことを保証するものではなく、既知のマージ条件の取りこぼしを減らす。各Codexが最新mainを取得して初めて更新ルールが届く。既存セッションへ自動配信はされない。
