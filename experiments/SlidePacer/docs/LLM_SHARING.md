# モデルのダウンロードを全員に求めない運用

別の場所からのチーム利用は、ホストMacを1台決め、Tailscale経由で接続する方針です。このリポジトリには接続先アドレスや認証情報を保存せず、各アプリのBase URLで設定します。

## 画面とロジックだけ確認する人

モデルは不要です。アプリのプリセット、入力、プロンプト編集を確認でき、回帰テストも実行できます。分析結果を新しく生成する操作にはLLMが必要です。モデルがない状態で推論できたように見せるダミー結果は返しません。

## 実際の分析を試す人

1台のチーム用MacでOllamaとQwen3.5:9bを起動し、クライアントのBase URLをそこに向けます。原文・ノート・プロンプトはそのMacへ送られます。ホストの起動とネットワーク到達性が必要で、同時利用の待ち時間は別途検証します。

## 別の場所から使う：Tailscale経由

チームの検証では、Qwenを動かすホストMacを1台用意し、メンバーはTailscaleのVPN経由で接続します。ホストだけがQwenを取得し、メンバーにはTailscaleとSlidePacerが必要です。Tailscale Serveはtailnet（許可された端末のネットワーク）内でローカルのHTTPサーバーを共有します。[公式Serveガイド](https://tailscale.com/docs/features/tailscale-serve)

```text
メンバーのSlidePacer → Tailscale内のHTTPS → localhostの転送処理 → Ollama → Qwen
```

### ホスト担当者の準備

1. [公式のTailscaleアプリ](https://tailscale.com/docs/concepts/macos-variants)をインストールします。学校・会社の既存ネットワークへ参加しないよう、個人アカウントでログインし、ハッカソン専用のtailnetを用意します。macOSのVPN/機能拡張許可は本人が行います。既存のTailscaleがある場合は重複インストールしません。
2. チームで使うtailnetとメンバーを確認し、アクセス方針で対象メンバーからホストのHTTPSポート443への接続を許可します。既存の広い許可があると追加ルールだけでは制限できないため、既存ルールも確認します。公開先URL・アカウント・認証情報はGitへ保存しません。
3. ホストだけOllamaと `qwen3.5:9b` を用意します。Ollamaの待ち受けは `127.0.0.1:11434` のままにします。
4. ホストで `experiments/SlidePacer` フォルダへ移動し、転送処理を起動します。Python 3の標準ライブラリだけを使います。

   ```sh
   cd experiments/SlidePacer
   python3 scripts/ollama_proxy.py
   ```

   このターミナルは開いたままにします。転送処理は `127.0.0.1:11435` だけで待ち受け、Ollama（`127.0.0.1:11434`）へ正しいHostヘッダーで送ります。Ollama 0.33.3は共有用ホスト名のまま転送すると403を返すため、この処理が必要です。転送対象は `GET /api/version`、`GET /api/tags`、`POST /api/generate`（`stream: false`）です。モデル管理用APIは転送しません。
5. 別のターミナルで以下を実行します。Standalone版macOSアプリのCLIをフルパスで呼ぶ例です。

   ```sh
   /Applications/Tailscale.app/Contents/MacOS/Tailscale status
   /Applications/Tailscale.app/Contents/MacOS/Tailscale serve --bg --https=443 http://127.0.0.1:11435
   ```

   初回にHTTPS有効化の案内が出た場合は、ホスト担当者が内容を確認して設定します。表示された `https://...ts.net` を接続先としてメンバーへ伝えます。これは例示URLではなく、実際に表示されたURLを使ってください。`--bg` によりターミナルを閉じても共有が続き、Tailscaleの再起動後も再開します。使わないときは下の停止コマンドを実行してください。[CLIと停止の仕様](https://tailscale.com/docs/reference/tailscale-cli/serve)

Tailscale Funnel、ルーターのポート開放、Ollamaの `0.0.0.0` 待ち受けはこの構成では使いません。Serveは上記の転送処理を介してOllamaへ接続するので、接続を許可するのは信頼できるチームメンバーに限ります。分析に必要な本文・ノート・プロンプトはホストへ送られます。

### 学校・会社のネットワークに入ってしまった場合

同じ学校・会社のメールでログインすると、既存の組織ネットワークに参加する場合があります。知らない端末が表示されたら、そのネットワークでLLM共有を開始せず、先に参加先を確認してください。

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale down
/Applications/Tailscale.app/Contents/MacOS/Tailscale logout
```

`down` はVPN接続を停止し、`logout` はこの端末のログインを解除します。組織側の管理画面にある端末登録や履歴の削除とは別です。登録削除は [Machines画面またはAPI](https://tailscale.com/docs/features/access-control/device-management/how-to/remove)で行い、自分に権限がなければ組織のTailscale管理者へ自分の端末の削除を依頼します。別アカウントへの切替だけで過去の登録が消えたとは判断しません。他の人の端末や組織全体のアクセス設定は変更しません。

その後、学校・会社とは別の個人アカウントでチーム専用tailnetを作り、参加者を確認してから必要なチームメンバーだけを許可します。知らない相手が見えないことを表示フィルターだけで判断せず、ネットワークの所属と権限を確認します。

### メンバー側の準備

1. Tailscaleをインストールして個人アカウントでログインし、チーム専用ネットワークへの招待を受けて接続します。学校・会社のネットワークと取り違えないでください。ホスト担当者のアカウントやパスワードは共有しません。
2. SlidePacerでバックエンドをOllama、Base URLをホストから伝えられたHTTPS URL、モデルを `qwen3.5:9b` にします。メンバー側ではOllamaやモデルのダウンロードは不要です。
3. temperature `0`、num_ctx `16384`、maxTokens指定OFFでプリセットを分析します。まず1人ずつ試し、接続・完了時間・ホストの負荷を確認します。

`127.0.0.1` をメンバー側のBase URLに設定すると、そのメンバー自身の端末を参照してしまいます。遠隔利用ではホストから伝えられたURLを使います。

### 負荷を抑える運用

初期運用は「同じモデルだけを使い、推論リクエストは1件ずつ処理」です。1資料の分析は複数リクエストに分かれるため、複数人の資料が丸ごと順番に処理される保証はありません。混雑時は待ち時間やタイムアウトが増えます。

設定を明示してホストを起動する場合は、先に既存のOllamaサーバーを通常の方法で終了します（CLIなら起動したターミナルのCtrl+C、Ollamaアプリなら終了）。推論中に停止しないでください。その後、次を別ターミナルで実行します。

```sh
OLLAMA_HOST=127.0.0.1:11434 \
OLLAMA_NUM_PARALLEL=1 \
OLLAMA_MAX_LOADED_MODELS=1 \
OLLAMA_MAX_QUEUE=4 \
OLLAMA_CONTEXT_LENGTH=16384 \
OLLAMA_KEEP_ALIVE=5m \
ollama serve
```

- 同時にメモリへ載せるモデルを1つ、モデルあたりの同時推論を1件、待機リクエスト上限を4件にします。待機上限を超えると503エラーになり、時間を置いて再実行が必要です。
- アプリ側の `num_ctx` は16384に合わせます。`OLLAMA_CONTEXT_LENGTH` は既定値であり、クライアント指定に対する強制上限ではありません。
- `OLLAMA_KEEP_ALIVE` は既定の待機保持時間です。APIが `keep_alive` を指定するとそちらが優先されます。
- 1件の分析中でもCPU/GPU負荷・発熱は発生します。同時処理制限はCPU/GPU使用率の上限設定ではありません。
- ホストがスリープ・終了・切断すると、メンバーの分析も利用できません。まず利用時間を決め、給電し、スリープさせずに使います。
- 終了時は次のコマンドでHTTPS共有を停止します。モデルも解放したければ、分析が終わったことを確認して `ollama stop qwen3.5:9b` を実行します。

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=443 off
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status
```

共有停止後は `No serve config` など、対象の転送がなくなったことを確認します。共有停止はOllamaサーバーの停止とは別です。転送処理も止める場合は、そのターミナルでCtrl+Cを押します。ホストを再起動した後はOllamaと転送処理を起動し直してください（Serveの設定だけは残ります）。

このコマンドは説明用です。README更新だけで稼働中Ollamaの設定やOSのスリープ設定は変更されません。[Ollamaの並列数・キュー・モデル保持の仕様](https://docs.ollama.com/faq)

## SSHをすでに使っている場合

Mac同士ですでにSSH接続を使える場合は、利用者側からポート転送できます。

```sh
ssh -N -L 127.0.0.1:11435:127.0.0.1:11434 user@llm-host
```

`user` と `llm-host` はチームで決めた接続先に置き換え、アプリのBase URLを `http://127.0.0.1:11435` に設定します。Ollamaはホストの `127.0.0.1:11434` のまま動かせます。SSHはユーザー認証と暗号化された転送を担います。SSH接続の権限設定はホスト担当者が行い、このPRで自動設定はしません。

直接LAN経由で共有する方法もありますが、Ollamaは初期状態でlocalhostのみ待ち受け、ローカルAPI自体には標準で認証がありません。待ち受け変更とアクセス制限が必要です。安易にインターネットへ直接公開せず、チームで接続範囲を決めてから設定します。[公式FAQ](https://docs.ollama.com/faq)・[認証仕様](https://docs.ollama.com/api/authentication)

個人Macを共有したくない場合は、チーム専用端末を用意するか、検証担当者が分析結果を必要範囲だけ共有する運用から始められます。JSON書き出しには元資料・プロンプトが含まれるので、共有対象を確認してください。クラウドAPIへの切替は現状の実装には含まれません。

## このPRでの確認範囲

ホスト1台でTailscale 1.102.3の導入、個人アカウントへの切替と他端末0台を確認しました。Ollama 0.33.3は上記のlocalhost限定・並列1・モデル1・待機4・context 16384で起動し、Qwen3.5:9bが短い接続確認に正常応答しました。

Serveの初回有効化を確認し、ホスト自身から共有HTTPS URLへのバージョン取得と短いQwen推論が200で成功しました。転送処理のテスト6件も成功しています。チームメンバーの参加は別途必要です。他メンバー端末との接続、同時推論、iPhoneからの推論は未検証です。SSH・ファイアウォール・学校側のアクセス設定は変更していません。これらはホストでの確認であり、利用者全員の接続確認ではありません。

転送処理の回帰テスト（Ollama・モデル不要）:

```sh
python3 scripts/test_ollama_proxy.py
```
