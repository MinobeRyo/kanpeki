# 接続承認の安全性（Issue #19の部分実装）

MultipeerConnectivityの暗号化・Macの明示承認・操作用iPhone1台の構成を維持する。この承認実装はMultipeer経路を補強する。後続QR直接TLS経路は[QR_CONNECTION](QR_CONNECTION.md)で別記する。

- 招待時から承認完了・接続完了まで同じ1台を予約し、2台目の招待は拒否する。既存接続を自動置換しない。
- 各招待にUUIDを割り当てる。Mac確認ダイアログは表示対象のUUIDを保持し、古い許可/拒否や21秒の期限切れ処理で次の招待を操作しない。
- 招待/再試行ごとにMCSessionを生成し、旧sessionはdelegate解除・切断する。delegate→mainの待機中に現在相手の切断を観測した場合は、その前のdata/ACKを無効化する。旧sessionや別peerは現在の世代を無効化できない。
- 原稿/状態/画像の送信先は承認・接続済みのpeer1台のみ。受信も同じ相手・sessionのみ許可する。接続直後に画像がconnected callbackより先着した場合は、承認済み相手にACKだけ返して表示はせず、次の画像更新を待つ。未承認相手へはACKも返さない。
- 画像identity、未ACK画像1枚、破棄画像のACKは#20の規則を維持する。停止・ブラウザ/広告再開始後の旧delegateも無効化する。

これは端末名を本人確認の証明にするものではない。人間は自分のiPhoneで接続操作したことを確認して承認する。このPRの対象外だったQRは後続PR #71で直接TLS接続を追加した（[QR_CONNECTION](QR_CONNECTION.md)）。WebSocket移行・実機到達性確認は別で、#19の全受入完了とは扱わない。

自動検証は純粋承認状態/操作UUID/callback世代の合成テストとMac/iPhoneビルド。実機でA承認待ち中のB接続、同peer再試行、接続直後の画像、切断中の操作、Mac alertのEsc・画面閉鎖、ローカルネットワーク許可を確認する必要がある。21秒は招待APIの20秒期限に合わせた解放用で、通信時間や実機接続成功を保証しない。
