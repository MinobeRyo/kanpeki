import SwiftUI
import KanpekiCamera
import KanpekiAudioHost

@main struct KanpekiMacApp: App {
    @StateObject private var model = MacModel()
    @State private var showPreparation = true
    @State private var showScreenReview = false
    @AppStorage("macNotesSize") private var notesSize = 0
    @StateObject private var audio = AudioHostModel()
    var body: some Scene {
        WindowGroup("カンペき · Mac") {
            MacScreen(model: model, capture: model.capture, link: model.link,
                showPreparation: $showPreparation, showScreenReview: $showScreenReview)
        }
            .defaultSize(width: 1440, height: 900)
            .commands {
                CommandGroup(after: .newItem) {
                    Button("切替記録をJSONで書き出す") { model.exportLog() }.disabled(model.events.isEmpty)
                    Button("新規記録") { model.resetLog() }
                }
                CommandGroup(after: .toolbar) {
                    Button("準備パネルを表示／非表示") { showPreparation.toggle() }
                    Button("画面構成を試す") { showScreenReview = true }
                    Divider()
                    Button("原稿を大きく") { notesSize = min(2, max(0, notesSize) + 1) }.keyboardShortcut("+")
                    Button("原稿を小さく") { notesSize = max(0, min(2, notesSize) - 1) }.keyboardShortcut("-")
                }
            }
        Window("カンペき · 音声分析", id: "audio-analysis") {
            AudioHostPanel(model: audio).frame(minWidth: 680, minHeight: 620)
        }.defaultSize(width: 760, height: 780)
    }
}

