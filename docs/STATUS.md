# 現在の実装と検証

発表タイマーの実装・同期・検証範囲は[タイマー仕様](../specs/PRESENTATION_TIMER.md)。映像解析は[カメラ仕様](../specs/CAMERA_ANALYSIS.md)。実機確認と配布の完了とは区別する。

既存アプリをユーザーの許可で移植した。実装の出所・検証結果は[MIGRATION](MIGRATION.md)、設計は[PRODUCT](../specs/PRODUCT.md)、共有は[HANDOFF](HANDOFF.md)を参照。
PowerPoint描画の取得、PPTXノート、Mac/iPhone通信の既存コードを含む。最新デザインの全画面や分析機能が本体へ実装済みとは限らない。SlidePacerは実験であり、統合済みと扱わない。
実機・TestFlightの以前の成功は今回の新リポジトリでの検証結果と区別する。正確な検証結果は各PR／Issueへ記録する。

## 音声の取得とMac分析（2026-09-15）

実装PR: [#72](https://github.com/MinobeRyo/kanpeki/pull/72)、進捗と未確認事項: [#63](https://github.com/MinobeRyo/kanpeki/issues/63)。[Mac音声分析の使い方](MAC_AUDIO.md)と[iPhone側の統合範囲](AUDIO_CAPTURE.md)を参照。

- Macアプリ上部「音声分析」から、モデル準備、録音受信、接続URL/コード、Whisper baseによるローカル分析、結果表示を実装。PythonやHomebrewの別起動は不要。
- 合成日本語WAVの受信・実推論・結果返却とiPhoneデコーダーの互換、ローカルRelease sandboxビルドを確認。画面はテスト内のNSHostingView描画で確認。
- 実ウィンドウ操作、実iPhone録音、会場での精度は未確認。main統合・最終CI・TestFlightの配布状態は上記PR/Issueの最新結果を確認する。リアルタイム分析やスライド時刻の自動同期は未対応。
