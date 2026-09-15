# Slack接続

通知の現在状態と設定は[docs/SLACK.md](../../docs/SLACK.md)を参照。Botトークンはrepository Secret SLACK_BOT_TOKENに保存し、manifestやコードには書かない。
manifestは送信用Bot。会話を読むAIの自動返信は別の公式Codex連携と新リポジトリの環境接続が必要。CLIへのログインや通知成功だけで、AI返信の接続完了とは扱わない。
register_secret.pyは指定チームのBot認証情報を確認してこのリポジトリのSecretへ登録するCLI hook。別の場所へ認証を登録する場合は対象を確認して許可を得る。
