# PowerPoint連携の実装と検証範囲

Issue #21。Macの `PowerPointBridge` はPowerPointの現在のスライドショーを読み、ページindex・元slide ID・元ファイルpathを返す。PPTXノートは引き続きMacModelで元path、枚数、index、slide IDを照合する。表示の再実装・Windows COM・別アプリ対応は追加しない。

## 今回の補強

- 起動確認とAppleScript実行を注入可能にして、PowerPointを動かさず合成AppleEvent応答をテストできるようにした。
- 応答は5項目のlist、文字列の資料名/path、整数のindex/ID/枚数を要求する。文字列やboolからの暗黙変換・欠落・不正範囲を受け入れない。
- 未起動時は自動起動せず案内する。オートメーション拒否、接続断、応答タイムアウトは回復操作付きの日本語エラーにする。エラー後は既存MacModelの操作停止と両端末への状態表示を使う。
- 送り戻りは同じAppleScript内で現在のshow、ページ、範囲を再確認する。次方向に表示対象のスライドがなければ移動命令を送らない。末尾の非表示スライドと範囲指定を考慮し、先頭へのループや末尾からのショー終了を避ける。
- showがゼロなら終了/未開始、複数なら対象が曖昧として拒否。目的別ショーは独自順序の未対応を明示し、PowerPoint側での操作を案内する。

## 根拠と検証

ローカルにインストールされたPowerPoint 16.112.4の公式スクリプト辞書 `PowerPoint.sdef` を読み取り、`slide show window` / `slideshow view` / `slide index` / `slide ID` / `range type` / `starting slide` / `ending slide` / `hidden` / next / previous の用語を照合した。辞書の読み取りはアプリ実行・ショー操作・権限許可の代わりではない。

`bash scripts/check.sh core` は合成応答の解析、依存注入による未起動/失敗経路、生成するスクリプトの安全条件の存在を検証する。スクリプト条件検査はPowerPoint上での動作保証ではない。`bash scripts/check.sh mac` でMacアプリの未署名ビルドを検証する。

## 実機・PowerPoint側で残る受け入れ確認

1. 対象PowerPoint版で、通常showの現在ページと日本語/空白入り保存path・元slide IDを確認する。
2. 1枚だけ、通常の先頭/末尾、末尾非表示、範囲指定、ループ設定で送り戻りがショーを勝手に終了・ループしないか確認する。手動PowerPoint操作と同時に動かす競合は未検証。
3. Presenter Viewと観客向け出力の別画面、複数資料/複数showで原稿や管理画面を誤投影しないか確認する。現状はshow数1を要求し、任意のPresenter Viewを正しく選択できる保証はしない。
4. 権限拒否→許可後の明示再接続、PowerPoint終了、ショー終了、ダイアログでの応答遅延を確認する。権限は自動変更しない。

goto・サムネイル専用取得は本PRの対象外。現在のプレビューは既存の画面取得から表示するもので、全スライドのサムネイルAPIではない。Issue #21全体・対象版の実機検証・TestFlight配布を完了とは扱わない。
