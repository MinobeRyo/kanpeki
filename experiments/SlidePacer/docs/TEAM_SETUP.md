# チームでSlidePacerを動かす

コードはGitで共有し、Qwenのモデル本体はOllamaで別に用意します。モデルをリポジトリへ同梱する必要はありません。UIのビルドや原文・時間配分の回帰テストはLLMなしで実行でき、実際の内容分析時だけOllamaへ接続します。

以下のコマンドは `experiments/SlidePacer` フォルダ内で実行します。モデルを各自で取得しない選択肢は [LLM_SHARING.md](LLM_SHARING.md) を参照してください。

## 各自のMacで分析する構成

```text
SlidePacer → http://127.0.0.1:11434 → 自分のMacのOllama / Qwen3.5:9b
```

1. [Ollamaの公式手順](https://docs.ollama.com/quickstart)でインストールして起動します。
2. モデルを取得します。

   ```sh
   ollama pull qwen3.5:9b
   ```

3. Ollamaアプリが起動していればサーバーの二重起動は不要です。CLIだけで使う場合は別ターミナルで `ollama serve` を実行し、そのまま開いておきます。
4. 接続とモデルを確認します。

   ```sh
   curl http://127.0.0.1:11434/api/version
   ollama ls
   ```

5. `SlidePacer.xcodeproj` をXcodeで開き、My Macを選びます。現プロジェクトの最低OS設定はmacOS/iOS/visionOS 26.5なので、対応するOS・Xcode SDKが必要です。
6. Signing & CapabilitiesのTeamは自分の開発チームを選びます。既存の開発者のTeam IDを使える必要はありません。Outgoing ConnectionsとUser Selected FileのRead/Writeは有効にします。
7. アプリで以下を設定し、プリセット「技術LT」を読み込んで分析します。プリセットは動作確認用です。

|項目|設定|
|---|---|
|バックエンド|Ollama|
|Base URL|`http://127.0.0.1:11434`|
|モデル|`qwen3.5:9b`|
|temperature|`0`（比較後の推奨。現在の画面の初期値は0.7）|
|num_ctx|`16384`|
|maximumResponseTokensの指定|OFF（ページ選択は内部で768）|
|思考モード|アプリがOFFに設定|

Ollamaのインストール・モデル取得・サーバー起動は[公式CLIリファレンス](https://docs.ollama.com/cli)を参照してください。

## LLMを入れずに開発する

UIの開発と以下の回帰テストは、モデルのダウンロードやOllamaの起動なしで進められます。分析ボタンを押す場合には接続先が必要です。

```sh
python3 scripts/check_editorial_planner.py
```

このコマンドはMacのXcode/Command Line ToolsとPython 3を使用し、34件の原文・配分処理のテストを実行します。テスト用の入力はテストコード内にあり、個人のPPTXや評価結果JSONは不要です。

署名を行わないMac向けビルドの確認は次で行えます。

```sh
xcodebuild -project SlidePacer.xcodeproj -scheme SlidePacer \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build
```

## 1台のMacをチームの推論サーバーとして使う場合

```text
メンバーのアプリ → 推論担当MacのAPI → Ollama / Qwen
```

全員がモデルをダウンロードしなくても、接続先を推論担当Macに統一できます。モデルの実行環境を揃えやすいので、結合確認・デモの選択肢になります。そのMacの起動と到達可能なネットワークが必要です。

現在のアプリはBase URLを編集できるため、接続先をコードへ埋め込む変更は不要です。ただし `127.0.0.1` は「アプリが動いている端末自身」を指すので、別のMacにはつながりません。

Ollamaは通常127.0.0.1だけで待ち受けます。LAN共有にはサーバー側の`OLLAMA_HOST`設定等が必要です。[公式FAQ](https://docs.ollama.com/faq#how-can-i-expose-ollama-on-my-network)を参照してください。この手順書の作成時点ではLAN公開や接続変更は実施していません。

ローカルAPIは標準では認証不要なので、共有するならチーム内にアクセスを限定する構成にします。インターネットへ直接公開する構成にはしません。[認証の仕様](https://docs.ollama.com/api/authentication)

Mac同士なら、既存のSSH接続を使う場合にクライアント側で次のポート転送を利用できます（SSHの設定が済んでいる場合の例）。

```sh
ssh -N -L 127.0.0.1:11435:127.0.0.1:11434 user@llm-host
```

この場合、アプリのBase URLは `http://127.0.0.1:11435` です。Ollama自体は推論担当Macのlocalhostで待ち受けたまま利用できます。`user`と`llm-host`は実際の接続情報へ置き換えます。iPhoneからのLAN接続、ローカルネットワーク権限、HTTP接続の設定は別途実機で確認が必要です。

## Gitに含めるもの

- Swiftコード、Xcodeプロジェクトの共有設定、テスト、スクリプト、READMEとこの手順書。
- モデル名・設定・比較条件などの小さなメタデータ。

`.gitignore`でビルド成果物、モデル本体、個人のスライド、資料本文やプロンプトが入った`evaluation/`、書き出したJSON、Xcodeの個人設定を除外しています。元データがない状態で過去の評価スクリプトを実行すると入力不足になるため、精度比較を再実行する人は評価用資料を別途用意してください。

共有時点で個人の`xcuserdata`は同梱していません。

## 比較時の環境

2026-09-10にOllama 0.33.3、Qwen3.5:9b（Q4_K_M）で検証しました。モデルタグは更新されることがあるため、厳密に同じモデルか確認するには`MODEL_CONFIG.json`のdigestと`/api/tags`の値を照合します。初回は2資料40ページ×5温度、追加で重要ページと全体判定を再実行しました。0は今回の保持チェックと安定性で有力でしたが、未知の資料での最適値を保証するものではありません。
