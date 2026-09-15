# 初期セットアップの検証記録

2026-09-08時点。

- 非公開リポジトリ: https://github.com/MinobeRyo/kanpeki
- ini-ei / MinobeRyo: write権限で招待済み、受諾は本人の操作待ち。
- 4人目: GitHub名の確認待ち。担当を推測して割り当てていない。
- [チーム連絡室 #1](https://github.com/MinobeRyo/kanpeki/issues/1)
- [実機検証待ち #2](https://github.com/MinobeRyo/kanpeki/issues/2)
- [担当・接続仕様の合意 #3](https://github.com/MinobeRyo/kanpeki/issues/3)
- [このセットアップ作業 #4](https://github.com/MinobeRyo/kanpeki/issues/4)

## 実施した検証

- 共有skill 3個: skill-creatorのquick_validateに合格。
- 既存コアテスト17件: 成功。
- チーム用スクリプト3件: 他担当の拒否、2つの実worktreeのコンテキスト分離・上書き拒否、空の報告を投稿しないことを確認。
- `team.py start` でGitHubのmainから作業worktreeを作成。
- `team.py report --state doing` のIssueコメント投稿・担当者・ラベル設定が成功。
- `team.py board` で他のIssueを含む現状一覧を取得。
- GitHub CI: [初回実行](https://github.com/MinobeRyo/kanpeki/actions/runs/34231922904)。初回はcore・mac・phoneの3ジョブすべて成功。以降の結果は各PRを参照。

## mainの保護

GitHub側でレビュー1件を必須化。新しいpushで古い承認は無効になり、管理者にも適用する。force push・削除は禁止。
core・mac・phoneの3つのCIチェック成功と最新mainへの追従も必須。メンバーがまだ招待未受諾の間はレビュー担当がいないため、本人たちの受諾を待つ。

## 共有していないもの

Apple署名の秘密鍵、TestFlightアーカイブ、APIキー、発表者の資料、個人のCodex設定は含まない。
画像生成ツールの利用権限は各自のアカウントに依存する。共有されるのはskillとプロンプト・素材の保存ルール。

## 2026-09-09 運用更新

上記は初期の記録。現在はユーザー承認によりレビュー必須0件、PR経由・3種CI成功・最新main追従は維持。4人目はmao-sonobe。現行手順は[MERGE.md](MERGE.md)、最新状態はGitHub API/Issuesを参照。
