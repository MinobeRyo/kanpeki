import SwiftUI
import KanpekiCamera

@main struct KanpekiMacApp: App {
    @StateObject private var model = MacModel()
    @State private var showScreenReview = false
    @AppStorage("macNotesSize") private var notesSize = 0
    @FocusedValue(\.preparationActions) private var actions
    var body: some Scene {
        WindowGroup("カンペき · Mac") {
            MacScreen(model: model, capture: model.capture, link: model.link, showScreenReview: $showScreenReview)
        }.defaultSize(width: 1200, height: 800)
            .commands {
                CommandMenu("準備") {
                    Button("共有画面を選ぶ…") { actions?.window() }
                    Button("接続方法を変更…") { actions?.connection() }
                    Button("時間を調整…") { actions?.time() }
                    Divider()
                    Button("カメラの設定・結果") { actions?.camera() }
                    Button("接続の詳細") { actions?.details() }
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
    @Binding var showScreenReview: Bool
    @AppStorage("macNotesSize") private var notesSize = 0
    @State private var showDetails = false
    @State private var macOnly = false
    @State private var screenOnly = false
    @State private var endingSession: UUID?
    @State private var adjustment: MacTimeDraft?
    @State private var windowDraft: MacPreparationDraft?
    @State private var connectionDraft: MacPreparationDraft?
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

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 12) {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 36, height: 36)
                Text("カンペき").font(.title2.bold())
                Spacer()
                if presenting || model.state.timer?.phase == .ended {
                    PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                }
                Label(link.connectedName ?? (macOnly ? "Macだけで練習" : "iPhone未接続"), systemImage: "iphone").font(.callout)
                if !showingDocumentPreview { options }
            }
            if model.deck == nil && !screenOnly && !presenting && model.state.timer?.phase != .ended {
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
                                DocumentPreview(url: deck.url).id(model.documentRevision).padding(12)
                            } else { Label("共有する画面を選びましょう", systemImage: "rectangle.on.rectangle") }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        if showingDocumentPreview {
                            Text("資料プレビュー · 発表画面は次の手順で共有します").font(.caption).foregroundStyle(.secondary)
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
        }.padding(28).frame(minWidth: 860, minHeight: 620)
            .background(mint).foregroundStyle(ink).tint(ink).preferredColorScheme(.light)
            .background(MacSlideKeyboard(model: model, onNarrowWindow: {}).frame(width: 0, height: 0))
            .task { await capture.refreshWindows() }
            .onChange(of: model.documentRevision) { _, _ in screenOnly = false }
            .focusedSceneValue(\.preparationActions, MacPreparationActions(
                window: { selectWindow() },
                connection: { if !busy { connectionDraft = preparationDraft() } },
                time: { if !busy, model.state.timer?.phase == .ready, let snapshot = model.state.timer { adjustment = MacTimeDraft(snapshot:snapshot) } },
                camera: { showCamera = true }, details: { showDetails = true }))
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
            .confirmationDialog("発表を終了しますか？", isPresented: Binding(get: { endingSession != nil }, set: { if !$0 { endingSession = nil } }), titleVisibility: .visible) {
                Button("発表を終了", role: .destructive) {
                    if let id = endingSession, model.state.timer?.sessionID == id { model.timerAction(.end, duration: nil) }
                    endingSession = nil
                }
                Button("続ける", role: .cancel) { endingSession = nil }
            }
            .alert("iPhoneからの接続", isPresented: Binding(get: { link.invitationName != nil }, set: { if !$0 { link.respondToInvitation(accept: false) } })) {
                Button("許可") { link.respondToInvitation(accept: true) }
                Button("拒否", role: .cancel) { link.respondToInvitation(accept: false) }
            } message: { Text("\(link.invitationName ?? "iPhone") に共有画面と原稿を送ります。自分の端末名か確認してください。") }
            .alert("確認が必要です", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                if capture.needsScreenPermission { Button("システム設定を開く") { capture.openScreenPermissionSettings() } }
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }


    private var options: some View {
        Menu {
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
            Button("接続方法を変更") { connectionDraft = preparationDraft() }.disabled(busy || model.state.timer?.phase == .ended)
            if link.running && link.connectedName == nil { Button("接続待機を停止") { link.stop() }.disabled(busy) }
            Divider()
            Button("カメラの設定・結果") { showCamera = true }
            Menu("原稿の文字サイズ") {
                Button("標準") { notesSize = 0 }; Button("大") { notesSize = 1 }; Button("特大") { notesSize = 2 }
            }
            Button("接続の詳細") { showDetails = true }
            Button("画面構成の見本") { showScreenReview = true }
        } label: { Image(systemName:"ellipsis").frame(width:32,height:28) }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("その他の操作")
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
                PresentationResultsButton(association: presentationResult, camera: camera)
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
                    Text(link.running ? "iPhoneの接続を待っています" : "iPhoneを使いますか？").font(.title2.bold())
                    Text(link.running ? "iPhoneの「Macにつなぐ」から、このMacを選んでください。" : "Macだけでも練習できます。")
                    Button(link.running ? "接続方法を変更" : "接続方法を選ぶ") { connectionDraft = preparationDraft() }
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
}
private struct MacPreparationActionsKey: FocusedValueKey { typealias Value = MacPreparationActions }
private extension FocusedValues {
    var preparationActions: MacPreparationActions? {
        get { self[MacPreparationActionsKey.self] }
        set { self[MacPreparationActionsKey.self] = newValue }
    }
}
