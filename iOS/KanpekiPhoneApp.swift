import SwiftUI
import KanpekiCamera
import UIKit
import Combine

@MainActor final class PhoneModel: ObservableObject {
    let link = PeerLink(isHost: false)
    @Published var state = PresentationState()
    @Published var image: UIImage?
    @Published var lastFrameDate: Date?
    @Published var lastStateDate: Date?
    @Published var lastTapDate = Date.distantPast
    @Published private(set) var timerReceivedAt: TimeInterval?
    private var timerReceiver = PresentationTimerReceiver()
    private var pointerSequence: UInt64 = 0
    private var frameReceiver = SlideFrameReceiver()
    private var frameReceivedAt: TimeInterval?
    private var stateReceivedAt: TimeInterval?
    var hasFreshSlide: Bool {
        guard frameReceiver.matches(state), let frameReceivedAt, let stateReceivedAt else { return false }
        return (0..<3).contains(TimerClock.now - frameReceivedAt) && (0..<3).contains(TimerClock.now - stateReceivedAt)
    }

    func sendPointer(_ point: SlidePointerPoint?) {
        guard link.connectedName != nil, let sessionID = state.pointerSessionID else { return }
        if point != nil {
            guard state.canControl, state.allowsSlideInteraction, hasFreshSlide else { return }
        }
        pointerSequence &+= 1
        link.send(WireMessage(kind: "pointer", pointer: SlidePointerUpdate(sessionID: sessionID, sequence: pointerSequence, point: point)), reliably: point == nil)
    }

    init() {
        link.onFrame = { [weak self] frame in
            guard let self, let image = UIImage(data: frame.jpeg), self.frameReceiver.accept(frame, state: self.state) else { return }
            self.image = image
            self.lastFrameDate = Date()
            self.frameReceivedAt = TimerClock.now
        }
        link.onMessage = { [weak self] message in
            guard message.kind == "state", let state = message.state, let self else { return }
            guard self.timerReceiver.accept(state.timer) else { return }
            self.state = state
            self.timerReceivedAt = state.timer == nil ? nil : TimerClock.now
            self.lastStateDate = Date()
            self.stateReceivedAt = TimerClock.now
            self.frameReceiver.update(state: state)
            if !self.frameReceiver.matches(state) { self.image = nil; self.lastFrameDate = nil; self.frameReceivedAt = nil }
        }
        link.onConnection = { [weak self] connected in
            guard let self else { return }
            self.image = nil
            self.lastFrameDate = nil
            self.lastStateDate = nil
            self.timerReceivedAt = nil
            self.timerReceiver = PresentationTimerReceiver()
            self.frameReceiver = SlideFrameReceiver()
            self.frameReceivedAt = nil
            self.stateReceivedAt = nil
            self.state = PresentationState()
            if connected { self.link.send(WireMessage(kind: "control", action: .refresh)) }
        }
    }
    func move(_ action: RemoteAction) {
        guard link.connectedName != nil, state.canControl, state.allowsSlideInteraction, hasFreshSlide,
              Date().timeIntervalSince(lastTapDate) >= 0.3 else { return }
        lastTapDate = Date()
        link.send(WireMessage(kind: "control", action: action, frameIdentity: state.frameIdentity))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func stop() {
        sendPointer(nil)
        link.stop()
        image = nil
        lastFrameDate = nil
        lastStateDate = nil
        timerReceivedAt = nil
        timerReceiver = PresentationTimerReceiver()
        frameReceiver = SlideFrameReceiver()
        frameReceivedAt = nil
        stateReceivedAt = nil
        state = PresentationState()
    }

    func timerAction(_ action: PresentationTimerAction, duration: Double?) {
        guard link.connectedName != nil, let snapshot = state.timer, let timerReceivedAt,
              TimerClock.now - timerReceivedAt < 3, snapshot.isFinishing != true else { return }
        let command = PresentationTimerCommand(sessionID: snapshot.sessionID, revision: snapshot.revision,
            sequence: snapshot.sequence, action: action, durationSeconds: duration)
        link.send(WireMessage(kind: "timerControl", timerCommand: command))
    }
}

@main struct KanpekiPhoneApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            PhoneScreen(model: model, link: model.link)
                .onChange(of: phase) { _, value in
                    UIApplication.shared.isIdleTimerDisabled = value == .active
                    if value == .background { model.stop() }
                }
        }
    }
}

