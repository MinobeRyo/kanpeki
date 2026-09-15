# Codex活用を説明する証拠

環境を用意したことと、開発で効果が出たことを区別する。未接続のCDや未実装のAI返信を成果として紹介しない。

## 現時点で示せる具体例

| 具体例 | 根拠 | 説明できる効果 |
|---|---|---|
| ロゴから用途のある少数色を定義 | [PR #2](https://github.com/MinobeRyo/kanpeki/pull/2)、BRAND | チームで同じ色の意味を共有 |
| 対話からボタンを削り直接操作へ修正 | [PR #4](https://github.com/MinobeRyo/kanpeki/pull/4)、SCREEN_FLOW | 誤操作と接続失敗も仕様化 |
| 案内・翻訳・音声・カメラ・結果の抜けを整理 | [PR #6](https://github.com/MinobeRyo/kanpeki/pull/6)、ASSISTANCE_FLOW | 機能間の流れと未決定事項を共有 |
| 画面比率・余白・指の届く位置の検討 | assets/design/device-size | 一覧画像から個別画面へ具体化。実機の操作性は未検証 |
| 準備用GitHub Actions | docs/HANDOFF.mdの実行リンク | 自動実行経路の一部を確認。アプリCI/CDではない |

上表は事前の設計成果。後続の実装・テスト・レビューは下記の実記録を入口にする。効果の数値を推測しない。

## 当日の実装・検証の入口

- [PR #51](https://github.com/MinobeRyo/kanpeki/pull/51)：発表とカメラのUUID関連付け、前回結果混入防止。
- [PR #54](https://github.com/MinobeRyo/kanpeki/pull/54)：画像identityと古い操作の拒否。
- [PR #60](https://github.com/MinobeRyo/kanpeki/pull/60)：録音の許可待ち・旧callback・不正結果の検証、明示的な発表音声入口。
- [Issue #28の配布成功](https://github.com/MinobeRyo/kanpeki/issues/28#issuecomment-5674062963)：署名失敗の修正から両内部TestFlightへの配布。全員の利用確認とは別。
- 個別テスト・実機未検証・未マージは[STATUS](STATUS.md)で分離する。これらを全コードの当日新規開発と表現しない。

## 当日の記録テンプレート

各担当は担当Issue／PRへ次を短く残す。同じ共有ファイルへの同時追記を避ける。

- 問題：何が必要だったか、または何が失敗したか。
- Codexへの依頼：目的と制約。秘密を含むチャット全文は貼らない。
- 変更：PRとコミット、実際に変わった挙動。
- 検証：環境・操作・結果。実機、シミュレーター、静的確認を区別。
- 人間の判断：採用・修正・見送りと理由。
- 効果：実測できた値だけ。時間短縮率や成功率を推測で作らない。

## CI/CD完成後に示す例

「Codexの変更 → PRの確認 → マージ → 同一コミットのテスト → TestFlightで同じビルドを人間が確認」を1本の証拠でつなぐ。ActionsのURL、コミット、アプリ版・ビルド番号、配布状態、人間の実機確認を揃える。アップロード・審査中・テスター配布可能は別の状態として扱う。
