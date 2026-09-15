# 会場での引き継ぎ：2026-09-15

このリポジトリを4人の共有正本とする。ユーザーの「これまでの作業内容を集約」に基づき、採用した設計、画像、運用構成、検証状況を統合した。その後のユーザー許可により、既存アプリ本体・テスト・Slack通知機能も移植対象に変更した。詳細は[MIGRATION](MIGRATION.md)。

## 最初に読む順序

1. [AGENTS.md](../AGENTS.md)：全員のAIが従う共通ルール。
2. [PRODUCT.md](../specs/PRODUCT.md)：合意した機能と未決定事項。
3. [SCREEN_FLOW.md](../specs/SCREEN_FLOW.md)：接続・準備・手持ち／固定・終了・障害復帰。
4. [ASSISTANCE_FLOW.md](../specs/ASSISTANCE_FLOW.md)：案内、Macローカル翻訳、音声／カメラ、結果。
5. [実画面比率の配置](../assets/design/device-size/LAYOUT.md)：393×852ptと1440×900を仮基準にした設計。
6. [提出案内](SUBMISSION.md)：会場写真の内容、スライド構成、2分動画案。
7. [Codex活用の証拠](CODEX_EVIDENCE.md)：示せる具体例と記録方法。

## 成果物の所在と現在の状態

| 対象 | 正本 | 状態 |
|---|---|---|
| ロゴと配色 | [BRAND](../specs/BRAND.md)、[原本](../assets/brand/app-icon.png) | Xcode組込み済み（#24）。配布版はSTATUSで確認 |
| 画面遷移 | [仕様](../specs/SCREEN_FLOW.md)、[画像](../assets/design/screen-flow/iphone-states.png) | 設計済み。通信・操作未検証 |
| 案内・分析 | [仕様](../specs/ASSISTANCE_FLOW.md)、[画像](../assets/design/assistance/screens.png) | 設計済み。モデル・性能未確定 |
| iPhone発表中 | [画像](../assets/design/device-size/iphone-live.png) | 画像モック |
| iPhone接続 | [画像](../assets/design/device-size/iphone-connect.png) | 画像モック |
| Mac準備 | [画像](../assets/design/device-size/mac-preparation.png) | 画像モック |
| 過去の配置案 | [旧デザイン](../assets/design/archive/README.md) | 非採用案。最新仕様に優先しない |
| 壁打ちの手順 | [skill](../.agents/skills/presentation-dialogue/SKILL.md) | 共通手順あり。各自の利用環境で実行 |
| チーム・worktree | [TEAM](TEAM.md) | 1タスク・1担当・1branch・1worktree |
| CI/CD | [DELIVERY](DELIVERY.md)、[確認範囲](CI_PREPARATION.md) | 両アプリ内部TestFlight CD成功記録あり。最新配布/全員利用は別 |
| Slack | [共有構成](SLACK.md) | マージ通知・スレッド・進捗通知は実配信確認済み。AI返信は別途接続 |
| 技術上の引き継ぎ | [ARCHITECTURE](../specs/ARCHITECTURE.md) | 目標境界と部分実装。STATUSと個別仕様を参照 |

## これまでの検討で決まったこと

- PDFだけでは原稿ノートを引き継げないため、PPTXとノートを扱う。描画は既存プレゼンアプリを活用する。
- 学生の発表を対象に、機能数より迷わない操作を優先。スマホ下部のスライドを直接操作する。
- 次へ・戻るボタンを削除。右／左の短いタップと、移動によるポインターを区別する。
- チュートリアルは任意の短い案内。キャラクターを使うが、発表中の操作を妨げない。
- 準備時の翻訳・原稿分析と、本番時の音声・カメラ観測、終了後の振り返りを画面設計に含めた。
- App Store向け実装、ローカルLLM、画面取得、通信、カメラ、振動の実現性は新アプリで別途確認する。

## 現在の入口と過去の検証

現在の実装・残件・未マージPR・両アプリ配布成功の根拠は[STATUS](STATUS.md)。以下は移植直後の履歴で、現在もCI/CDが未接続という意味ではない。

### 移植直後に確認した範囲

新リポジトリでは[準備資料チェック](https://github.com/MinobeRyo/kanpeki/actions/runs/34898809481)が成功した。これは資料の存在確認で、アプリのビルド・署名・配布成功ではない。
別環境でApple APIからアプリと外部TestFlightグループを読み取る接続確認を行ったが、新リポジトリのGitHub Actionsからの署名・アップロード・外部配布は未確認。旧アプリの動作報告を新アプリの実績として転記しない。
Actions節約は、文書変更でMacを起動しない・同じコミットのネイティブ検証を重複させない構成案まで。旧環境向けの変更案をこのリポジトリに適用したとは扱わない。

## 引き継がないデータ

最新のユーザー許可で旧アプリのソースとテストは移植した。バイナリ・git履歴は移植しない。認証情報、個人連絡先、チャット全文、端末固有パスも入れない。議論は現在の決定事項に整理し、古い未採用提案を合意事項へ混ぜない。旧実装由来であることはMIGRATIONに明記する。

## 作業開始時の確認

人間が本番実装の開始を指示したら、最小デモ範囲・担当・入出力・検証方法をIssueで確定する。会場入りだけで本番コードを生成しない。会場写真は提出物の案内であり、持ち込み範囲のルール全文ではない。コード移植は後続のユーザーの明示的な許可に基づく。
