# SlidePacer / 発表準備

kanpekiの発表準備用macOSアプリです。本文・発表者ノートをChatGPTのMCP接続で分析し、原文IDを照合して時間配分を表示します。

[起動・MCP接続・検証手順](../../docs/MCP_INTEGRATION.md) を参照してください。

```sh
# リポジトリのルートから
make slidepacer-test
make slidepacer-build
```

Xcodeでは `Kanpeki.xcworkspace` の `SlidePacer` schemeを使用します。旧Ollamaのモデル設定は履歴資料です。現在の画面からローカルLLMを起動・呼び出す操作はありません。ChatGPTのモデル設定はアプリから指定しません。
