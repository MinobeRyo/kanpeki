# 実装・残件・検証のスナップショット

確認日：2026-09-15 13:42 JST。基準main：`59618470b0dd3ed88289b5565a29879f4ed6fc7c`。常時最新の担当・配布状態を保証する一覧ではない。作業状況は[最新Issues](https://github.com/MinobeRyo/kanpeki/issues)、統合状態は各PR、配布は対象コミット・ビルド番号で再確認する。[全文書の棚卸し](DOCUMENTATION_INVENTORY.md)。

## mainにある機能

「部分実装」は記載範囲がコードにあること。CI・合成試験を実機操作・精度・配布の成功へ読み替えない。

| 機能 | mainの範囲と根拠 | 残件 |
|---|---|---|
| ブランド・基本UI | ロゴ組込み、少数色、下部スライド、原稿スクロール。[BRAND_UI](BRAND_UI.md)、[Issue #24](https://github.com/MinobeRyo/kanpeki/issues/24) | 画面確認モードの固定・翻訳・改善例はサンプル。iPhoneの簡素化はPR #70で統合済み（[MINIMAL_UI](../specs/MINIMAL_UI.md)）。全画面実UI受入 #10/#66は別 |
| PPTX・PowerPoint | 保存済PPTXノート、実ページ観測、操作、資料不一致保護。[検証範囲](POWERPOINT_VALIDATION.md) | 実PowerPoint・権限・複数画面 #21 |
| 画像・通信 | 暗号化MultipeerConnectivity。資料/page/capture identityで画像と操作を照合。[PR #54](https://github.com/MinobeRyo/kanpeki/pull/54)、[仕様](SLIDE_FRAME_SYNC.md) | 実遅延/再接続/遷移描画 #20。QR直接TLS接続と1台承認はPR #71/#64で統合済み。[QR](QR_CONNECTION.md)・[承認](PEER_APPROVAL.md)。実機受入 #19/#65、WebSocketは別 |
| ポインター | 移動→Mac overlay、旧session/範囲/期限切れ拒否。[仕様](POINTER_DEVELOPMENT.md) | 手ぶれ閾値・実投影/VoiceOver #16 |
| 時間・通知 | Mac正本の開始/停止/再開/終了、期限1回通知、入力→確認→適用。[タイマー](../specs/PRESENTATION_TIMER.md)、[通知](../specs/PRESENTATION_NOTIFICATIONS.md)、[段階入力](../specs/STEPWISE_SETUP.md) | 実端末振動・背景復帰 #11/#18。音声通知は未接続 #41 |
| カメラ | 任意開始、対象/前後選択、顔向き/うなずき候補、未計測、UUID保護、端末内集計・時間帯。[PR #59](https://github.com/MinobeRyo/kanpeki/pull/59)、[PR #62](https://github.com/MinobeRyo/kanpeki/pull/62)、[仕様](../specs/CAMERA_ANALYSIS.md) | 笑顔判定・実会場精度/熱/長時間 #14。生映像保存・端末間合算は範囲外 |
| 発表結果 | Mac確定の実測時間＋同発表に関連付いた当端末カメラ。[PR #51](https://github.com/MinobeRyo/kanpeki/pull/51)、[仕様](RESULTS_DEVELOPMENT.md) | 共通結果への音声・改善候補・統一時系列・実UI削除 #13/#17 |
| iPhone音声 | 任意録音、発表/録音UUID、終了/切断停止、手動送信、返却ID/数値検証。候補章選択・保持録音再生。[PR #60](https://github.com/MinobeRyo/kanpeki/pull/60)、[音声](AUDIO_CAPTURE.md)、[聞き直し](../specs/FILLER_CHAPTERS.md) | Mac音声ホストは本PR #72で追加（下記）。VAD #40、連続送信 #41、時計/スライド履歴 #17/#38、実機精度 #39 |
| 原稿要約・時間配分 | 別アプリSlidePacer、原文選択・配分・Ollama/FoundationModelsの実験。[README](../experiments/SlidePacer/README.md) | 本体への事前結果適用・iPhone表示 #34/#15。実資料品質 #56/#68 |

## 未マージPR（mainの完成機能に含めない）

| PR・確認head | 内容 | 限界 |
|---|---|---|
| [#58](https://github.com/MinobeRyo/kanpeki/pull/58) `1283343` | 資料MCP実験＋発表全体の音声/カメラ根拠集約・返却・Mac/iPhone振り返り | [push報告](https://github.com/MinobeRyo/kanpeki/issues/33#issuecomment-5674648100)済み。事前資料分析のiPhone適用とは別経路。実ChatGPT新ツール返却・実機・配布は未検証 |
| [#67](https://github.com/MinobeRyo/kanpeki/pull/67) `97f4e3f` | Mac準備カード・確認付き開始・共有復旧・案内保存 #61 | CI成功報告。実PowerPoint/権限/狭幅/操作一巡は未検証。「最大3操作」全達成ではない |
| [#73](https://github.com/MinobeRyo/kanpeki/pull/73) `4af8e58` | 引用・数値・列挙・否定保持 #68 | 合成回帰と実資料品質を区別 |

## 文書から見つかった残件・未確定

- ASSISTANCE_FLOW A01〜A06：翻訳の原文比較、個別採用/修正/戻す、モデル準備同意/取消は本体未接続。#15/#34と後続MCP方針の整理が必要。ローカル専用案とChatGPTへの明示共有は別経路で、勝手なクラウドfallbackを認めない。
- B01〜B05：単一主マイク/カメラの端末間調停、言語選択、フィラー誤検出の利用者訂正は未接続。#12/#14/#40の受入項目の明文化を確認する必要がある。現在iPhone音声開始はカメラを停止し、同時計測できると見せない。
- R01〜R04：改善候補1つ、音声・カメラ・スライドの同発表時系列、元原稿へ戻る統合導線は未完了。#13/#17（担当中）を重複実装しない。異なる時計を受信時刻で整列しない。
- 案内の二回目抑止・再表示・Reduce Motion/読み上げの全画面受入は #10/#61。固定モード見本は専用本番モードの完成ではない。
- リアルタイム翻訳、Keynote/Canva操作・ノート、多カメラ、感情/理解率、永続結果保存は採用済み初期実装と区別する。
- [提出物](SUBMISSION.md)：台本案はあるが、本監査では提出PPTX/PDF・2分実動画・受理記録を確認していない。外部作成/提出は未確認。

## 検証・配布

移植の出所・当時のテスト数は[MIGRATION](MIGRATION.md)に保存する。今回の文書監査で実機を新たに検証したわけではない。

- 両アプリ0.1.0 (1018.1.0)は[CD run 34923131258](https://github.com/MinobeRyo/kanpeki/actions/runs/34923131258)成功、[Issue #28報告](https://github.com/MinobeRyo/kanpeki/issues/28#issuecomment-5674062963)にApple VALID / IN_BETA_TESTING / 内部グループ割当を記録。最新mainを含むとは限らない。
- 全員利用完了とは別。[招待報告](https://github.com/MinobeRyo/kanpeki/issues/28#issuecomment-5674224642)では一部招待・受諾/追加が残る。今回はApple現在値を再照会していない。
- 主経路は両方の内部TestFlight。[チームの導入手順](TESTFLIGHT_TEAM.md)、[AUTOMATIC_DELIVERY](AUTOMATIC_DELIVERY.md)。Mac DMGは補助経路。外部公開リンクを内部配布入口にしない。
- Slackのマージ・進捗・配布通知に成功記録あり。会話AI自動返信は別接続で未確認。[SLACK](SLACK.md)。

## 本PRで追加するMac音声分析（2026-09-15）

上記mainスナップショットへの追加差分: [PR #72](https://github.com/MinobeRyo/kanpeki/pull/72)、進捗と未確認事項: [Issue #63](https://github.com/MinobeRyo/kanpeki/issues/63)。[使い方](MAC_AUDIO.md)と[iPhone側の統合範囲](AUDIO_CAPTURE.md)を参照。

- Mac上部「音声分析」から、モデル準備、録音受信、接続URL/コード、Whisper baseによるローカル分析、結果表示を実装。PythonやHomebrewの別起動は不要。
- 合成日本語WAVの受信・実推論・結果返却とiPhoneデコーダーの互換、ローカルRelease sandboxビルドを確認。画面はNSHostingView描画で確認。
- 実ウィンドウ操作、実iPhone録音、会場での精度は未確認。main統合・最終CI・TestFlightの現在値は上記PR/Issueを確認する。リアルタイム分析・共通時計・スライド履歴の自動同期は未対応。
