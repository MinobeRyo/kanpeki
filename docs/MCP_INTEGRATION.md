# ChatGPTによるMCP分析

Issue: #33 / 実資料の精度評価: #56

事前分析の要点案を本体で確認・採用し、iPhone原稿へ届ける操作は[原稿準備](PREPARATION_NOTES.md)を参照。準備アプリで「Mac本体の資料を読み込む」を使った同一資料だけが対象です。元PPTXは変更せず、確認・採用・元に戻すは発表準備中だけ行います。実ChatGPTと実機一巡は未検証です。

## 実装した流れ

準備アプリ `apps/SlidePacer` が本文・発表者ノートに原文IDを付け、選択した共有フォルダーへ分析依頼を保存します。ChatGPTはMCPで資料を読み、重要ページと説明に使うIDを返します。アプリが依頼ID・全ページ・原文IDを再検証し、元の文章を復元して時間を配分します。推奨秒数はSwiftによる計画値です。

Mac本体は、読み込んだ資料と、Macを基準とするタイマー・PowerPointの観測ページ・iPhone接続状態を同じフォルダーへ共有できます。ローカルLLMの起動とモデル推論APIの呼び出しは、この経路では行いません。ChatGPTの画面でアプリを選び依頼を送る操作が必要です。

## 起動

前提: Node.js 22以降、Xcode 26以降、利用可能なChatGPTカスタムMCP接続、設定済みのOpenAIトンネルと公式tunnel-client。トンネル認証はPCだけに置きます。アプリにAPIキーを入力する欄はありません。

リポジトリのルートから:

```sh
npm ci --prefix integrations/mcp --ignore-scripts --no-audit --no-fund
mkdir -p .build/mcp-session
export KANPEKI_MCP_DIR="$PWD/.build/mcp-session"
export KANPEKI_TUNNEL_BIN="/path/to/official/tunnel-client"
export KANPEKI_RUNTIME_KEY_FILE="/path/to/private/runtime-key-file"
export KANPEKI_TUNNEL_ID="your-existing-tunnel-id"
node integrations/mcp/run.mjs
```

キーの値ではなく保存ファイルのパスを指定します。既存キーの期限切れ・権限不足は接続エラーになります。トンネル利用権限・継続料金の保証はこの実装に含みません。

1. `Kanpeki.xcworkspace` を開き、`SlidePacer` schemeで準備アプリを起動します。
2. 「ChatGPTとの共有フォルダーを選ぶ」で上記フォルダーを指定します。
3. PPTX/JSON/手入力から資料を取り込み、目的・聴衆・持ち時間を設定して分析依頼を準備します。
4. 依頼文をコピーし、ChatGPTで登録済みMCPアプリを選んで送信します。以前の3ツール版を使っていた場合はアプリ設定から更新します。
5. ChatGPTが `submit_analysis` を実行すると、アプリが原文を照合して結果を表示します。`get_analysis_status` の `completed` が反映完了の確認になります。
6. 発表状況も共有する場合は `KanpekiMac` のChatGPT欄から同じフォルダーを選択します。

終了は準備アプリの取消/終了、Mac本体の「共有を停止」、起動端末でCtrl+Cです。共有ファイルには資料とノートが残ります。共有フォルダーは非公開の場所に置き、Gitへ含めないでください。1フォルダーにつき準備アプリ1インスタンスを使用します。

## MCPの契約

| ツール | データと動作 |
|---|---|
| `get_presentation(source: preparation)` | 保留中の依頼ID、全ページの本文・ノート・原文ID、目的・持ち時間 |
| `get_presentation(source: live)` | Macで取り込んだ資料。表示中資料との一致を別フィールドで返す |
| `get_live_state` | タイマーの実状態、観測ページ、接続状態。未取得値はnull |
| `get_practice_report` | 最大256件のページ観測ログ。正確なページ滞在時間や発話時間ではない |
| `submit_analysis` | 全ページの原文ID選択を保存。受付とネイティブ反映は別状態 |
| `get_analysis_status` | 現在の依頼に対する反映完了・拒否・保留 |

