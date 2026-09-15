# 音声取得・解析モジュール

## 今回の移植範囲

ユーザーの指示により、別リポジトリに作成した音声初版を `experiments/AudioCapture/` に移した。
移植元: `mao-sonobe/kanpeki-audio`、コミット `12f4a30d02d951e491232fbde53d2b5487f99000`。
ソース・実テスト・Xcodeプロジェクト・手順を取り込み、Git履歴・モデル・録音・秘密情報は含めていない。
アイコン/ロゴは本体の `assets/brand/app-icon.png` に合わせた。

本体の `KanpekiPhone` / `KanpekiMac` に組み込まれた機能ではなく、音声担当が単体検証できる入口。
PythonのMacサーバーとSwiftUIのiPhone検証アプリを含む。主製品のMacネイティブアプリの代わりにしない。
本体の `Shared/Models.swift`、既存iPhone UI、結果画面、署名・配布設定は変更していない。

## 試す

本体リポジトリから `cd experiments/AudioCapture` し、[README](../experiments/AudioCapture/README.md) の順に起動する。
Xcodeで開くのは `experiments/AudioCapture/ios/KanpekiAudio.xcodeproj`。
単体検証用Bundle IDは `dev.kanpeki.audio`。本体のTestFlightとは別アプリで、配布設定は未接続。

音声は16kHz mono PCM16 WAVを録音終了後に一括送信する。Mac内のwhisper.cppで文字起こしし、話速・フィラー候補・低音量区間を返す。モデル未設定/失敗は未計測として扱う。詳細は [API契約](../experiments/AudioCapture/docs/INTEGRATION.md)。

## 残作業の受け取り方

[Issue #12](https://github.com/MinobeRyo/kanpeki/issues/12) が音声全体の入口。本文の完了条件と直近コメント、関連する未担当Issueを確認する。
手が空いた人は、未担当・未着手の項目を選び、着手コメントと自分への担当設定を行ってから専用branch/worktreeで始める。担当済みの作業は既存担当と調整する。

引き取り可能な残件の入口（担当の最新状態は各Issueで確認）：

- [#38 本体の発表セッションへの組み込み](https://github.com/MinobeRyo/kanpeki/issues/38)
- [#39 実iPhone・実会場での検証](https://github.com/MinobeRyo/kanpeki/issues/39)
- [#40 VADと日本語フィラー候補の改善](https://github.com/MinobeRyo/kanpeki/issues/40)
- [#41 連続送信と発表中通知](https://github.com/MinobeRyo/kanpeki/issues/41)

関連する本体作業：

- #10：iPhone画面。音声のON/OFF・権限・録音状態を既存画面へ組み込む。
- #13：結果画面。`AudioReport` を渡し、未計測と0件を区別する。
- #17 #20：タイムラインとスライド切替。録音の時刻基準へ変換する。
- #19 #22：接続とMac Bridge。接続先/認証・受信経路を本体へ統合する。
- #18：通知。連続分析と通知条件を検証してからつなぐ。

これらの担当や完了状態は固定表に複製せず、最新Issueを正本にする。

## 移植先の検証

2026-09-15、移植先の専用worktreeで以下を確認した。

- バックエンド18件成功（音量・時刻・未計測・実HTTP・認証・再送・削除）。
- 本体 `bash scripts/check.sh core` 成功（チーム管理4テスト、Swiftコア17チェック）。
- 単体音声アプリのiPhone Simulator向け署名なしビルド成功。
- 同じ `AudioAPI.swift` の実通信クライアントから、日本語合成音声17.712秒を送信→Macでwhisper.cpp実分析→Swiftで結果取得まで成功。

実行コマンド：

```sh
cd experiments/AudioCapture
PYTHONPATH=backend python3 -m unittest discover -s backend/tests -v
xcodebuild -project ios/KanpekiAudio.xcodeproj -scheme KanpekiAudio \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

本体の音声CIは `.github/workflows/audio.yml`。移植前の結果は [初版の検証記録](../experiments/AudioCapture/docs/VALIDATION.md) で区別する。
実iPhoneの録音・LAN接続・会場音声の精度は未検証。VAD、リアルタイム分析/通知、本体セッションの接続は未実装。