struct MacScreen: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: MacModel
    @ObservedObject var capture: WindowCapture
    @ObservedObject var link: PeerLink
    @Binding var showPreparation: Bool
    @Binding var showScreenReview: Bool
    @AppStorage("macPreparationGuide") private var showGuide = true
    @AppStorage("macNotesSize") private var notesSize = 0
    @State private var showDetails = false
    @State private var macOnly = false
    @State private var endingSession: UUID?
    @State private var adjustment: MacTimeDraft?
    @State private var windowDraft: MacPreparationDraft?
    @State private var connectionDraft: MacPreparationDraft?
    @State private var showQR = false
    @StateObject private var camera = CameraController()
    @State private var presentationResult = PresentationResultAssociation()
    @State private var showCamera = false
    private let ink = BrandColor.ink
    private let paper = BrandColor.paper
    private let mint = BrandColor.mint
    private var presenting: Bool { model.state.timer?.phase == .running || model.state.timer?.phase == .paused }
    private var startReason: String? {
        model.presentationStartReason ?? (link.connectedName == nil && !macOnly ? "iPhoneを接続するか、Macだけで始めるを選んでください。" : nil)
    }

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 40, height: 40)
                Text("カンペき").font(.title2.bold())
                PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                Spacer()
                Label("iPhone：\(link.connectedName ?? "未接続")", systemImage: "iphone")
                    .font(.callout)
                Button("音声分析", systemImage: "waveform") { openWindow(id: "audio-analysis") }
                Button("QRでつなぐ", systemImage: "qrcode") { showQR = true }.disabled(link.connectedName != nil)
                Menu("その他") {
                    Button("準備パネルを表示／非表示") { showPreparation.toggle() }
                    Button("接続の詳細") { showDetails = true }
                    if presenting {
                        Button("発表を終了") { endingSession = model.state.timer?.sessionID }.disabled(model.timerFinishing)
                    }
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(model.deck?.title ?? model.state.title).font(.headline).lineLimit(1)
                        Spacer()
                        Text(model.state.slideIndex.map { "\($0) / \(model.state.totalSlides)" } ?? "— / —").monospacedDigit()
                    }
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(paper)
                        if let image = capture.image {
                            Image(nsImage: image).resizable().scaledToFit()
                        } else if capture.sharing {
                            Label("スライド画像を更新中", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            VStack(spacing: 16) {
                                Image("BrandMascot").resizable().scaledToFit().frame(width: 100, height: 100)
                                Text("いつものスライドを、ここに。").font(.title2.bold())
                                Text(showPreparation ? "右の手順に沿って準備しましょう" : "準備パネルを開いて画面を選びましょう").font(.callout)
                            }
                        }
                    }.frame(height: max(180, geometry.size.height * 0.50)).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    HStack {
                        Button { model.move(.previous) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 30) }
                            .accessibilityLabel("前のスライド")
                            .help("前のスライド（←キー・文字編集中を除く）")
                            .disabled(model.state.frameReady != true || !model.state.canMoveSlide(.previous))
                        Button { model.move(.next) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 30) }
                            .accessibilityLabel("次のスライド")
                            .help("次のスライド（→キー・文字編集中を除く）")
                            .disabled(model.state.frameReady != true || !model.state.canMoveSlide(.next))
                        Spacer()
                        Label(model.state.message, systemImage: model.state.frameReady == true ? "checkmark.circle" : "info.circle")
                            .font(.callout).lineLimit(2)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("原稿").font(.headline)
                            Spacer()
                            Button("A−") { notesSize = max(0, min(2, notesSize) - 1) }.disabled(notesSize <= 0).help("原稿を小さく（⌘−）")
                            Button("A＋") { notesSize = min(2, max(0, notesSize) + 1) }.disabled(notesSize >= 2).help("原稿を大きく（⌘＋）")
                        }
                        ScrollView {
                            Text(model.state.notes.isEmpty ? "スライドと原稿が同期すると、ここに表示されます。" : model.state.notes)
                                .font(.system(size: [18.0, 22.0, 26.0][min(2, max(0, notesSize))])).lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(minHeight: 80, maxHeight: .infinity)
                        if model.state.notes.isEmpty { Text(model.state.notesStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }.padding(20).background(paper, in: RoundedRectangle(cornerRadius: 20))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(24)
        }.frame(minWidth: 780, minHeight: 640)
            .background(mint).foregroundStyle(ink).tint(ink).preferredColorScheme(.light)
            .inspector(isPresented: $showPreparation) {
                preparation.inspectorColumnWidth(min: 320, ideal: 408, max: 408)
            }
            .background(MacSlideKeyboard(model: model, onNarrowWindow: { showPreparation = false }).frame(width: 0, height: 0))
            .task { await capture.refreshWindows() }
            .onChange(of: model.deck?.url) { _, _ in Task { await capture.refreshWindows() } }
            .onChange(of: showPreparation) { _, visible in if visible { Task { await capture.refreshWindows() } } }
            .onChange(of: capture.message) { _, message in
                if capture.needsScreenPermission { model.errorMessage = message }
            }
            .task { if !link.running { link.start() } }
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
            .onChange(of: camera.result) { _, _ in shareCameraEvidence() }
            .onChange(of: model.state.timer) { _, _ in shareCameraEvidence() }
            .onDisappear { camera.stop(); model.cancelPresentationStart() }
            .modifier(PresentationResultsObserver(snapshot: model.state.timer, connected: true,
                camera: camera, association: $presentationResult))
            .onChange(of: model.state.timer?.phase) { _, phase in
                if phase == .ended { camera.stop() }
                if phase == .running { showPreparation = false }
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

    private func shareCameraEvidence() {
        let cameraID = presentationResult.sessionID == model.state.timer?.sessionID ? presentationResult.cameraID : nil
        let facts = CameraAnalysisEvidence.facts(camera: camera, prefix: "macCamera", associatedCameraID: cameraID)
        model.updateCameraAnalysis(facts, presentationID: facts.isEmpty ? nil : model.state.timer?.sessionID)
    }

    private var preparation: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(presenting ? "発表中の設定" : "準備").font(.largeTitle.bold())
                    if model.state.timer?.phase == .ready {
                        stepCard("1 資料", complete: model.deck != nil) {
                            Text(model.deck.map { "\($0.title) · \($0.slides.count)枚" } ?? "PowerPointで発表資料を開いてください")
                            Button(model.importing ? "読込中…" : "PPTXの原稿を選ぶ") { model.importDeck() }
                                .disabled(model.importing || model.presentationStarting)
                            Text("原稿の読込は任意です。共有する資料と同じPPTXを選びます。").font(.caption)
                        }
                        stepCard("2 共有画面", complete: capture.windows.contains { $0.id == model.selectedWindowID }) {
                            HStack {
                                Text(capture.windows.first { $0.id == model.selectedWindowID }?.label ?? "共有する画面を選んでください")
                                Spacer()
                                Button { Task { await capture.refreshWindows(requestPermission: true) } } label: { Image(systemName: "arrow.clockwise") }
                                    .help("共有ウィンドウを更新").disabled(capture.refreshing || model.presentationStarting)
                            }
                            if capture.needsScreenPermission {
                                Text("画面を共有するには画面収録の許可が必要です。").font(.callout)
                                Button("画面収録を許可して探す") { Task { await capture.refreshWindows(requestPermission: true) } }
                                Button("システム設定を開く") { capture.openScreenPermissionSettings() }
                            } else {
                                Button("共有画面を選ぶ") { windowDraft = preparationDraft() }.disabled(model.presentationStarting)
                                Text("PowerPoint以外は表示のみです。").font(.caption)
                            }
                        }
                        stepCard("3 iPhone", complete: link.connectedName != nil || macOnly) {
                            Text(link.connectedName ?? (macOnly ? "Macだけで始める" : "iPhoneで使う場合は接続方法を選びます。"))
                            Button("接続方法を選ぶ") { connectionDraft = preparationDraft() }.disabled(model.presentationStarting)
                            if link.running && link.connectedName == nil {
                                Text(link.status).font(.caption)
                                Button("接続待機を停止") { link.stop() }.disabled(model.presentationStarting)
                            }
                        }
                    }
                    GroupBox("発表時間") {
                        VStack(alignment: .leading, spacing: 12) {
                            PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                            if let snapshot = model.state.timer {
                                if snapshot.phase == .ready {
                                    Button("時間を調整", systemImage: "timer") { adjustment = MacTimeDraft(snapshot: snapshot) }
                                        .disabled(model.presentationStarting || model.timerFinishing)
                                } else if presenting {
                                    Button(snapshot.phase == .running ? "一時停止" : "再開") {
                                        model.timerAction(snapshot.phase == .running ? .pause : .resume, duration: nil)
                                    }.disabled(model.timerFinishing)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if presenting {
                        GroupBox("共有とスライド操作") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(capture.windows.first { $0.id == model.selectedWindowID }?.label ?? "共有画面を選び直してください")
                                if capture.needsScreenPermission {
                                    Button("画面収録を許可して探す") { Task { await capture.refreshWindows(requestPermission: true) } }
                                    Button("システム設定を開く") { capture.openScreenPermissionSettings() }
                                }
                                Button("共有・操作を確認し直す") {
                                    Task {
                                        await capture.refreshWindows()
                                        windowDraft = preparationDraft()
                                    }
                                }.disabled(model.presentationStarting || model.timerFinishing || capture.needsScreenPermission ||
                                    (link.connectedName == nil && !macOnly))
                                Text("画面を選んで確認後、共有とPowerPoint操作を復旧します。発表タイマーはそのままです。").font(.caption)
                                if link.connectedName == nil {
                                    Text(macOnly ? "Macだけで使用中" : "復旧にはiPhoneの再接続か、Macだけで使う選択が必要です。").font(.caption)
                                    Button("接続方法を選ぶ") { connectionDraft = preparationDraft() }.disabled(model.presentationStarting)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox("ChatGPTで相談") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.mcpStatus).font(.caption)
                            Button("分析データの共有を開始") { model.startMCP() }
                            Button("ChatGPTとの共有を停止") { model.stopMCP() }
                            Text("音声認識結果・カメラの集計値も共有します。").font(.caption)
                            Button("発表をまとめて分析・依頼文をコピー") { model.requestPracticeAnalysis() }
                                .disabled(model.state.analysisSharingID == nil || model.state.timer?.phase != .ended || model.timerFinishing)
                            Text("音声: \(model.sharedAudioAvailable ? "取得済み" : "未共有") · カメラ: \(model.sharedCameraAvailable ? "取得済み" : "未共有")").font(.caption)
                            Text(model.practiceAnalysisStatus).font(.caption)
                            PracticeFeedbackView(result: model.practiceAnalysis)
                            Link("ChatGPTを開く", destination: URL(string: "https://chatgpt.com/")!)
                        }
                    }
                    Button { showCamera = true } label: { Label("カメラの設定・結果", systemImage: "video") }
                    PresentationResultsButton(association: presentationResult, camera: camera)
                    if camera.phase == .running { Text("\(camera.subject.title) · \(camera.summary.currentQuality)").font(.caption) }
                }.padding(22)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if showGuide {
                    HStack {
                        Image("BrandMascot").resizable().scaledToFit().frame(width: 52, height: 52)
                        Text(presenting ? "手元のスライドに集中しよう" : (startReason == nil ? "準備ができたら始めよう" : "資料・共有画面・接続を順に確認しよう"))
                            .font(.callout)
                        Button { showGuide = false } label: { Image(systemName: "xmark") }.help("案内を閉じる")
                    }
                } else { Button("案内を表示") { showGuide = true }.font(.caption) }
                if model.presentationStarting {
                    HStack { ProgressView(); Text("共有とスライドを確認中") }
                    Button(presenting ? "復旧をキャンセル" : "開始をキャンセル") { model.cancelPresentationStart() }
                } else if presenting {
                    Button("発表を終了") { endingSession = model.state.timer?.sessionID }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(model.timerFinishing)
                } else if model.state.timer?.phase == .ended {
                    Button("準備に戻る") { model.timerAction(.reset, duration: nil); showPreparation = true }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(model.timerFinishing)
                } else {
                    if let reason = startReason { Text(reason).font(.callout) }
                    Button("発表を始める") { Task { await model.beginPresentation(macOnly: macOnly) } }
                        .buttonStyle(BrandPrimaryButtonStyle()).disabled(startReason != nil)
                }
            }.padding(22)
        }.background(paper).foregroundStyle(ink).tint(ink).preferredColorScheme(.light)
    }

    private func stepCard<Content: View>(_ title: String, complete: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: complete ? "checkmark.circle.fill" : "circle").font(.headline)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(complete ? mint : Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }

    private func canAdjust(_ draft: MacTimeDraft) -> Bool {
        !model.presentationStarting && !model.timerFinishing &&
        model.state.timer?.phase == .ready &&
        model.state.timer?.sessionID == draft.snapshot.sessionID &&
        model.state.timer?.revision == draft.snapshot.revision &&
        model.timerReceivedAt.map { TimerClock.now - $0 < 3 } == true
    }

    private func preparationDraft() -> MacPreparationDraft? {
        model.state.timer.map { MacPreparationDraft(timer: $0, connectionID: model.preparationConnectionID) }
    }

    private func canPrepare(_ draft: MacPreparationDraft) -> Bool {
        !model.presentationStarting && !model.timerFinishing &&
        model.state.timer?.phase == draft.timer.phase && draft.timer.phase != .ended &&
        model.state.timer?.sessionID == draft.timer.sessionID && model.state.timer?.revision == draft.timer.revision &&
        model.preparationConnectionID == draft.connectionID
    }
}

private struct MacTimeDraft: Identifiable {
    let id = UUID()
    let snapshot: PresentationTimerSnapshot
}
