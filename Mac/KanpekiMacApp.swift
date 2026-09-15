import SwiftUI
import KanpekiCamera
import KanpekiAudioHost

@main struct KanpekiMacApp: App {
    @StateObject private var model = MacModel()
    @StateObject private var audio = AudioHostModel()
    @State private var showScreenReview = false
    @AppStorage("macNotesSize") private var notesSize = 0
    @FocusedValue(\.preparationActions) private var actions
    var body: some Scene {
        WindowGroup("カンペき · Mac") {
            MacScreen(model: model, capture: model.capture, link: model.link, audio: audio, showScreenReview: $showScreenReview)
        }.defaultSize(width: 1200, height: 800)
            .commands {
                CommandMenu("準備") {
                    Button("ホーム") { actions?.home() }
                    Button("共有画面を選ぶ…") { actions?.window() }
                    Button("接続方法を変更…") { actions?.connection() }
                    Button("QRでつなぐ") { actions?.qr() }
                    Button("時間を調整…") { actions?.time() }
                    Divider()
                    Button("音声分析") { actions?.audio() }
                    Button("ChatGPTで振り返る") { actions?.practice() }
                    Button("カメラの設定・結果") { actions?.camera() }
                    Button("接続の詳細") { actions?.details() }
                }

                CommandMenu("発表") {
                    Button("一時停止・再開") { actions?.pause() }
                    Button("発表を終了") { actions?.end() }
                }
                CommandGroup(after: .newItem) {
                    Button("資料を選ぶ…") { model.importDeck() }
                    Button("切替記録をJSONで書き出す") { model.exportLog() }.disabled(model.events.isEmpty)
                    Button("新規記録") { model.resetLog() }
                }
                CommandGroup(after: .toolbar) {
                    Button("画面構成の見本") { showScreenReview = true }
                    Button("原稿を大きく") { notesSize = min(2, max(0, notesSize) + 1) }.keyboardShortcut("+")
                    Button("原稿を小さく") { notesSize = max(0, min(2, notesSize) - 1) }.keyboardShortcut("-")
                }
            }
    }
}

struct MacScreen: View {
    @ObservedObject var model: MacModel
    @ObservedObject var capture: WindowCapture
    @ObservedObject var link: PeerLink
    @ObservedObject var audio: AudioHostModel
    @State private var navigation = MacNavigation()
    @State private var showDocument = false
    @Binding var showScreenReview: Bool
    @AppStorage("macNotesSize") private var notesSize = 0
    @State private var showDetails = false
    @State private var showPractice = false
    @State private var showRecordedResults = false
    @State private var showPreparationAI = false
    @State private var notesAfterPreparation = false
    @State private var showPreparationNotes = false
    @State private var macOnly = false
    @State private var screenOnly = false
    @State private var endingSession: UUID?
    @State private var adjustment: MacTimeDraft?
    @State private var windowDraft: MacPreparationDraft?
    @State private var connectionDraft: MacPreparationDraft?
    @State private var showQR = false
    @StateObject private var camera = CameraController()
    @State private var presentationResult = PresentationResultAssociation()
    @State private var showCamera = false
    private let ink = BrandColor.ink, paper = BrandColor.paper, mint = BrandColor.mint
    private var presenting: Bool { model.state.timer?.phase == .running || model.state.timer?.phase == .paused }
    private var busy: Bool { model.importing || model.openingDocument || model.presentationStarting || model.timerFinishing }
    private var step: MacSetupStep {
        .next(document: model.deck != nil, screenOnly: screenOnly, opened: model.powerPointOpened,
              window: capture.windows.contains { $0.id == model.selectedWindowID },
              connected: link.connectedName != nil, macOnly: macOnly, time: model.state.timer?.durationSeconds != nil)
    }
    private var showingDocumentPreview: Bool {
        model.deck != nil && !capture.sharing && !presenting && model.state.timer?.phase == .ready
    }
    private var startReason: String? {
        model.presentationStartReason ?? (link.connectedName == nil && !macOnly ? "iPhoneを接続してください。" : nil)
    }