struct PhoneScreen: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var link: PeerLink
    @State private var showDetails = false
    @State private var showAudioTrial = false
    @StateObject private var audioRecorder = RecorderModel()
    @State private var showScreenReview = false
    @State private var reviewAfterDetails = false
    @State private var audioAfterDetails = false
    @StateObject private var camera = CameraController()
    @State private var presentationResult = PresentationResultAssociation()
    @State private var showCamera = false
    @StateObject private var notifications = PresentationNotificationPresenter()
    @Environment(\.scenePhase) private var cameraScenePhase
    private let ink = Color(red: 92/255, green: 102/255, blue: 115/255)
    private let paper = Color(red: 249/255, green: 255/255, blue: 230/255)
    private let mint = Color(red: 217/255, green: 235/255, blue: 213/255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image("BrandMascot").resizable().scaledToFit().frame(width: 42, height: 42)
                    Text("カンペき").font(.title2.bold())
                    Spacer()
                    PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: link.connectedName != nil)
                    Button { showDetails = true } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("接続と操作の詳細")
                }
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let timer = model.state.timer
                    let fresh = link.connectedName != nil && model.timerReceivedAt.map { TimerClock.now - $0 < 3 } == true
                    PresentationNotificationBanner(presenter: notifications,
                        input: PresentationNotificationInput(sessionID: timer?.sessionID,
                            isExpired: timer?.durationSeconds.map { timer!.elapsedSeconds >= $0 } ?? false,
                            isPresenting: timer?.phase == .running || timer?.phase == .paused,
                            isForeground: cameraScenePhase == .active, isConnected: fresh))
                }
                if link.connectedName == nil {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: 24) {
                                Spacer(minLength: 24)
                                Image("BrandMascot").resizable().scaledToFit().frame(width: 100, height: 100)
                                Text("Macにつなぐ").font(.largeTitle.bold())
                                if !link.availablePeers.isEmpty {
                                    Menu {
                                        ForEach(link.availablePeers, id: \.self) { peer in
                                            Button(peer.displayName) { link.invite(peer) }
                                        }
                                        Divider()
                                        Button("探し直す") { model.stop(); link.start() }
                                    } label: {
                                        Label("Macを選ぶ", systemImage: "desktopcomputer")
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }.buttonStyle(BrandPrimaryButtonStyle())
                                }
                                if link.availablePeers.isEmpty {
                                    Button(link.running ? "探し直す" : "Macを探す") {
                                        model.stop(); link.start()
                                    }.buttonStyle(.bordered).controlSize(.large)
                                }
                                Text(link.availablePeers.isEmpty ? "Macで接続待機を開始" : "接続するMacを選択")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 24)
                            }.frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Macと接続中", systemImage: "link").font(.caption)
                            Text(model.state.title).font(.headline).lineLimit(2)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("原稿").font(.caption.bold())
                                Text(model.state.notes.isEmpty ? "原稿を待っています" : model.state.notes)
                                    .font(.title3).lineSpacing(7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }.padding(20).background(paper, in: RoundedRectangle(cornerRadius: 20))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if camera.phase == .running {
                    Label("カメラ：\(camera.subject.title) · \(camera.summary.currentQuality)", systemImage: "video")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
                if link.connectedName != nil {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let fresh = model.hasFreshSlide
                        VStack(spacing: 8) {
                            if !fresh {
                                Label("共有画面の更新を待っています", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                            }
                            Text(model.state.slideIndex.map { "\($0) / \(model.state.totalSlides)" } ?? "— / —")
                                .font(.callout.monospacedDigit())
                            slide(fresh: fresh)
                        }
                    }
                }
            }.padding(16).background(mint.ignoresSafeArea())
                .foregroundStyle(ink)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showDetails, onDismiss: {
                    if audioAfterDetails { audioAfterDetails = false; showAudioTrial = true }
                    if reviewAfterDetails {
                        reviewAfterDetails = false
                        showScreenReview = true
                    }
                }) {
                    NavigationStack {
                        List {
                            NavigationLink("発表") {
                                List {
                                    PresentationResultsButton(association: presentationResult, camera: camera)
                                    PresentationTimerPanel(snapshot: model.state.timer, receivedAt: model.timerReceivedAt,
                                        connected: link.connectedName != nil, canStart: model.state.isSharing,
                                        send: { model.timerAction($0, duration: $1) })
                                }.navigationTitle("発表")
                            }
                            NavigationLink("その他") {
                                List {
                                    Button("カメラ") { showCamera = true }
                                    Menu("確認・接続") {
                                        Button("画面構成を試す") { reviewAfterDetails = true; showDetails = false }
                                        Button("音声を試す") { audioAfterDetails = true; showDetails = false }
                                            .disabled(camera.phase == .running || camera.phase == .preparing)
                                        if link.connectedName != nil {
                                            Button("接続を切る", role: .destructive) { model.stop(); showDetails = false }
                                        }
                                    }
                                    Text("右タップで次へ、左で戻る。ドラッグでポインター。")
                                        .font(.caption)
                                    Text(link.status).font(.caption)
                                }.navigationTitle("その他")
                            }
                        }.navigationTitle("メニュー")
                            .toolbar { Button("閉じる") { showDetails = false } }
                            .sheet(isPresented: $showCamera) {
                                NavigationStack {
                                    CameraPanel(controller: camera, onContinueWithoutAnalysis: { showCamera = false })
                                        .toolbar { Button("戻る") { showCamera = false } }
                                }
                            }
                    }
                }
        }.tint(ink).preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showScreenReview) { ScreenReview() }
        .fullScreenCover(isPresented: $showAudioTrial) {
            AudioCaptureView(model: audioRecorder, logoName: "BrandMascot", onClose: { showAudioTrial = false })
        }
        .onChange(of: cameraScenePhase) { _, phase in
            if phase != .active { model.sendPointer(nil) }
            if (phase != .active && camera.phase == .running) || (phase == .background && camera.phase == .preparing) {
                camera.stop(interrupted: true)
            }
        }
        .onDisappear { camera.stop(); model.sendPointer(nil) }
        .modifier(PresentationResultsObserver(snapshot: model.state.timer, connected: link.connectedName != nil,
            camera: camera, association: $presentationResult))
        .onChange(of: model.state.timer?.phase) { _, phase in
            if phase == .ended { camera.stop() }
        }
    }

    private func turn(_ action: RemoteAction, fresh: Bool) {
        guard fresh, model.image != nil,
              let index = model.state.slideIndex,
              (action == .next ? index < model.state.totalSlides : index > 1) else { return }
        model.move(action)
    }

    private func slide(fresh: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(paper)
                if let image = model.image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Label(model.state.isSharing ? "スライド画像を更新中" : "Macで共有を開始", systemImage: "rectangle.on.rectangle").font(.callout)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .overlay {
                    SlideTouchSurface(imageSize: model.image?.size ?? .zero,
                                      enabled: fresh && model.state.canControl && model.state.allowsSlideInteraction && cameraScenePhase == .active && !showDetails,
                                      sessionID: model.state.pointerSessionID,
                                      onPointer: model.sendPointer,
                                      onTap: { turn($0, fresh: fresh) })
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("共有スライド")
                .accessibilityAction(named: "次のスライド") { turn(.next, fresh: fresh) }
                .accessibilityAction(named: "前のスライド") { turn(.previous, fresh: fresh) }
        }.aspectRatio(model.image.map { $0.size.width / max($0.size.height, 1) } ?? 16/9, contentMode: .fit)
            .frame(maxHeight: 320)
    }
}
