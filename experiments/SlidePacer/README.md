# SlidePacer：内容選択・時間配分の技術検証

PowerPointの本文と発表者ノート、発表目的、制限時間から、話す内容と各スライドの時間配分を提案するMac向けの検証アプリです。

## 開き方

リポジトリのルートにある `Kanpeki.xcworkspace` を開き、スキーム `SlidePacer`、実行先 `My Mac` を選びます。`KanpekiMac` / `KanpekiPhone` と同じworkspaceでソースを閲覧・編集できます。既存アプリとの画面・通信接続はまだ行っていません。

このフォルダの `SlidePacer.xcodeproj` を単独で開くこともできます。最低OS設定は26.5です。既存のカンペきの最低OSは変更していません。

初回は自分のSigning Teamを選んでください。検証アプリには個人のTeam IDを設定していません。

## LLMを全員にダウンロードさせる必要はありません

|やりたいこと|モデルの用意|
|---|---|
|画面・プロンプト・コードの確認や編集|不要。アプリ起動時に推論は走りません|
|原文保持・時間配分ロジックの回帰テスト|不要。下記コマンドで実行できます|
|資料をLLMで分析する|自分のOllama、または到達可能なチームの推論サーバーが必要|

別の場所からはTailscale経由で1台のホストMacへ接続する方針です。ホストが起動・接続している間だけ分析でき、推論は1件ずつ処理する設定から始めます。接続先の用意・VPN許可・メンバー接続は別途必要です。

共有先への接続方法は [LLMのチーム運用](docs/LLM_SHARING.md)、モデル取得とビルド手順は [セットアップ](docs/TEAM_SETUP.md) を参照してください。未接続の状態で分析ボタンを押すと接続エラーになります。

## 今回共有する機能

- PPTX・本文とノートのJSON・プリセットからの入力
- Qwen3.5:9bによる全体方針とページごとの原文選択
- 原文の条件・制約・表の数値を保ち、総時間に応じて内容と時間を調整
- プロンプト編集・実際の入力確認・キャンセル・分析結果JSONの保存
- FoundationModelsへの切替（Apple Intelligence対応環境が必要）

現在のOllama設定は `qwen3.5:9b` / `num_ctx=16384` / 思考OFF。今回の比較での推奨temperatureは `0` です。画面の初期値は既存の検証アプリと同じ `0.7` のため、比較条件を合わせる場合は変更してください。[モデルの検証時メタデータ](docs/MODEL_CONFIG.json)

## テスト

このフォルダをカレントディレクトリにして実行します。

```sh
python3 scripts/check_editorial_planner.py
xcodebuild -project SlidePacer.xcodeproj -scheme SlidePacer \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build
```

回帰テストはMacのSwiftコンパイラーとPython 3を使用します。その他の `scripts/` は過去の精度比較用で、個別の `evaluation/` 入力ファイルが必要です。個人資料・元資料の本文を含む評価ファイル・モデル・ビルド成果物は同梱していません。

[検証結果と制約](docs/VALIDATION.md) · [統合作業Issue #34](https://github.com/MinobeRyo/kanpeki/issues/34)