    private var mainContent: some View {
        Group {
            if navigation.current == .audio {
                AudioHostPanel(model: audio, onBack: { navigation.back() })
            } else {
                VStack(spacing: 22) {
            HStack(spacing: 12) {
                if navigation.current != .home {
                    Button("戻る", systemImage: "chevron.left") { navigation.back() }
                }
                Image("BrandMascot").resizable().scaledToFit().frame(width: 36, height: 36)
                Text("カンペき").font(.title2.bold())
                Spacer()
                if presenting || model.state.timer?.phase == .ended {
                    PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                }
                Label(link.connectedName ?? (macOnly ? "Macだけで練習" : "iPhone未接続"), systemImage: "iphone").font(.callout)
                if navigation.current == .presentation && model.state.timer?.phase != .ended && !(presenting && capture.sharing && model.state.frameReady == true) {
                    options
                }
            }
            if navigation.current == .home {
                home
            } else if navigation.current == .connection {
                connection
            } else if navigation.current == .practice {
                RehearsalFlow(model: model, audio: audio, link: link, connect: { showQR = true },
                    feedback: { showPractice = true }, audioDetails: { navigation.open(.audio) })
            } else if navigation.current == .analysis {
                analysis
            } else if model.deck == nil && !screenOnly && !presenting && model.state.timer?.phase != .ended {
                Spacer()
                Image("BrandMascot").resizable().scaledToFit().frame(width: 112, height: 112)
                Text("発表する資料を選びましょう").font(.largeTitle.bold())
                Text("PowerPointの資料を、そのまま確認できます。")
                Button(model.importing ? "読み込み中…" : "PPTXを選ぶ") { model.importDeck() }
                    .buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(model.deck?.title ?? model.state.title).font(.headline).lineLimit(1)
                            Spacer()
                            if let index = model.state.slideIndex, capture.sharing {
                                Text("\(index) / \(model.state.totalSlides)").monospacedDigit()
                            } else if let deck = model.deck { Text("\(deck.slides.count)枚").foregroundStyle(.secondary) }
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(paper)
                            if let image = capture.image, capture.sharing {
                                Image(nsImage: image).resizable().scaledToFit()
                            } else if presenting || capture.sharing {
                                Label("発表画面の更新を待っています", systemImage: "arrow.triangle.2.circlepath")
                            } else if model.state.timer?.phase == .ended {
                                Label("発表を終了しました", systemImage:"checkmark.circle").font(.title2)
                            } else if let deck = model.deck {
                                DocumentThumbnail(url: deck.url).id(model.documentRevision).padding(12)
                            } else { Label("共有する画面を選びましょう", systemImage: "rectangle.on.rectangle") }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        if showingDocumentPreview {
                            Text("資料の表紙 · 全ページは「準備・機能」→「資料を大きく見る」").font(.caption).foregroundStyle(.secondary)
                        }
                        if presenting && capture.sharing && model.state.frameReady == true {
                            HStack {
                                Button { model.move(.previous) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 30) }
                                    .accessibilityLabel("前のスライド").disabled(!model.state.canMoveSlide(.previous))
                                Button { model.move(.next) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 30) }
                                    .accessibilityLabel("次のスライド").disabled(!model.state.canMoveSlide(.next))
                                Spacer()
                                Text("← → キーでも操作できます").font(.caption).foregroundStyle(.secondary)
                            }
                            if !model.state.notes.isEmpty {
                                ScrollView {
                                    Text(model.state.notes).font(.system(size: [18.0,22.0,26.0][min(2,max(0,notesSize))]))
                                        .lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                }.frame(height: 140).padding(20).background(paper,in:RoundedRectangle(cornerRadius:20))
                            }
                        }
                    }
                    if !presenting || !capture.sharing || model.state.frameReady != true {
                        nextAction.frame(width: 300)
                    }
                }
            }
                }.padding(28)
            }
        }.frame(minWidth: 860, minHeight: 620)
            .background(mint).foregroundStyle(ink).tint(ink).preferredColorScheme(.light)
            .background { if navigation.current == .presentation { MacSlideKeyboard(model: model, onNarrowWindow: {}).frame(width: 0, height: 0) } }
    }

    private var routedContent: some View {
        mainContent
            .task { await capture.refreshWindows(); if !link.running { link.start() }; syncAudioConnection() }
            .onChange(of: audio.receiving) { _, _ in syncAudioConnection() }
            .onChange(of: audio.addresses) { _, _ in syncAudioConnection() }
            .onChange(of: navigation.current) { previous, current in
                if previous == .presentation && current != .presentation && model.presentationStarting { model.cancelPresentationStart() }
            }
            .onChange(of: model.documentRevision) { _, _ in screenOnly = false }
            .focusedSceneValue(\.preparationActions, MacPreparationActions(
                window: { navigation.open(.presentation); selectWindow() },
                connection: { if !busy { connectionDraft = preparationDraft() } },
                time: { if !busy, model.state.timer?.phase == .ready, let snapshot = model.state.timer { adjustment = MacTimeDraft(snapshot:snapshot) } },
                camera: { showCamera = true }, details: { showDetails = true }, qr: { showQR = true },
                audio: { navigation.open(.audio) }, practice: { showPractice = true }, home: { navigation.home() },
                pause: { if presenting { model.timerAction(model.state.timer?.phase == .running ? .pause : .resume, duration: nil) } },
                end: { if presenting { endingSession = model.state.timer?.sessionID } }))
            .sheet(isPresented: $showDocument) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("戻る", systemImage: "chevron.left") { showDocument = false }
                    if let deck = model.deck { DocumentPreview(url: deck.url).id(model.documentRevision) }
                }.padding(20).frame(width: 800, height: 580)
            }
            .sheet(isPresented: $showPractice) { practiceSheet }
            .sheet(isPresented: $showRecordedResults) {
                VStack(alignment: .leading, spacing: 20) {
                    Button("戻る") { showRecordedResults = false }
                    PresentationResultsButton(association: presentationResult, camera: camera)
                    if presentationResult.elapsedSeconds == nil { Text("練習・発表の終了後に表示します") }
                }.padding(24).frame(minWidth: 480, minHeight: 180)
            }
            .sheet(isPresented: $showPreparationNotes) {
                VStack(alignment: .leading, spacing: 20) {
                    Button("戻る") { showPreparationNotes = false }
                    PreparationNotesView(model: model)
                }.padding(24).frame(minWidth: 480, minHeight: 180)
            }
            .sheet(isPresented: $showPreparationAI, onDismiss: {
                if notesAfterPreparation { notesAfterPreparation = false; showPreparationNotes = true }
            }) {
                VStack {
                    HStack {
                        Button("戻る") { showPreparationAI = false }
                        Spacer()
                        Button("原稿案を確認・採用") { notesAfterPreparation = true; showPreparationAI = false }
                    }.padding()
                    ContentView(sharedFolder: model.preparationFolder)
                }.frame(width: 1000, height: 740)
            }
            .sheet(isPresented: $showQR) { QRPairingSheet(link: link) }
            .sheet(isPresented: $showScreenReview) { ScreenReview() }
            .sheet(isPresented: $showCamera) {
                VStack {
                    HStack { Spacer(); Button("発表画面に戻る") { showCamera = false } }.padding()
                    CameraPanel(controller: camera, onContinueWithoutAnalysis: { showCamera = false })
                }.frame(width: 560, height: 650)
            }
            .sheet(isPresented: $showDetails) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("接続の詳細").font(.title2.bold())
                    Text(link.status); Text(model.state.message); Text(capture.message)
                    Text("切替記録：\(model.events.count)件")
                    Button("閉じる") { showDetails = false }
                }.padding(24).frame(width: 520)
            }
    }

    private var observedContent: some View {
        routedContent
            .onChange(of: camera.result) { _, _ in shareCameraEvidence() }
            .onChange(of: model.state.timer) { _, _ in shareCameraEvidence() }
            .onDisappear { camera.stop(); model.cancelPresentationStart() }
            .modifier(PresentationResultsObserver(snapshot: model.state.timer, connected: true,
                camera: camera, association: $presentationResult))
            .onChange(of: model.state.timer?.phase) { _, phase in
                if phase == .ended { camera.stop() }
            }
            .sheet(item: $adjustment) { draft in
                TimeAdjustmentFlow(initialSeconds: draft.snapshot.durationSeconds,
                    canApply: { canAdjust(draft) }, apply: { seconds in
                        guard canAdjust(draft) else { return false }
                        model.timerAction(.configure, duration: seconds)
                        return true
                    })
            }
            .sheet(item: $windowDraft) { draft in
                MacWindowSelectionFlow(windows: capture.windows, currentID: model.selectedWindowID,
                    restoring: draft.timer.phase == .running || draft.timer.phase == .paused,
                    canApply: { canPrepare(draft) }, apply: { id in
                        guard canPrepare(draft), capture.windows.contains(where: { $0.id == id }) else { return false }
                        model.selectedWindowID = id
                        if draft.timer.phase == .running || draft.timer.phase == .paused {
                            Task {
                                await model.recoverSharing(macOnly: macOnly, expectedTimer: draft.timer,
                                    expectedConnectionID: draft.connectionID)
                            }
                        }
                        return true
                    })
            }
            .sheet(item: $connectionDraft) { draft in
                MacConnectionSetupFlow(initialMacOnly: macOnly, canApply: { canPrepare(draft) }, apply: { choice in
                    guard canPrepare(draft) else { return false }
                    macOnly = choice
                    if !choice { link.start() }
                    return true
                })
            }
    }

    var body: some View {
        observedContent
            .confirmationDialog("発表を終了しますか？", isPresented: Binding(get: { endingSession != nil }, set: { if !$0 { endingSession = nil } }), titleVisibility: .visible) {
                Button("発表を終了", role: .destructive) {
                    if let id = endingSession, model.state.timer?.sessionID == id { model.timerAction(.end, duration: nil) }
                    endingSession = nil
                }
                Button("続ける", role: .cancel) { endingSession = nil }
            }
            .alert("iPhoneからの接続", isPresented: Binding(get: { link.invitation != nil && !showQR }, set: { _ in }), presenting: link.invitation) { invitation in
                Button("許可") { link.respondToInvitation(accept: true, invitationID: invitation.id) }
                Button("拒否", role: .cancel) { link.respondToInvitation(accept: false, invitationID: invitation.id) }
            } message: { invitation in Text("\(invitation.name) に共有画面と原稿を送ります。自分の端末から接続を操作したか確認してください。") }
            .alert("確認が必要です", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                if capture.needsScreenPermission { Button("システム設定を開く") { capture.openScreenPermissionSettings() } }
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private func syncAudioConnection() {
        model.updateAudioConnection(address: audio.receiving ? audio.addresses.first : nil, token: audio.code)
    }

    private var home: some View {
        VStack(spacing: 30) {
            Spacer()
            Image("BrandMascot").resizable().scaledToFit().frame(width: 90, height: 90)
            Text("今日は、何から始めますか？").font(.largeTitle.bold())
            HStack(alignment: .top, spacing: 18) {
                homeCard(presenting ? "発表に戻る" : "発表準備", icon: "rectangle.on.rectangle",
                    detail: model.deck?.title ?? "資料を選んで、発表を始める", destination: .presentation)
                homeCard("練習する", icon: "mic", detail: "録音 → 音声分析 → AIの改善提案", destination: .practice)
                homeCard("分析・結果", icon: "waveform", detail: audio.receiving ? "録音の受信中・結果を確認" : "録音・カメラ・AIの振り返り", destination: .analysis)
            }
            Text("練習は資料なしでも始められます。iPhoneの声をMacで分析します。").font(.callout)
            Spacer()
        }
    }

    private func homeCard(_ title: String, icon: String, detail: String, destination: MacDestination) -> some View {
        Button { navigation.open(destination) } label: {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon).font(.system(size: 30))
                Text(title).font(.title2.bold())
                Text(detail).font(.callout).lineLimit(3).frame(minHeight: 52, alignment: .topLeading)
                Image(systemName: "arrow.right")
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(paper, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Label("iPhone接続", systemImage: "iphone").font(.largeTitle.bold())
            Text(link.connectedName.map { "\($0) とスライド操作を接続済み" } ?? "同じWi-Fiで、スライドとリモコンをつなぎます。")
            Text(link.status).font(.callout)
            if link.connectedName != nil {
                Button("発表準備へ") { navigation.open(.presentation) }.buttonStyle(BrandPrimaryButtonStyle())
            } else {
                Button("接続用QRを表示") { showQR = true }.buttonStyle(BrandPrimaryButtonStyle())
            }
            Text("音声を送る場合は、音声分析に表示されるURL・コードで別に接続します。").font(.callout)
            Menu("音声送信・接続の設定") {
                Button("音声分析のURL・コードを表示") { navigation.open(.audio) }
                Button("近くのiPhoneからの接続を待つ") { link.start() }
                Button("接続の詳細") { showDetails = true }
                Button("Macだけで練習する設定") { connectionDraft = preparationDraft() }
            }.fixedSize()
            Spacer()
        }.padding(32).frame(maxWidth: .infinity, alignment: .leading).background(paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private var analysis: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Label("分析・結果", systemImage: "chart.bar").font(.largeTitle.bold())
            Text("音声分析では、iPhoneの録音を受け取り、話速・フィラー候補・低音量区間を確認できます。")
            Text(audio.receiving ? audio.status : "資料やスライド接続がなくても、録音の分析を試せます。").font(.callout)
            Button("音声分析を開く") { navigation.open(.audio) }.buttonStyle(BrandPrimaryButtonStyle())
            Menu("カメラ・AI振り返り・その他") {
                Button("カメラの設定・結果") { showCamera = true }
                Button("時間・カメラの結果") { showRecordedResults = true }
                Button("ChatGPTで発表を振り返る") { showPractice = true }
                Button("資料をAIで整理する") { if model.preparationFolder == nil { model.startMCP() }; showPreparationAI = true }
                Button("練習する") { navigation.open(.practice) }
                Button("切替記録をJSONで書き出す") { model.exportLog() }.disabled(model.events.isEmpty)
                Button("画面構成の見本") { showScreenReview = true }
            }.fixedSize()
            Text("AI振り返りは発表後に依頼します。結果がない項目は未計測として扱います。").font(.caption)
            Spacer()
        }.padding(32).frame(maxWidth: .infinity, alignment: .leading).background(paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func shareCameraEvidence() {
        let cameraID = presentationResult.sessionID == model.state.timer?.sessionID ? presentationResult.cameraID : nil
        let facts = CameraAnalysisEvidence.facts(camera: camera, prefix: "macCamera", associatedCameraID: cameraID)
        model.updateCameraAnalysis(facts, presentationID: facts.isEmpty ? nil : model.state.timer?.sessionID)
    }


    private var practiceSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("ChatGPTで振り返る").font(.title2.bold())
                Spacer()
                Menu("共有の設定") {
                    Button("分析データの共有を開始") { model.startMCP() }
                    Button("共有を停止") { model.stopMCP() }.disabled(model.state.analysisSharingID == nil)
                    Link("ChatGPTを開く", destination: URL(string: "https://chatgpt.com/")!)
                }
            }
            Text(model.mcpStatus).font(.callout)
            Text("共有には資料・音声認識結果・カメラ集計値が含まれます。").font(.caption)
            Text("音声: \(model.sharedAudioAvailable ? "取得済み" : "未共有") · カメラ: \(model.sharedCameraAvailable ? "取得済み" : "未共有")").font(.caption)
            Button(model.state.analysisSharingID == nil ? "ChatGPTとの共有を設定" : "AIへの依頼文をコピーしてChatGPTを開く") {
                if model.state.analysisSharingID == nil { model.startMCP() }
                else {
                    model.requestPracticeAnalysis()
                    NSWorkspace.shared.open(URL(string: "https://chatgpt.com/")!)
                }
            }.disabled(model.state.analysisSharingID != nil && (model.state.timer?.phase != .ended || model.timerFinishing))
            Text("ChatGPTでカンペきのMCPを選び、コピーした依頼文を送ってください。結果はここに戻ります。").font(.caption)
            Text(model.practiceAnalysisStatus).font(.callout)
            ScrollView { PracticeFeedbackView(result: model.practiceAnalysis) }.frame(maxHeight: .infinity)
            Button("閉じる") { showPractice = false }
        }.padding(24).frame(width: 580, height: 540)
    }

    private var options: some View {
        Menu("準備・機能") {
            Button("ホームに戻る") { navigation.home() }
            Button("練習する") { navigation.open(.practice) }
            Button("資料をAIで整理する") { if model.preparationFolder == nil { model.startMCP() }; showPreparationAI = true }
            Button("iPhone接続") { navigation.open(.connection) }
            Button("分析・結果") { navigation.open(.analysis) }
            if model.deck != nil { Button("資料を大きく見る") { showDocument = true } }
            Divider()
            if presenting {
                Button(model.state.timer?.phase == .running ? "一時停止" : "再開") {
                    model.timerAction(model.state.timer?.phase == .running ? .pause : .resume, duration: nil)
                }.disabled(busy)
                Button("発表を終了") { endingSession = model.state.timer?.sessionID }.disabled(busy)
                Divider()
                Button("共有画面を選び直す") { selectWindow() }.disabled(busy)
            } else if model.state.timer?.phase == .ready {
                Button("資料を選び直す…") { model.importDeck() }.disabled(busy)
                Button("PowerPointで開く") { Task { await model.openDeckInPowerPoint() } }.disabled(model.deck == nil || busy)
                Button("共有画面を選ぶ") { selectWindow() }.disabled(busy)
                if model.deck == nil { Button("資料を選ばず、画面を共有") { screenOnly = true } }
                Button("時間を調整") { if let value = model.state.timer { adjustment = MacTimeDraft(snapshot:value) } }.disabled(busy)
            }
            Button("QRでつなぐ") { showQR = true }.disabled(link.connectedName != nil)
            Button("接続方法を変更") { connectionDraft = preparationDraft() }.disabled(busy || model.state.timer?.phase == .ended)
            if link.running && link.connectedName == nil { Button("接続待機を停止") { link.stop() }.disabled(busy) }
            Divider()
            Button("音声分析") { navigation.open(.audio) }
            Button("ChatGPTで振り返る") { showPractice = true }
            Button("要点原稿を確認・採用") { showPreparationNotes = true }
            Button("カメラの設定・結果") { showCamera = true }
            Menu("原稿の文字サイズ") {
                Button("標準") { notesSize = 0 }; Button("大") { notesSize = 1 }; Button("特大") { notesSize = 2 }
            }
            Button("接続の詳細") { showDetails = true }
            Button("画面構成の見本") { showScreenReview = true }
        }.fixedSize().accessibilityLabel("準備・機能")
    }

    private var nextAction: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.presentationStarting {
                ProgressView()
                Text(presenting ? "共有画面を確認しています" : "発表の準備を確認しています").font(.title2.bold())
                Button("キャンセル") { model.cancelPresentationStart() }
            } else if presenting {
                Text("発表画面を確認しましょう").font(.title2.bold())
                Text("タイマーはそのまま、共有を復旧します。")
                Button("共有画面を選び直す") { selectWindow() }.buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
            } else if model.state.timer?.phase == .ended {
                Text("おつかれさまでした").font(.title2.bold())
                Button("音声・AIで振り返る") { navigation.open(.practice) }
                Button("次の練習を準備") { model.timerAction(.reset,duration:nil) }.buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
            } else {
                Text("資料 → 画面 → 接続 → 時間").font(.caption).foregroundStyle(.secondary)
                switch step {
                case .document:
                    Text("発表する資料を選びましょう").font(.title2.bold())
                    Button("PPTXを選ぶ") { model.importDeck() }.buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
                case .powerPoint:
                    Text("次は、発表画面を開きます").font(.title2.bold())
                    Text("選んだ資料をPowerPointで開きます。")
                    Button(model.openingDocument ? "開いています…" : "PowerPointで開く") { Task { await model.openDeckInPowerPoint() } }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
                case .window:
                    Text("発表画面を選びましょう").font(.title2.bold())
                    Text(screenOnly ? "iPhoneに映すウィンドウを選びます。" : "PowerPointでスライドショーを開始してから、画面を選びます。")
                    Button(capture.refreshing ? "画面を探しています…" : "共有画面を選ぶ") { selectWindow() }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(busy || capture.refreshing)
                case .connection:
                    Text("iPhoneを接続しましょう").font(.title2.bold())
                    Text("QR接続を開きます。Macだけで練習する場合は「準備・機能」から変更できます。")
                    Button("iPhone接続へ") { navigation.open(.connection) }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
                case .time:
                    Text("発表時間を決めましょう").font(.title2.bold())
                    Button("時間を設定") { if let snapshot = model.state.timer { adjustment = MacTimeDraft(snapshot:snapshot) } }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(busy)
                case .ready:
                    Text("準備ができました").font(.title2.bold())
                    if let duration = model.state.timer?.durationSeconds { Text("発表時間 \(PresentationTimerText.time(duration))").font(.title.bold()) }
                    Text(macOnly ? "Macだけで練習します。" : "iPhoneからスライドを操作できます。")
                    if let reason = startReason { Text(reason).font(.callout) }
                    Button("発表を始める") { Task { await model.beginPresentation(macOnly:macOnly) } }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(startReason != nil || busy)
                }
            }
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(paper,in:RoundedRectangle(cornerRadius:20))
    }

    private func selectWindow() {
        guard !busy, !capture.refreshing, let draft = preparationDraft() else { return }
        Task {
            await capture.refreshWindows(requestPermission:true)
            guard canPrepare(draft) else { return }
            if capture.needsScreenPermission { model.errorMessage = capture.message }
            else { windowDraft = draft }
        }
    }

    private func canAdjust(_ draft: MacTimeDraft) -> Bool {
        !model.presentationStarting && !model.timerFinishing && !model.importing && !model.openingDocument &&
        model.state.timer?.phase == .ready &&
        model.state.timer?.sessionID == draft.snapshot.sessionID &&
        model.state.timer?.revision == draft.snapshot.revision &&
        model.timerReceivedAt.map { TimerClock.now - $0 < 3 } == true
    }

    private func preparationDraft() -> MacPreparationDraft? {
        model.state.timer.map { MacPreparationDraft(timer: $0, connectionID: model.preparationConnectionID) }
    }

    private func canPrepare(_ draft: MacPreparationDraft) -> Bool {
        !model.presentationStarting && !model.timerFinishing && !model.importing && !model.openingDocument &&
        model.state.timer?.phase == draft.timer.phase && draft.timer.phase != .ended &&
        model.state.timer?.sessionID == draft.timer.sessionID && model.state.timer?.revision == draft.timer.revision &&
        model.preparationConnectionID == draft.connectionID
    }
}

private struct MacTimeDraft: Identifiable {
    let id = UUID()
    let snapshot: PresentationTimerSnapshot
}

private struct MacPreparationActions {
    var window: () -> Void
    var connection: () -> Void
    var time: () -> Void
    var camera: () -> Void
    var details: () -> Void
    var qr: () -> Void
    var audio: () -> Void
    var practice: () -> Void
    var home: () -> Void
    var pause: () -> Void
    var end: () -> Void
}
private struct MacPreparationActionsKey: FocusedValueKey { typealias Value = MacPreparationActions }
private extension FocusedValues {
    var preparationActions: MacPreparationActions? {
        get { self[MacPreparationActionsKey.self] }
        set { self[MacPreparationActionsKey.self] = newValue }
    }
}
