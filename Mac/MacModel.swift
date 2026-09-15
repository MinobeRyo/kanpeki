import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor final class MacModel: ObservableObject {
    let capture = WindowCapture()
    let link = PeerLink(isHost: true)
    @Published var selectedWindowID: UInt32? = nil {
        didSet { if oldValue != selectedWindowID { cancelPresentationStart() } }
    }
    @Published var state = PresentationState()
    @Published var deck: ImportedDeck?
    @Published var importing = false
    @Published var monitoring = false
    @Published var errorMessage: String?
    @Published var events: [SlideObservation] = []
    @Published private(set) var timerReceivedAt: TimeInterval?
    @Published private(set) var timerFinishing = false
    @Published private(set) var presentationStarting = false
    @Published private(set) var preparationConnectionID = UUID()
    private var presentationStartIntent: MacPresentationStart?
    private var presentationTimer = PresentationTimerAuthority()
    private let bridge: PresentationControlling = PowerPointBridge()
    private var timer: Timer?
    private var sessionID = UUID()
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var requests = RequestDeduplicator()
    private var lastMoveAt: TimeInterval = 0
    private var sharedWindow: CaptureWindow?
    private var lastObservedID: Int?
    private var lastObservedPath: String?
    private var frameSessionID = UUID()
    private var frameRevision: UInt64 = 0
    private var snapshotRequests = SlideCaptureRequests()
    private var snapshotTask: Task<Void, Never>?
    private var lastSnapshotAt: TimeInterval?
    private var sharingAttemptID = UUID()
    private var heartbeat: Timer?
    private let pointerOverlay = SlidePointerOverlay()
    private var pointerReceiver = SlidePointerReceiver()

    init() {
        capture.usesObservedSnapshots = true
        capture.onStopped = { [weak self] in
            guard let self else { return }
            self.disableControl()
            self.state.isSharing = false
            self.state.message = "共有停止。Macでウィンドウを選び直してください"
            self.publishState()
        }
        link.onConnection = { [weak self] connected in
            guard let self else { return }
            self.preparationConnectionID = UUID()
            if self.presentationStarting, self.presentationStartIntent?.requiredConnectionID != nil {
                self.errorMessage = "接続が変わったため共有準備を取り消しました。接続を確認するか、Macだけで始めるを選んでください。"
                self.cancelPresentationStart()
            }
            self.requests = RequestDeduplicator()
            self.resetPointer()
            self.invalidateFrames(newSession: true)
            if connected {
                self.publishState()
                if self.monitoring { self.pollPosition() } else { self.requestSnapshot() }
            }
        }
        link.onMessage = { [weak self] message in
            if message.kind == "pointer", let self, let update = message.pointer,
               self.pointerReceiver.accept(update, sessionID: self.state.pointerSessionID) {
                if let point = update.point, self.capture.sharing, self.state.canControl, self.state.frameReady == true, self.state.allowsSlideInteraction,
                   self.link.connectedName != nil, let windowID = self.sharedWindow?.id {
                    self.pointerOverlay.show(point, windowID: windowID)
                } else { self.pointerOverlay.clear() }
                return
            }
            guard let self, self.requests.accept(message.requestID) else { return }
            if message.kind == "timerControl", let command = message.timerCommand {
                self.applyTimer(command)
                return
            }
            guard message.kind == "control", let action = message.action else { return }
            if action == .refresh { self.publishState() }
            else if message.frameIdentity == self.state.frameIdentity, message.frameIdentity != nil { self.move(action) }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let self, self.state.frameReady == true,
                   self.lastSnapshotAt.map({ TimerClock.now - $0 >= 3 }) ?? true {
                    self.invalidateFrames()
                    self.state.message = "画像更新を待っています。共有状態を確認してください"
                }
                self?.publishState()
                if self?.monitoring == false { self?.requestSnapshot() }
            }
        }
        publishState()
    }

    func startSharing() async {
        guard !timerFinishing else { return }
        guard let window = capture.windows.first(where: { $0.id == selectedWindowID }) else { return }
        let attempt = UUID()
        sharingAttemptID = attempt
        disableControl()
        sharedWindow = window
        state = stateWithoutSharing()
        resetPointer()
        invalidateFrames(newSession: true)
        state.title = window.window.owningApplication?.applicationName ?? "画面共有"
        await capture.start(window: window)
        guard sharingAttemptID == attempt else { return }
        state.isSharing = capture.sharing
        state.message = window.isPowerPoint ? "プレビューを確認後、PowerPoint操作を有効にしてください" : "画面表示のみ対応。操作・原稿連携はPowerPointで利用できます"
        publishState()
        requestSnapshot()
    }

    var presentationStartReason: String? {
        if presentationStarting { return "共有画面とスライドを確認しています…" }
        if importing { return "資料の読み込みが終わるまでお待ちください" }
        if timerFinishing { return "発表の終了処理を待っています" }
        guard selectedWindowID != nil, capture.windows.contains(where: { $0.id == selectedWindowID }) else {
            return "共有画面を選ぶと開始できます"
        }
        guard state.timer?.phase == .ready else { return "準備に戻ると次の発表を開始できます" }
        if state.timer?.durationSeconds == nil { return "発表時間を調整すると開始できます" }
        return nil
    }

    /// Called only by the explicit primary action. Capture permission is never requested on launch.
    func beginPresentation(macOnly: Bool = false) async {
        await preparePresentation(macOnly: macOnly, mode: .start)
    }

    /// Restore only sharing and PowerPoint observation; never start/reset the existing clock.
    func recoverSharing(macOnly: Bool, expectedTimer: PresentationTimerSnapshot, expectedConnectionID: UUID) async {
        await preparePresentation(macOnly: macOnly, mode: .recoverSharing,
            expectedTimer: expectedTimer, expectedConnectionID: expectedConnectionID)
    }

    private func preparePresentation(macOnly: Bool, mode: MacPresentationStart.Mode,
        expectedTimer: PresentationTimerSnapshot? = nil, expectedConnectionID: UUID? = nil) async {
        if let expectedTimer {
            guard state.timer?.sessionID == expectedTimer.sessionID,
                  state.timer?.revision == expectedTimer.revision,
                  state.timer?.phase == expectedTimer.phase,
                  preparationConnectionID == expectedConnectionID else {
                errorMessage = "準備状態が変わりました。共有画面をもう一度確認してください。"
                return
            }
        }
        let allowed = mode == .start ? presentationStartReason == nil :
            (!presentationStarting && !importing && !timerFinishing &&
                (state.timer?.phase == .running || state.timer?.phase == .paused))
        guard allowed,
              macOnly || link.connectedName != nil,
              let window = capture.windows.first(where: { $0.id == selectedWindowID }),
              let snapshot = state.timer else { return }
        let intent = MacPresentationStart(windowID: window.id, documentPath: deck?.url.path,
            timerSessionID: snapshot.sessionID, timerRevision: snapshot.revision,
            requiresPowerPoint: window.isPowerPoint,
            requiredConnectionID: macOnly ? nil : preparationConnectionID, mode: mode)
        presentationStartIntent = intent
        presentationStarting = true
        errorMessage = nil
        defer { presentationStartIntent = nil; presentationStarting = false }
        await startSharing()
        guard startIsCurrent(intent), capture.sharing else {
            if startIsCurrent(intent) { errorMessage = capture.message }
            await stopSharing(); return
        }
        if window.isPowerPoint {
            enableControl()
            guard monitoring && state.canControl else { await stopSharing(); return }
        }
        let deadline = TimerClock.now + 8
        while startIsCurrent(intent), capture.sharing, state.frameReady != true, TimerClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard startIsCurrent(intent),
              lastSnapshotAt.map({ TimerClock.now - $0 < 3 }) == true,
              intent.canComplete(activeIntentID: presentationStartIntent?.id,
                connectionID: link.connectedName == nil ? nil : preparationConnectionID,
                windowID: selectedWindowID, documentPath: deck?.url.path, timer: state.timer,
                sharing: capture.sharing, frameReady: state.frameReady == true, hasImage: capture.image != nil,
                controlsReady: monitoring && state.canControl) else {
            if presentationStartIntent != nil {
                errorMessage = intent.startsTimer ? "開始できませんでした。共有画面・資料と画像更新を確認してください。タイマーは開始していません。" :
                    "共有を復旧できませんでした。共有画面と資料を確認してください。発表タイマーは変更していません。"
            }
            await stopSharing(); return
        }
        if intent.startsTimer {
            let current = presentationTimer.snapshot(at: TimerClock.now)
            applyTimer(PresentationTimerCommand(sessionID: current.sessionID, revision: current.revision,
                sequence: current.sequence, action: .start), fromPreparation: true)
        }
    }

    private func startIsCurrent(_ intent: MacPresentationStart) -> Bool {
        !Task.isCancelled && presentationStartIntent?.id == intent.id &&
        (intent.requiredConnectionID == nil || (link.connectedName != nil && intent.requiredConnectionID == preparationConnectionID)) &&
        intent.matches(windowID: selectedWindowID, documentPath: deck?.url.path, timer: state.timer)
    }

    func cancelPresentationStart() {
        guard presentationStarting else { return }
        presentationStartIntent = nil
        Task { await stopSharing() }
    }

    func stopSharing() async {
        let attempt = UUID()
        sharingAttemptID = attempt
        disableControl()
        invalidateFrames(newSession: true)
        await capture.stop()
        guard sharingAttemptID == attempt else { return }
        sharedWindow = nil
        state = stateWithoutSharing()
        state.message = "Macが共有を停止しました"
        publishState()
    }

    func enableControl() {
        guard capture.sharing, sharedWindow?.isPowerPoint == true else {
            errorMessage = "PowerPointの発表用ウィンドウを共有してください"
            return
        }
        monitoring = true
        pollPosition()
        guard monitoring else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPosition() }
        }
    }

    func disableControl() {
        resetPointer()
        timer?.invalidate()
        timer = nil
        monitoring = false
        state.canControl = false
        state.slideIndex = nil
        state.slideID = nil
        state.notes = ""
        state.notesStatus = "PowerPointとの同期停止中"
        invalidateFrames()
        publishState()
    }

    func pollPosition() {
        guard monitoring, capture.sharing else { return }
        do {
            let position = try bridge.readPosition()
            state.title = position.title
            state.slideIndex = position.index
            state.slideID = position.id
            state.totalSlides = position.count
            state.canControl = true
            state.message = "PowerPointの実際の表示ページを同期中"
            state.notes = ""
            if let deck {
                let samePath = URL(fileURLWithPath: position.path).standardizedFileURL.resolvingSymlinksInPath() == deck.url.standardizedFileURL.resolvingSymlinksInPath()
                if samePath && deck.slides.count == position.count,
                   let slide = deck.slides.first(where: { $0.id == position.id && $0.index == position.index }) {
                    state.notes = slide.notes
                    state.notesStatus = slide.notes.isEmpty ? "このスライドの発表者ノートは空です" : "保存済みpptxから取得した原稿（編集後は再取込）"
                } else { state.notesStatus = "表示中の資料とpptxが一致しません。保存後に同じファイルを再取込してください" }
            } else { state.notesStatus = "発表者ノートを表示するにはpptxを読み込んでください" }
            if state.frameIdentity?.slideID != position.id || state.frameIdentity?.slideIndex != position.index || lastObservedPath != position.path {
                resetPointer()
                invalidateFrames()
            }
            if lastObservedID != position.id || lastObservedPath != position.path {
                events.append(SlideObservation(sessionID: sessionID, observedAt: Date(), elapsedMs: Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000), presentation: position.title, slideID: position.id, slideIndex: position.index, timingSource: "PowerPoint polling 800ms; observed time, not exact transition time"))
                lastObservedID = position.id
                lastObservedPath = position.path
            }
            publishState()
            requestSnapshot(observed: position)
        } catch {
            disableControl()
            state.message = error.localizedDescription
            errorMessage = error.localizedDescription
            publishState()
        }
    }

    func move(_ action: RemoteAction) {
        guard state.canControl, state.frameReady == true, state.allowsSlideInteraction, monitoring, capture.sharing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMoveAt > 0.25 else { return }
        lastMoveAt = now
        do {
            // Read before each action; never increment an assumed page number.
            let current = try bridge.readPosition()
            guard current.id == state.frameIdentity?.slideID, current.index == state.frameIdentity?.slideIndex,
                  current.path == lastObservedPath else { pollPosition(); return }
            if action == .next && current.index >= current.count { return }
            if action == .previous && current.index <= 1 { return }
            invalidateFrames()
            resetPointer()
            publishState()
            try bridge.move(action)
            pollPosition()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pollPosition() }
        } catch {
            disableControl()
            state.message = error.localizedDescription
            errorMessage = error.localizedDescription
            publishState()
        }
    }

    func importDeck() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pptx") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) { try PPTXImporter.load(url) }.value
                deck = imported
                if monitoring { pollPosition() }
            } catch { errorMessage = error.localizedDescription }
            importing = false
        }
    }

    func resetLog() {
        events = []
        sessionID = UUID()
        startedAt = ProcessInfo.processInfo.systemUptime
        lastObservedID = nil
        lastObservedPath = nil
        if monitoring { pollPosition() }
    }

    func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "kanpeki-slide-events.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(events).write(to: url, options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }

    private func invalidateFrames(newSession: Bool = false) {
        if newSession {
            frameSessionID = UUID(); frameRevision = 0
            snapshotTask?.cancel(); snapshotTask = nil
            snapshotRequests.invalidate()
        }
        frameRevision &+= 1
        state.frameIdentity = SlideFrameIdentity(sessionID: frameSessionID, revision: frameRevision,
            slideID: state.slideID, slideIndex: state.slideIndex)
        state.frameReady = false
        lastSnapshotAt = nil
        capture.image = nil
        pointerOverlay.clear()
    }

    private func requestSnapshot(observed: SlidePosition? = nil) {
        guard capture.sharing, let identity = state.frameIdentity else { return }
        guard monitoring == (observed != nil) else { return }
        guard let requestID = snapshotRequests.begin() else { return }
        let lease = SlideCaptureLease(identity: identity, beganAt: TimerClock.now)
        snapshotTask = Task {
            defer { if snapshotRequests.finish(requestID) { snapshotTask = nil } }
            do {
                let jpeg = try await capture.snapshot()
                guard !Task.isCancelled, snapshotRequests.activeID == requestID,
                      capture.sharing, state.frameIdentity == identity,
                      monitoring == (observed != nil) else { return }
                guard let jpeg, lease.accepts(current: state.frameIdentity, now: TimerClock.now) else {
                    invalidateFrames()
                    if presentationStarting {
                        presentationStartIntent = nil
                        errorMessage = "共有画像の確認に失敗したため、共有準備を取り消しました。"
                    }
                    publishState()
                    return
                }
                if let observed {
                    let after = try bridge.readPosition()
                    guard after.path == observed.path, after.id == observed.id,
                          after.index == observed.index, after.count == observed.count else {
                        invalidateFrames()
                        pollPosition()
                        return
                    }
                }
                guard let image = NSImage(data: jpeg) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                capture.image = image
                state.frameReady = true
                lastSnapshotAt = TimerClock.now
                capture.message = monitoring ? "ページ観測に合わせて画像更新 · JPEG · 音声なし" : "共有画像更新 · JPEG · 音声なし"
                publishState()
                link.sendFrame(jpeg, identity: identity)
            } catch {
                guard !Task.isCancelled, snapshotRequests.activeID == requestID, state.frameIdentity == identity else { return }
                invalidateFrames()
                state.message = "画像更新を待っています。共有状態を確認してください"
                if presentationStarting {
                    presentationStartIntent = nil
                    errorMessage = "共有画像を確認できないため、共有準備を取り消しました。"
                }
                publishState()
            }
        }
    }

    private func resetPointer() {
        pointerOverlay.clear()
        pointerReceiver = SlidePointerReceiver()
        state.pointerSessionID = UUID()
    }

    func timerAction(_ action: PresentationTimerAction, duration: Double?) {
        let snapshot = presentationTimer.snapshot(at: TimerClock.now)
        applyTimer(PresentationTimerCommand(sessionID: snapshot.sessionID, revision: snapshot.revision,
            sequence: snapshot.sequence, action: action, durationSeconds: duration))
    }

    private func applyTimer(_ command: PresentationTimerCommand, fromPreparation: Bool = false) {
        guard !timerFinishing else { publishState(); return }
        guard !presentationStarting || fromPreparation else { publishState(); return }
        guard command.action != .start || (capture.sharing && state.frameReady == true &&
            (sharedWindow?.isPowerPoint != true || (monitoring && state.canControl))) else { publishState(); return }
        let applied = presentationTimer.apply(command, at: TimerClock.now)
        if applied && command.action == .end { timerFinishing = true }
        publishState()
        if applied && command.action == .end {
            Task {
                await stopSharing()
                timerFinishing = false
                publishState()
            }
        }
    }

    private func publishState() {
        let now = TimerClock.now
        state.timer = presentationTimer.snapshot(at: now)
        state.timer?.isFinishing = timerFinishing
        timerReceivedAt = now
        link.send(WireMessage(kind: "state", state: state))
    }

    private func stateWithoutSharing() -> PresentationState {
        var value = PresentationState()
        value.timer = presentationTimer.snapshot(at: TimerClock.now)
        value.timer?.isFinishing = timerFinishing
        return value
    }
}
