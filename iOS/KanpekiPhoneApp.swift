import SwiftUI
import UIKit
import Combine
import KanpekiCamera

@MainActor final class PhoneModel: ObservableObject {
    let link = PeerLink(isHost: false)
    @Published var state = PresentationState()
    @Published var image: UIImage?
    @Published var lastFrameDate: Date?
    @Published var lastStateDate: Date?
    @Published var lastTapDate = Date.distantPast

    init() {
        link.onFrame = { [weak self] data in
            guard let image = UIImage(data: data), let self else { return }
            self.image = image
            self.lastFrameDate = Date()
        }
        link.onMessage = { [weak self] message in
            guard message.kind == "state", let state = message.state, let self else { return }
            self.state = state
            self.lastStateDate = Date()
            if !state.isSharing { self.image = nil; self.lastFrameDate = nil }
        }
        link.onConnection = { [weak self] connected in
            guard let self else { return }
            self.image = nil
            self.lastFrameDate = nil
            self.lastStateDate = nil
            self.state = PresentationState()
            if connected { self.link.send(WireMessage(kind: "control", action: .refresh)) }
        }
    }
    func move(_ action: RemoteAction) {
        guard link.connectedName != nil, state.canControl, state.isSharing,
              let lastStateDate, Date().timeIntervalSince(lastStateDate) < 3,
              Date().timeIntervalSince(lastTapDate) >= 0.3 else { return }
        lastTapDate = Date()
        link.send(WireMessage(kind: "control", action: action))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func stop() {
        link.stop()
        image = nil
        lastFrameDate = nil
        lastStateDate = nil
        state = PresentationState()
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
    @StateObject private var camera = CameraController()
    @State private var showCamera = false
    @Environment(\.scenePhase) private var cameraScenePhase
    private let accent = Color(red: 0.20, green: 0.35, blue: 0.82)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label(link.connectedName == nil ? "未接続" : "Macと接続中", systemImage: "circle.fill").font(.caption.bold()).foregroundStyle(link.connectedName == nil ? .secondary : accent)
                        Spacer()
                        Text("SLIDE REMOTE").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    if link.connectedName == nil {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Macのスライドを手元に。").font(.title2.bold())
                            Text("Macで「接続待機を開始」を押してから、下の一覧で接続先を選択してください。").font(.callout).foregroundStyle(.secondary)
                            Button(link.running ? "検索をやり直す" : "近くのMacを探す") {
                                model.stop(); link.start()
                            }.buttonStyle(.borderedProminent)
                            ForEach(link.availablePeers, id: \.self) { peer in
                                Button { link.invite(peer) } label: {
                                    HStack { Image(systemName: "desktopcomputer"); Text(peer.displayName); Spacer(); Image(systemName: "chevron.right") }.padding(12)
                                }.buttonStyle(.bordered)
                            }
                            Text(link.status).font(.caption).foregroundStyle(.secondary)
                        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.state.title).font(.headline).lineLimit(2)
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.055, green: 0.07, blue: 0.12))
                            if let image = model.image {
                                Image(uiImage: image).resizable().scaledToFit().padding(3)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 35))
                                    Text("Macの共有画面がここに表示されます").font(.caption)
                                }.foregroundStyle(.white.opacity(0.7)).padding()
                            }
                        }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                        TimelineView(.periodic(from: .now, by: 0.5)) { context in
                            let fresh = model.lastStateDate.map { context.date.timeIntervalSince($0) < 3 } ?? false
                            let frameAge = model.lastFrameDate.map { context.date.timeIntervalSince($0) }
                            VStack(spacing: 12) {
                                if let frameAge, frameAge > 3 {
                                    Label("画像の更新が止まっています。Macの共有状態を確認してください", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                }
                                HStack(spacing: 15) {
                                    Button { model.move(.previous) } label: { Image(systemName: "chevron.left").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 52) }
                                        .buttonStyle(.bordered).disabled(!fresh || !model.state.canControl || model.state.slideIndex == 1)
                                    Text(model.state.slideIndex.map { "\($0) / \(model.state.totalSlides)" } ?? "— / —")
                                        .font(.system(.title3, design: .monospaced)).monospacedDigit()
                                    Button { model.move(.next) } label: { Image(systemName: "chevron.right").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 52) }
                                        .buttonStyle(.borderedProminent).disabled(!fresh || !model.state.canControl || model.state.slideIndex == model.state.totalSlides)
                                }
                            }
                        }
                        Text(model.state.message).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("発表者ノート", systemImage: "text.alignleft").font(.headline)
                        Text(model.state.notesStatus).font(.caption).foregroundStyle(.secondary)
                        Text(model.state.notes.isEmpty ? "原稿はMacで読み込んだpptxから同期されます。" : model.state.notes)
                            .font(.body).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    if camera.phase == .running {
                        Label("カメラ：\(camera.subject.title) · \(camera.summary.currentQuality)", systemImage: "video")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("カンペき")
                .toolbar {
                    Button { showCamera = true } label: { Image(systemName: "video") }.accessibilityLabel("カメラ分析")
                    if link.connectedName != nil { Button("切断") { model.stop() } }
                }
        }.tint(accent)
        .sheet(isPresented: $showCamera) {
            VStack {
                HStack { Spacer(); Button("発表画面に戻る") { showCamera = false } }.padding()
                CameraPanel(controller: camera, onContinueWithoutAnalysis: { showCamera = false })
            }
        }
        .onChange(of: cameraScenePhase) { _, phase in
            if (phase != .active && camera.phase == .running) || (phase == .background && camera.phase == .preparing) {
                camera.stop(interrupted: true)
            }
        }
        .onDisappear { camera.stop() }
    }
}
