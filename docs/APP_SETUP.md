> 移植元の操作説明。現在の有効化・検証状況はMIGRATION.mdとSLACK.mdを優先する。

# カンペき スライド連携プロトタイプ

PowerPointが描画した画面をMacアプリ内に表示し、iPhoneに共有します。iPhoneの「次へ・戻る」をMac経由でPowerPointへ送り、保存済みpptxから取得した発表者ノートを同期します。

## 時間配分の検証アプリ（SlidePacer）

`Kanpeki.xcworkspace` を開くと、既存の `KanpekiMac` / `KanpekiPhone` と、時間配分検証用の `SlidePacer` を同じXcodeで閲覧・編集できます。検証アプリを起動する場合は `SlidePacer` → `My Mac` を選びます（最低macOS設定26.5）。

[検証アプリの説明](experiments/SlidePacer/README.md) · [セットアップ](experiments/SlidePacer/docs/TEAM_SETUP.md) · [全員にモデルをダウンロードさせない運用](experiments/SlidePacer/docs/LLM_SHARING.md)

モデルなしでも画面の確認・編集と回帰テストができます。LLM分析を実行する場合だけ、自分のOllamaまたはチームの推論サーバーへの接続が必要です。既存アプリへの画面・通信接続は今後の作業です。

### 別の場所からLLM分析を使う

Qwenを動かすホストMacを1台用意し、メンバーのアプリは **Tailscale経由でそのMacへ接続**します。モデルの取得はホストだけです。メンバーはTailscaleに接続し、アプリのBase URLへホストが伝えたHTTPS URLを設定します。ホストではOllamaに加え、同梱のPython転送処理を起動します（共有ホスト名による403を防ぐため）。[ホスト・メンバーの接続手順と停止方法](experiments/SlidePacer/docs/LLM_SHARING.md)

ホストが起動・接続している間だけ利用できます。分析中はホストのCPU/GPUを使うため、最初は推論を1件ずつ処理する設定で運用します。同時処理制限でも分析自体の負荷は残り、混雑時は待ち時間が増えます。資料本文・ノートはホストへ送信されます。

Tailscaleは学校・会社のアカウントで既存の組織ネットワークへ入らず、個人アカウントでチーム専用ネットワークを用意します。ログイン・VPN許可・メンバーのアクセス設定は各自で行います。ホスト自身から共有HTTPS URLを通じたQwen応答は確認済みです。別端末からの接続と複数人利用は未検証です。

## 自動配布

[GitHub Actions → TestFlightの設定・運用](docs/CD.md)。mainへの統合後に検証と配布を実行します。Apple側の認証・署名・外部テスター設定が必要です。

## チーム開発

