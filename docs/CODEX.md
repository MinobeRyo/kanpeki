# 共有skillsとCodex設定

`.agents/skills` はGitで共有されるリポジトリ用skill。各worktreeにも同じバージョンが展開される。個人の `~/.codex` のコピーは不要。

| skill | 用途 |
|---|---|
| `$kanpeki-team` | Issueへの開始・進捗共有、worktree作成とPR引継ぎ |
| `$kanpeki-native` | Mac/iPhone・PPTX・通信の実装と検証 |
| `$kanpeki-imagegen` | 画像生成とモックの共通手順、プロンプトと成果物の保存 |

`.codex/config.toml` はworkspace-write / on-requestの共有初期値。各自が内容を読みプロジェクトを信頼した場合に読み込まれる。管理環境の制約が優先される。モデル・認証・APIキー・個人パスは固定していない。
公式資料: [Skillsの配置](https://learn.chatgpt.com/docs/build-skills)、[設定の優先順位](https://learn.chatgpt.com/docs/config-file/config-basic)。

## ImageGenの共有範囲

共有するのはプロジェクト専用skill、生成プロンプト、承認済み素材とデザインの意図。画像生成ツール自体の利用権限や課金枠はリポジトリをcloneしても付与されない。
各自のCodexで組み込み画像生成を利用できる場合はそれを使う。環境で利用できない場合は担当者に依頼し、生成済み素材をPRで共有する。API方式を選ぶ場合は各自のキーと費用が必要。キーはリポジトリ、Issue、チャットに貼らない。
このリポジトリのskillは独自のチーム用手順で、システム組み込みimagegenの複製ではない。

例: `$kanpeki-imagegen Issue #5 の発表者向けiPhoneモックを作り、プロンプトとともにPRで共有して`。
AIに渡す要件は、対象画面、ユーザーの目的、必須要素、サイズ、既存素材を変えてよい範囲。実装済みと将来案をラベルで区別する。

## 初期セットアップ確認

- GitHubの招待を受け `gh auth status` が成功する。
- Codexでrepoまたはworktreeを開き、AGENTS.mdとskillが見えていることを確認する。
- `python3 scripts/team.py board` で最新Issueが取得できる。
- `bash scripts/check.sh core` を実行する。
- iPhone実機の署名は各自Teamをビルド引数またはローカルXcode設定で指定。配布設定をPRで書き換えない。
