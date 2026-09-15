# 現在の実装と検証

発表タイマーの実装・同期・検証範囲は[タイマー仕様](../specs/PRESENTATION_TIMER.md)。映像解析は[カメラ仕様](../specs/CAMERA_ANALYSIS.md)。実機確認と配布の完了とは区別する。

既存アプリをユーザーの許可で移植した。実装の出所・検証結果は[MIGRATION](MIGRATION.md)、設計は[PRODUCT](../specs/PRODUCT.md)、共有は[HANDOFF](HANDOFF.md)を参照。
PowerPoint描画の取得、PPTXノート、Mac/iPhone通信の既存コードを含む。最新デザインの全画面や分析機能が本体へ実装済みとは限らない。SlidePacerのMCP分析とMac状態の共有は #33 で統合中です。共通ホームへの埋め込みとiPhoneへの分析結果表示は未実装です。[MCP連携](MCP_INTEGRATION.md)を参照してください。
実機・TestFlightの以前の成功は今回の新リポジトリでの検証結果と区別する。正確な検証結果は各PR／Issueへ記録する。