[開発ルール](docs/TEAM.md) · [Codexとskills](docs/CODEX.md) · [現在の実装](docs/STATUS.md) · [GitHub作業一覧](https://github.com/MinobeRyo/kanpeki/issues)

共有コードの作業ディレクトリはこのリポジトリです。旧KanpekiPrototypeは配布時のスナップショットです。

## 開くファイル

- `Kanpeki.xcodeproj`：Mac版とiPhone版の2ターゲットを含むXcodeプロジェクト。
- Mac版はXcodeからビルドします。ビルド済みバイナリはGitに含めません。
- `docs/STATUS.md`：実際に検証した項目と未確認の項目。

外部Swiftパッケージ、クラウドサーバー、APIキーは不要です。macOS 14以降、iOS 17以降を対象にしています。Xcode 26.6でビルドしています。

## 使い始める

### Mac

1. PowerPointで、発表者ノートのあるpptxを保存して開きます。
2. PowerPointのスライドショーを1つだけ開始します。最初はウィンドウ表示のスライドショーで検証してください。
3. Xcodeでスキーム`KanpekiMac`、実行先`My Mac`を選んでRunします。
4. 「ウィンドウを探す」を押します。必要に応じ、システム設定の「プライバシーとセキュリティ → 画面収録（画面とシステムオーディオ収録）」でカンペきを許可します。許可後にアプリ再起動が必要になる場合があります。
5. 発表用のスライドウィンドウを選択し、「共有開始」を押します。原稿・デスクトップを誤って共有していないか、Macのプレビューを確認してください。
6. 「pptxの原稿を読み込む」で、PowerPointで開いたものと同じファイルを選びます。
7. 「PowerPoint操作を有効化」を押します。macOSのオートメーション許可が出たらPowerPointとの連携を許可します。失敗した場合は表示される案内に従い、もう一度有効化します。
8. 「接続待機を開始」を押します。

画面取得に失敗しても、アプリが権限設定を自動変更することはありません。最小化、全画面、複数画面、外部ディスプレイでの動作は個別に検証してください。共有中は元のPowerPointも起動したままにします。

### iPhone実機

1. Xcodeで`Kanpeki.xcodeproj`を開きます。
2. `KanpekiPhone`ターゲット → Signing & Capabilitiesで自分のTeamを選びます。Bundle Identifierが重複する場合は自分用の値に変更してください。
3. iPhoneをMacに接続し、必要な信頼確認とDeveloper Modeの設定を済ませます。
4. スキーム`KanpekiPhone`、実行先にiPhoneを選び、Runします。
5. MacとiPhoneのWi-Fiを有効にし、最初は同じWi-Fiで試してください。ローカルネットワーク権限を許可します。
6. iPhoneの「近くのMacを探す」からMacを選びます。
7. Macの確認ダイアログで端末名を確認し、許可します。画面と原稿がiPhoneへ共有され、スライド操作が可能になります。

実機へのインストールにはユーザーの開発用署名が必要です。完成したアプリのApp Store配布・公証はこの試作に含みません。

### 確認する操作

- 次へ・戻るを操作し、MacとiPhoneの実際のページと原稿が一致する。
- PowerPoint側のキーボード操作も両方に反映される。
- 最初・最後のページで範囲外へ移動しない。
- 切断後は操作ボタンが無効になり、再検索で接続できる。
- iPhoneをバックグラウンドに移すと切断する。戻ったら再検索する。
- 「JSONを書き出す」で実際に観測したスライドID・ページ・時刻を保存する。

## 試作の範囲

| 項目 | 実装 |
|---|---|
| Mac内のスライド表示 | ScreenCaptureKitで指定ウィンドウを取得 |
| iPhone内の表示 | 最大5fps、最大180KB/枚のJPEGを転送 |
| 通信 | Multipeer Connectivity。暗号化必須、Mac側で接続許可 |
| フレーム制御 | 受信確認が来るまで次の画像を送らず、古い画像の待ち行列を増やさない |
| スマホの操作 | 次へ・戻る。重複コマンド抑止、短時間の連打制限 |
| PowerPoint連携 | Apple Eventsで操作・実際のスライドIDとページ位置を取得 |
| 原稿 | pptxのZIP/XMLを読み、表示順とノートのrelationshipを辿る |
| 切替ログ | 約800ms間隔の観測。JSON出力 |
| 他のアプリ | 「他のアプリも表示」で画面取得のみ。Keynote/Canvaの操作・原稿取得は未実装 |

ノートは保存済みpptxの取込時点の内容です。PowerPointで編集したら保存して再取込してください。原稿は同じファイルパス・枚数・スライドID・順序が一致する場合だけ表示します。pptxの読み込み後にプレゼン内容を編集せず検証してください。

この版はパスワード保護pptx、カスタムショー、表示中資料の編集、アニメーション段階の厳密な同期を対象外としています。ノート本文のbodyプレースホルダーを読み、ページ番号やヘッダーは除外します。1〜500枚、1枚のノート64KBまでに制限しています。

映像とメタデータは別メッセージで届きます。切替時に短い時間差が生じる可能性があります。画像配信が止まるとiPhoneに警告を表示し、スライド状態が3秒更新されなければ操作を無効にします。60fpsの動画配信、システム音声、リアルタイム翻訳、マイク・カメラ解析は未実装です。

ログ時刻はMacが状態を観測した時刻で、正確な描画時刻・音声との同期済み時刻ではありません。ログはアプリ終了で失われるため、必要な場合はJSONを保存してください。

## 構成と拡張

```text
Shared/
  Models.swift             共通状態・コマンド・画像パケット・ログ
  PeerLink.swift           端末探索・接続許可・転送・受信確認
Mac/
  WindowCapture.swift      指定ウィンドウの取り込み
  PowerPointBridge.swift   PowerPoint固有の操作と状態取得
  PPTXImporter.swift       表示順と発表者ノートの読み取り
  MacModel.swift           同期とセッション記録
  KanpekiMacApp.swift      Macの画面
iOS/
  KanpekiPhoneApp.swift    iPhoneの画面とリモコン
```

`PresentationControlling`を実装するアダプターを追加することで、PowerPoint固有処理から独立した操作経路を作れます。現在のUIはPowerPoint操作を明示的に有効化する仕様です。Keynote/Canvaへ拡張する場合は、対応するアダプターに加え、現在ページ・原稿の取得方法とUIの切替も実装してください。

次段階では、表示スライドID・取込原稿・ログをチーム共通のSession/SlideSpanに変換できます。翻訳やカメラ解析はその共通時刻に紐づけ、映像キャプチャとは別の処理として追加します。

## ビルドとテスト

コマンドラインがCommand Line Toolsを指していても、以下はXcodeを一時指定するので全体設定を変更しません。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Kanpeki.xcodeproj -scheme KanpekiMac \
  -configuration Debug -derivedDataPath /tmp/kanpeki-mac-build build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Kanpeki.xcodeproj -scheme KanpekiPhone \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/kanpeki-phone-build build CODE_SIGNING_ALLOWED=NO

bash Tests/run_tests.sh
```

テストはPython 3（標準ライブラリのみ）とXcode付属Swiftコンパイラーを使います。PRでは署名なしビルドとコアテストをCIで実施します。TestFlightの配布履歴はdocs/STATUS.mdを参照。
