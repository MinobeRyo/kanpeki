# アプリ本体を持ち込まず、開発基盤を移す

`infrastructure/settings.example.json`を別の作業用JSONへコピーし、移植先の`repository`を入力します。Apple識別子は決まっていなければnullのままで書き出せます。

```sh
python3 scripts/export_infrastructure.py --config /tmp/team-settings.json --output /tmp/new-team-repo
```

新規出力先のみ受け付けます。既存ディレクトリを上書きしません。
出力はCI/CD・Issue/worktree・マージ確認・短いSlack通知・共有skills・仕様書テンプレートです。追跡済みファイルの許可リストのみを使用し、アプリコード・Xcodeプロジェクト・Git履歴・認証情報・既存画像・実験コードは含めません。

手順は出力先の`infrastructure/SETUP.md`。GitHub設定はファイルコピーだけでは移りません。必要Secrets/変数一覧を生成し、署名・App ID・Slack接続を設定するまでは配布フラグを無効にします。
CIは新規アプリ未実装時に失敗します。アプリを一から実装して受入テストが成功してから配布します。

現時点では移植先リポジトリ名が未指定です。別GitHubへのpush・秘密鍵の登録・新規接続はまだ実施していません。
