# ChatGPTによるMCP分析

Issue: #33 / 実資料の精度評価: #56

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

ツール数は5です。`get_presentation`はsource引数で準備用とライブ用を切り替えます。初期PoCは3機能でした。

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

元の準備アプリは別ターゲットとして取り込まれています。Mac本体の共通ホームへの画面埋め込みと、分析結果のiPhone画面への表示は未実装です。音声・カメラの分析指標もMCPへ未接続のため、取得済みとして返しません。iPhone実機、CPU/メモリ削減、長時間連続運転、TestFlightでの統合動作は別途確認が必要です。

原文ID照合は「選ばれた文章が元資料に存在する」ことを確認する仕組みです。説明の十分さや最適な時間配分を保証するものではありません。実資料の選択品質は #56 で別に評価します。
