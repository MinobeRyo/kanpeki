---
name: kanpeki-team
description: カンペきでIssueの作業開始・進捗報告・worktree作成・PR引き継ぎ・マージ前確認を行うときに使う。
---

Read `AGENTS.md` and `docs/TEAM.md` from the repository root. Use `scripts/team.py board` to inspect current work, then read the assigned issue and latest comments. Never invent what teammates are doing.
Use one issue per worktree. `start NUMBER slug` creates a new worktree; `bind NUMBER` binds an existing feature worktree. Before coding, post the intended scope and acceptance criteria using `report --state doing --body-file FILE` if issue posting is authorized; otherwise prepare the text for the user.
The worktree context is private to its Git directory; do not put an active-task file in the shared common Git directory or tracked docs.
At scope changes, blocking points and handoff, append a report. Use `review` for a PR awaiting review; `done` only when the described work is actually done. Do not overwrite others' reports. A failed GitHub request is not a published update. Read back uncertain results before retrying.

For merging, read `docs/MERGE.md` and the current main version of AGENTS.md. Required approvals are currently zero; this does not mean self-approval is supported. Fetch live GitHub protection and run `scripts/merge_preflight.py PR_NUMBER`. Review the diff against current main, especially Shared/Models.swift, Xcode signing, and CD. If the user authorized merging and all checks pass, use the printed commit-pinned merge command. Never use --admin or silently alter branch protection. After each merge, refresh main and rerun the next PR checks. A merged PR and a successful TestFlight upload do not imply external beta distribution completed.

For brainstorming, scope changes, blocked dependencies, or demo planning, use the sibling kanpeki-facilitator skill. Report concrete progress and evidence, including what a human should verify next. Slack forwarding is a separate configured service; do not claim it ran just because the Issue comment exists.

## Slackは要点だけ

- 通常の投稿は3行・200文字以内を目安に「結果／次に必要な操作／リンク」。進展のない繰り返し報告はしない。
- Issue報告の冒頭3行に要点を書く。Branch・Session・Update-idや作業ログはSlackへ転記しない。詳細はIssue/PRに残す。
- PRタイトルは利用者に分かる変更点にする。配布通知はバージョン・配布状態・アプリのリンク、スレッドは変更点と確認事項だけ。PR本文を全文転載しない。
- 未接続の状態を伝える場合は「Slack通知は稼働中。AIの自動返信は未接続。」の一文でよい。既知の状態を毎回付記しない。
