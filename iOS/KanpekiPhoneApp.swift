import SwiftUI
import UIKit
import Combine

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
    @State private var showDetails = false
    @State private var dragged = false
    @State private var touchStarted: Date?
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
                    Button { showDetails = true } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("接続と操作の詳細")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if link.connectedName == nil {
                            Text("Macにつなぐ").font(.title.bold())
                            Text("Macで接続待機を開始してください。")
                            Button(link.running ? "もう一度探す" : "近くのMacを探す") {
                                model.stop(); link.start()
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                            ForEach(link.availablePeers, id: \.self) { peer in
                                Button { link.invite(peer) } label: {
                                    Label(peer.displayName, systemImage: "desktopcomputer")
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.buttonStyle(.bordered)
                            }
                            Text(link.status).font(.caption)
                            HStack {
                                Image("BrandMascot").resizable().scaledToFit().frame(width: 72, height: 72)
                                Text("見つかったMacを選んでね").font(.callout)
                            }.padding(.top)
                        } else {
                            Label("Macと接続中", systemImage: "link").font(.caption)
                            Text(model.state.title).font(.headline).lineLimit(2)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("原稿").font(.caption.bold())
                                Text(model.state.notes.isEmpty ? "原稿を待っています" : model.state.notes)
                                    .font(.title3).lineSpacing(7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }.padding(20).background(paper, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if link.connectedName != nil {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let fresh = model.lastStateDate.map { context.date.timeIntervalSince($0) < 3 } ?? false
                        let frameFresh = model.lastFrameDate.map { context.date.timeIntervalSince($0) < 3 } ?? false
                        VStack(spacing: 8) {
                            if !fresh || !frameFresh {
                                Label("共有画面の更新を待っています", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                            }
                            Text(model.state.slideIndex.map { "\($0) / \(model.state.totalSlides)" } ?? "— / —")
                                .font(.callout.monospacedDigit())
                            slide(fresh: fresh && frameFresh)
                        }
                    }
                }
            }.padding(16).background(mint.ignoresSafeArea())
                .foregroundStyle(ink)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showDetails) {
                    NavigationStack {
                        List {
                            Section("操作") {
                                Text("スライドの右側をタップすると進み、左側で戻ります。")
                                Text("ポインター送信・時間通知・音声分析は準備中です。")
                            }
                            Section("接続") { Text(link.status); Text(model.state.message); Text(model.state.notesStatus) }
                            if link.connectedName != nil {
                                Button("Macとの接続を切る", role: .destructive) { model.stop(); showDetails = false }
                            }
                        }.navigationTitle("接続と操作")
                            .toolbar { Button("閉じる") { showDetails = false } }
                    }
                }
        }.tint(ink).preferredColorScheme(.light)
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
                    Label("Macで共有を開始", systemImage: "rectangle.on.rectangle").font(.callout)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if touchStarted == nil { touchStarted = value.time }
                        if hypot(value.translation.width, value.translation.height) > 8 { dragged = true }
                    }
                    .onEnded { value in
                        defer { dragged = false; touchStarted = nil }
                        guard !dragged, hypot(value.translation.width, value.translation.height) <= 8,
                              value.time.timeIntervalSince(touchStarted ?? value.time) < 0.5 else { return }
                        turn(value.location.x < geo.size.width / 2 ? .previous : .next, fresh: fresh)
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("共有スライド")
                .accessibilityAction(named: "次のスライド") { turn(.next, fresh: fresh) }
                .accessibilityAction(named: "前のスライド") { turn(.previous, fresh: fresh) }
        }.aspectRatio(model.image.map { $0.size.width / max($0.size.height, 1) } ?? 16/9, contentMode: .fit)
            .frame(maxHeight: 320)
    }
}