資料分析の初期統合は5ツールでした。現在は発表全体の分析返却を加え6ツールです。`get_presentation`はsource引数で準備用とライブ用を切り替えます。初期PoCは3機能でした。

依頼の生存確認は15秒、ライブ状態は5秒で失効します。原文IDはページごと、core/detail各32件まで。未知ID・欠落・重複・古い依頼・異なる結果の再送を拒否します。同じ結果の再送は二重適用しません。ネイティブ側も独立して検証します。各共有JSONは8MB以内、HTTPは127.0.0.1で待機します。

## 検証と限界

```sh
npm test --prefix integrations/mcp
make slidepacer-test
make slidepacer-build
bash scripts/check.sh core
bash scripts/check.sh mac
bash scripts/check.sh phone
```

2026-09-15のローカル確認: MCP 18テスト、Swiftの抽出/配分/ネイティブ検証38テスト、本体coreテスト、準備アプリ/Mac本体/iPhoneシミュレーターの署名なしビルドが成功しました。合成5ページでは、準備アプリの依頼→ローカルMCP投稿→原文照合→画面表示まで成功（推奨165秒/上限300秒、未配分の注意表示も確認）。これは経路確認であり、ChatGPTによる選択品質の評価ではありません。

ChatGPTでのMCP読み取りは成功しましたが、`submit_analysis` はChatGPT側の安全性チェックに拒否され、サーバーへ未到達でした。自動反映E2Eは未完了です。実資料由来の詳細な評価内容や数値は非公開のローカル記録に保管しています。

MCPテストは実SDK経由の初期化・ツール一覧・読み取り・結果投稿と、不正データ/二重投稿/期限切れを検証します。CIにはMCP専用ワークフローを追加しました。実際のCI成否はPRに記録します。

元の準備アプリは別ターゲットとして取り込まれています。Mac本体の共通ホームへの画面埋め込みは未実装です。#86では同一資料の要点案に限り、本体での確認・採用後にiPhone原稿へ表示します。計画全体のiPhone画面や完成原稿生成ではありません。音声・カメラの指標共有と発表全体の振り返りは下記の追加統合で対応しました。未取得値は未計測のまま扱います。iPhone実機、CPU/メモリ削減、長時間連続運転、TestFlightでの統合動作は別途確認が必要です。

原文ID照合は「選ばれた文章が元資料に存在する」ことを確認する仕組みです。説明の十分さや最適な時間配分を保証するものではありません。実資料の選択品質は #56 で別に評価します。

## 発表全体の分析（音声・カメラを統合）

利用者にどんな改善を提案するかは[AI_COACHING](../specs/AI_COACHING.md)を参照してください。根拠・具体的な修正・次の練習での確認をそろえる設計案です。現在の契約は下記の最大8件の `kind / text / evidenceIDs` であり、構造化された修正/次回確認や優先1件表示は未実装です。正確なページ別時間や発話との時刻同期、前回比較を現行の取得情報から生成しないでください。

資料の事前分析に加え、本体Macの「発表をまとめて分析・依頼文をコピー」で発表終了後の振り返りを依頼できます。追加課金のモデルAPIは使用せず、既存のChatGPT MCP接続を使います。ChatGPTへ依頼文を送る操作は必要です。

### 操作

1. 更新したMac/iPhoneアプリとMCPサーバーを起動し、Macの「分析データの共有を開始」で既存MCPの共有フォルダーを選びます。音声認識結果・カメラ集計値も共有対象であることを表示します。
2. iPhoneの「発表の音声」から任意で録音し、録音終了後に既存Mac音声サーバーへ分析を依頼します。文字起こしは引き続きMacのWhisperで行います。取得済みAudioReportを、発表ID・録音IDを検証してペアリング済みMacへ渡します。音声認識サーバーの準備は #63 の担当範囲です。
3. 発表終了後、Macの「音声: 取得済み / 未共有」「カメラ: 取得済み / 未共有」を確認し、「発表をまとめて分析・依頼文をコピー」を押します。未共有のままでも、取得済みの範囲だけ分析できます。
4. ChatGPTで既存MCPアプリを選び、コピーした依頼文を送ります。MCPのツール一覧を更新し、追加の `submit_practice_analysis` が表示されることを確認してください。
5. 回答を受け取るとMac/iPhoneの「ChatGPTの振り返り」に表示します。「根拠」はGPTが生成した引用ではなく、ネイティブ側が元の分析材料から復元します。

