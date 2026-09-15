# GitHub Actions → TestFlight 自動配布

## 仕組み

PR → 任意レビューと必須CI成功 → mainへマージ → TestFlight CD → core/Mac/iPhone検証と署名なしRelease archive → 一時キーチェーンへ配布証明書を取込 → 署名付きarchive/IPA → App Store Connectアップロード → Appleの処理待ち → 外部グループへ追加・ベータ審査提出 → Apple承認後に通知・インストール。

一般公開のApp Storeへの提出や公開は行わない。対象はiPhone/iPad版のみ。Mac版のビルドはCIに含むが、MacのApp Store配布/公証は別工程。

## 現状

iPhoneの署名・TestFlight外部配布とSlack通知は設定済みで、[CDの成功実績](https://github.com/MinobeRyo/kanpeki/actions/runs/34769175088)があります。テスターは https://testflight.apple.com/join/a8W7TAaE から参加できます。Apple審査や処理状況はビルドごとに異なるため、マージ成功と配布成功は別に確認してください。Macは独立したDeveloper ID署名・公証・GitHub Release配布です。設定と導入手順は[MAC_INSTALL.md](MAC_INSTALL.md)、現在の配布作業は[Issue #17](https://github.com/MinobeRyo/kanpeki/issues/17)を参照してください。

## 初回のみ必要な設定

1. Account HolderがApp Store Connect → ユーザとアクセス → 統合でAPI利用権を申請。契約に同意する場合は内容を確認する。
2. `Kanpeki GitHub CD` など識別可能な名前でAPIキーを用意。テスターへの配布まで行うにはApp Manager相当が必要。Team APIキーは同一チームの他アプリにも権限が及ぶため、その範囲を理解して発行する。キーは一度しかダウンロードできない。
3. Apple Distribution証明書と対応する秘密鍵をパスワード付きP12で用意。開発用Apple Development証明書では不可。既存証明書を勝手に失効させない。クラウド管理証明書の秘密鍵はこのMacからエクスポートできないので、CI用の証明書が必要。
4. `XYJX89KRDM` / `jp.kanpeki.prototype.phone` 用のApp Store Connect配布プロファイルを用意。3の証明書を含める。Ad HocやDevelopment用は不可。
5. GitHub repository → Settings → Environments → `testflight` に以下を登録。

| Environment secret | 内容 |
|---|---|
| ASC_KEY_ID | AppleのKey ID |
| ASC_ISSUER_ID | AppleのIssuer ID |
| ASC_KEY_P8_BASE64 | .p8秘密鍵のBase64 |
| IOS_DISTRIBUTION_P12_BASE64 | 証明書＋秘密鍵P12のBase64 |
| IOS_DISTRIBUTION_P12_PASSWORD | P12のパスワード |
| IOS_APPSTORE_PROFILE_BASE64 | 配布プロファイルのBase64 |

Environment variable `TESTFLIGHT_EXTERNAL_GROUP` はチーム外部テスターグループの正確な名前またはID。
秘密値はチャット・Issue・PR・コミットに記載しない。`gh secret set NAME --env testflight --repo MinobeRyo/kanpeki` の標準入力で設定できる。Base64は暗号化ではないので、GitHub Secrets以外へ公開しない。

6. App Store Connectで外部グループを作り、チーム4人の招待先メールを登録。GitHubの招待とAppleの招待は別。2026-09-14、Slackからアプリを確認するユーザー依頼により公開参加リンクを有効化（リンク参加枠10人）。
7. TestFlightのテスト情報に、説明、フィードバック先、審査担当への連絡先（氏名/メール/電話）、Mac companionの入手方法と具体的な検証手順を登録する。非公開GitHubリンクだけではAppleの審査担当はアクセスできない。審査でアクセスできる配布方法を本人が確認して用意する。未入力のまま外部配布は完了しない。
8. PRをレビュー/マージ。`TestFlight CD` がmainのpushで起動する。ActionsのRun workflowでもmainだけ実行可。

GitHub Environmentはmain限定にする。Environment承認ゲートは設けず、ユーザーのマージ依頼と必須CIを確認して統合する。レビュー必須は0件。保護設定を勝手に変更しない。

## 実行と結果

- 配布は同時実行しない。実行中のリリースは中断しない。GitHubのconcurrencyは全pushのFIFOを保証せず、待機分が新しい実行に置き換わる場合がある。最新mainを配布する運用。
- 配布直前にmainのSHAと対象SHAを比較し、古いmainの実行は停止する。
- ビルド番号は `GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT.0`。再実行で番号が変わり、同一workflow内で衝突しない。run_numberが9999を超える前に戦略を更新する。手動配布はこの番号帯を使わない。
- Appleの処理待ちは30分、配布jobは60分でタイムアウト。アップロード後にタイムアウトした場合、まずTestFlightでその番号を確認する。無条件の再実行は別ビルドを作る。
- fastlane成功は外部配布申請の成功を示す。初回審査中/審査拒否は別途TestFlightで確認する。「全員が見れる」の完了条件は、グループの全員の登録・ビルド承認・招待受諾まで。
- Secretsは配布jobのみ。一時ファイル/証明書はalways cleanupで削除し、IPAやarchiveや生の配布ログをActions artifactへアップロードしない。GitHubホスト型runner専用。
- プロファイルの期限切れや証明書の更新時は、同じEnvironment secretを交換してから再実行。Key/P12をリポジトリへ置かない。

## 参考

[GitHubの署名付きXcodeビルド](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
[AppleのAPI利用開始](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
[fastlaneのTestFlight配布](https://docs.fastlane.tools/actions/pilot/)
