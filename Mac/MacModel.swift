import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor final class MacModel: ObservableObject {
    let capture = WindowCapture()
    let link = PeerLink(isHost: true)
    @Published var selectedWindowID: UInt32? = nil
    @Published var state = PresentationState()
    @Published var deck: ImportedDeck?
    @Published var importing = false
    @Published var monitoring = false
    @Published var errorMessage: String?
    @Published var events: [SlideObservation] = []
    @Published private(set) var timerReceivedAt: TimeInterval?
    @Published private(set) var timerFinishing = false
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
    private var latestJPEG: Data?
    private var heartbeat: Timer?

    init() {
        capture.onJPEG = { [weak self] data in self?.latestJPEG = data; self?.link.sendFrame(data) }
        capture.onStopped = { [weak self] in
            guard let self else { return }
            self.disableControl()
            self.state.isSharing = false
            self.state.message = "共有停止。Macでウィンドウを選び直してください"
            self.publishState()
        }
        link.onConnection = { [weak self] connected in
            guard let self else { return }
            self.requests = RequestDeduplicator()
            if connected {
                self.publishState()
                if self.capture.sharing, let jpeg = self.latestJPEG { self.link.sendFrame(jpeg) }
            }
        }
        link.onMessage = { [weak self] message in
            guard let self, self.requests.accept(message.requestID) else { return }
            if message.kind == "timerControl", let command = message.timerCommand {
                self.applyTimer(command)
                return
            }
            guard message.kind == "control", let action = message.action else { return }
            if action == .refresh { self.publishState() } else { self.move(action) }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publishState() }
        }
        publishState()
    }

    func startSharing() async {
        guard !timerFinishing else { return }
        guard let window = capture.windows.first(where: { $0.id == selectedWindowID }) else { return }
        disableControl()
        latestJPEG = nil
        sharedWindow = window
        state = PresentationState()
        state.title = window.window.owningApplication?.applicationName ?? "画面共有"
        await capture.start(window: window)
        state.isSharing = capture.sharing
        state.message = window.isPowerPoint ? "プレビューを確認後、PowerPoint操作を有効にしてください" : "画面表示のみ対応。操作・原稿連携はPowerPointで利用できます"
        publishState()
    }

    func stopSharing() async {
        disableControl()
        await capture.stop()
        sharedWindow = nil
        latestJPEG = nil
        state = PresentationState()
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
        timer?.invalidate()
        timer = nil
        monitoring = false
        state.canControl = false
        state.slideIndex = nil
        state.slideID = nil
        state.notes = ""
        state.notesStatus = "PowerPointとの同期停止中"
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
            if lastObservedID != position.id || lastObservedPath != position.path {
                events.append(SlideObservation(sessionID: sessionID, observedAt: Date(), elapsedMs: Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000), presentation: position.title, slideID: position.id, slideIndex: position.index, timingSource: "PowerPoint polling 800ms; observed time, not exact transition time"))
                lastObservedID = position.id
                lastObservedPath = position.path
            }
            publishState()
        } catch {
            disableControl()
            state.message = error.localizedDescription
            errorMessage = error.localizedDescription
            publishState()
        }
    }

    func move(_ action: RemoteAction) {
        guard state.canControl, state.allowsSlideInteraction, monitoring, capture.sharing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMoveAt > 0.25 else { return }
        lastMoveAt = now
        do {
            // Read before each action; never increment an assumed page number.
            let current = try bridge.readPosition()
            if action == .next && current.index >= current.count { return }
            if action == .previous && current.index <= 1 { return }
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

    func timerAction(_ action: PresentationTimerAction, duration: Double?) {
        let snapshot = presentationTimer.snapshot(at: TimerClock.now)
        applyTimer(PresentationTimerCommand(sessionID: snapshot.sessionID, revision: snapshot.revision,
            sequence: snapshot.sequence, action: action, durationSeconds: duration))
    }

    private func applyTimer(_ command: PresentationTimerCommand) {
        guard !timerFinishing else { publishState(); return }
        guard command.action != .start || capture.sharing else { publishState(); return }
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
}
