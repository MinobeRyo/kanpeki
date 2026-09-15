# カンペき：チーム開発

対象リポジトリ: MinobeRyo/kanpeki

ユーザーの許可に基づき、既存のMac/iPhoneアプリ本体とテスト、設計、チーム運用を集約しました。移植由来と実装差分は[移植状況](docs/MIGRATION.md)、起動手順は[APP_SETUP](docs/APP_SETUP.md)を参照してください。配布バイナリや秘密鍵は含みません。

まず[共通ルール](AGENTS.md)と[現在の実装・残件・配布](docs/STATUS.md)を読む。要件はspecs/PRODUCT.md、開発運用はdocs/TEAM.mdを参照する。docs/PREPARATION.mdは開始許可前の履歴。全文書の分類は[棚卸し](docs/DOCUMENTATION_INVENTORY.md)を参照する。

設計画像の全機能が実装済みとは限りません。ネイティブCIと両アプリの内部TestFlight CDには成功記録がありますが、最新mainの配布・全員のインストールとは別です。[配布構成](docs/AUTOMATIC_DELIVERY.md)と[Slack通知](docs/SLACK.md)を参照してください。

アイコンとテーマカラーはspecs/BRAND.md、事前のCI確認範囲はdocs/CI_PREPARATION.mdを参照する。

[接続から終了までの画面遷移と操作仕様](specs/SCREEN_FLOW.md)には、全状態の表示・操作・復帰先と代表画面の画像をまとめています。

[キャラクター案内・翻訳・分析・振り返りの画面設計](specs/ASSISTANCE_FLOW.md)を参照してください。

## 会場での引き継ぎ

[全成果物と検証状況](docs/HANDOFF.md)を入口に、[提出案内・2分動画台本](docs/SUBMISSION.md)、[Codex活用の証拠](docs/CODEX_EVIDENCE.md)、[技術構成](specs/ARCHITECTURE.md)、[Slack連携案](docs/SLACK.md)を確認してください。

[実画面サイズを考慮した配置](assets/design/device-size/LAYOUT.md)と画像：

- [iPhone：発表中](assets/design/device-size/iphone-live.png)
- [iPhone：接続](assets/design/device-size/iphone-connect.png)
- [Mac：準備と翻訳](assets/design/device-size/mac-preparation.png)

会場写真は提出物の案内として整理しました。既存アプリの移植と、最新デザインの実装は別の作業です。

## 並行作業を始める

[worktreeの作成・一覧・片付け](docs/WORKTREES.md)。担当Issueごとに `python3 scripts/team.py start 番号 作業名`、作成済み一覧は `python3 scripts/team.py list`。

映像解析はMac/iPhoneのカメラ補助パネルに実装。[カメラ仕様](specs/CAMERA_ANALYSIS.md)と[開発・検証手順](docs/CAMERA_DEVELOPMENT.md)を参照。

音声取得・解析の初版は [AudioCapture](experiments/AudioCapture/README.md) で単体検証できます。[移植範囲と本体への統合点](docs/AUDIO_CAPTURE.md)・[進捗と残作業（Issue #12）](https://github.com/MinobeRyo/kanpeki/issues/12) を参照。本体iPhoneの未接続ホーム「音声を試す」から録音・分析を検証できます。発表UUIDへの明示録音・終了停止・同発表の音声結果入口はPR #60で部分統合済み。時計・統一結果の統合と実機検証は残件です。