### データと契約

- `get_practice_report(source: analysis)`：依頼ID・発表ID付きの固定した分析材料（`facts`）。本文/ノート、認識文の全区間、話速推定、フィラー候補と文脈、低音量区間、注意事項、タイマー、最大256件の同発表のページ観測、関連付いたMac/iPhoneカメラ集計と最大120件の撮影相対時間帯。
- `get_practice_report(source: live)`：従来のライブ観測に `analysisFacts` を追加。`get_live_state` は実際の取得有無を返します。
- `submit_practice_analysis`：最大8件の良かった点・改善案・限界。すべてに既存fact IDを1〜8件付けます。受付とネイティブ反映は別です。
- `get_analysis_status(kind: practice)`：ネイティブ側の反映/拒否状態。準備アプリ用の既定値は `preparation` のままです。
- `Shared/PracticeAnalysis.swift` が本体の契約です。`PhoneAnalysisEvidence` は共有世代・発表ID・録音/撮影ID・連番を持ち、旧接続・別発表・重複を拒否します。音声/カメラ由来のIDは録音/撮影IDに一致する必要があります。
- 1秒ごとの本体状態更新で、変更のある共有データだけを送ります。音声/カメラ結果の削除は次の更新または結果変更通知で反映します。iPhone由来データは180KiBまで、分析材料は4,096件・2MiBまで、1つの結果ファイルは64KiBまで。上限超過を黙って切り捨てずエラー表示します。
- 共有停止、発表変更、再接続、材料変更は保留依頼と以前の振り返りを無効にします。依頼ファイル・結果・フィードバックは共有フォルダーから削除します。アプリ停止は15秒で失効します。資料の既存共有ファイルと、ChatGPT側が既に取得したデータはこの操作では削除しません。

音声時刻は録音開始、カメラは撮影全体、ページ観測はタイマーの概算時刻です。異なる時計を同期済みと扱いません。カメラは関連付いた撮影の集計値だけで、生映像・顔画像・顔形状を渡しません。うなずき候補秒数は人数・動作回数・理解度ではありません。GPTの提案は解釈で、未計測を0や失敗と断定する指示は与えません。

### 検証

MCPの既存/追加テスト、Swiftの分析共有/原文復元テスト、core、Mac/iPhone Simulatorの署名なしビルドを実行します。`integrations/mcp/tests/native-roundtrip.mjs` はSwift生成依頼→実MCP SDK→返却JSONを検証し、`PracticeAnalysisTests --verify-exchange` が本番と同じネイティブvalidatorで照合します。この合成往復は実ChatGPT・実マイク/カメラ・実端末の通信やTestFlight配布の成功を意味しません。


今回の最終ローカル検証：MCP 30テスト、分析共有Swift 16チェック（ネイティブ受理の往復実行では17）、本体core、Mac universal / iPhone Simulator署名なしDebugビルド成功。Swift生成依頼→実SDK→返却→Swift原文復元も成功しました。既存の通知実装にMainActor警告が残ります。実ChatGPTの新ツール更新・結果返却、実端末通信、実マイク/カメラ、今回の画面操作とTestFlightは未検証です。

## Macの入口（PR #81）

メニューバー「準備」→「ChatGPTで振り返る」から開き、「共有の設定」で共有を開始/停止します。発表後は同じ画面で依頼文のコピーと結果確認を行います。発表中は「…」からも開けます。
