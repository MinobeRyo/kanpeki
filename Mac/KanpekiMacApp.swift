import SwiftUI
import KanpekiCamera

@main struct KanpekiMacApp: App {
    @StateObject private var model = MacModel()
    var body: some Scene {
        WindowGroup("カンペき · Mac") { MacScreen(model: model, capture: model.capture, link: model.link) }
            .defaultSize(width: 1440, height: 900)
    }
}

struct MacScreen: View {
    @ObservedObject var model: MacModel
    @ObservedObject var capture: WindowCapture
    @ObservedObject var link: PeerLink
    @State private var showAllWindows = false
    @State private var showGuide = true
    @State private var showDetails = false
    @State private var showQR = false
    @State private var showScreenReview = false
    @StateObject private var camera = CameraController()
    @State private var presentationResult = PresentationResultAssociation()
    @State private var showCamera = false
    private let ink = Color(red: 92/255, green: 102/255, blue: 115/255)
    private let paper = Color(red: 249/255, green: 255/255, blue: 230/255)
    private let mint = Color(red: 217/255, green: 235/255, blue: 213/255)

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 40, height: 40)
                Text("カンペき").font(.title2.bold())
                PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                Spacer()
                Label(link.connectedName == nil ? "iPhone未接続" : "iPhone接続済み", systemImage: "iphone")
                    .font(.callout)
                Button("QRでつなぐ", systemImage: "qrcode") { showQR = true }.disabled(link.connectedName != nil)
                Button("画面構成を試す") { showScreenReview = true }
                Button { showDetails = true } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                    .accessibilityLabel("接続の詳細と記録")
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
                                Button(model.importing ? "読込中…" : "PPTXの原稿を選ぶ") { model.importDeck() }
                                    .buttonStyle(BrandPrimaryButtonStyle()).disabled(model.importing)
                                Text("共有する画面は右側で選べます").font(.callout)
                            }
                        }
                    }.aspectRatio(16/9, contentMode: .fit).layoutPriority(1).clipShape(RoundedRectangle(cornerRadius: 20))
                    HStack {
                        Button { model.move(.previous) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 30) }
                            .accessibilityLabel("前のスライド")
                            .disabled(model.state.frameReady != true || !model.state.canMoveSlide(.previous))
                        Button { model.move(.next) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 30) }
                            .accessibilityLabel("次のスライド")
                            .disabled(model.state.frameReady != true || !model.state.canMoveSlide(.next))
                        Spacer()
                        Text(capture.sharing ? "共有中" : "共有前").font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("原稿").font(.headline)
                        ScrollView {
                            Text(model.state.notes.isEmpty ? "スライドと原稿が同期すると、ここに表示されます。" : model.state.notes)
                                .font(.title3).lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(minHeight: 80, maxHeight: .infinity)
                        if model.state.notes.isEmpty { Text(model.state.notesStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }.padding(20).background(paper, in: RoundedRectangle(cornerRadius: 20))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                preparation.frame(width: 340)
            }
        }.padding(24).frame(minWidth: 980, minHeight: 720)
            .background(mint).foregroundStyle(ink).tint(ink).preferredColorScheme(.light)
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
                    Text("接続と記録").font(.title2.bold())
                    Text(link.status); Text(model.state.message); Text(capture.message)
                    Text("切替記録：\(model.events.count)件")
                    HStack {
                        Button("JSONを書き出す") { model.exportLog() }.disabled(model.events.isEmpty)
                        Button("新規記録") { model.resetLog() }
                        Spacer(); Button("閉じる") { showDetails = false }
                    }
                }.padding(24).frame(width: 520)
            }
            .onDisappear { camera.stop() }
            .modifier(PresentationResultsObserver(snapshot: model.state.timer, connected: true,
                camera: camera, association: $presentationResult))
            .onChange(of: model.state.timer?.phase) { _, phase in
                if phase == .ended { camera.stop() }
            }
            .alert("iPhoneからの接続", isPresented: Binding(get: { link.invitation != nil }, set: { _ in }), presenting: link.invitation) { invitation in
                Button("許可") { link.respondToInvitation(accept: true, invitationID: invitation.id) }
                Button("拒否", role: .cancel) { link.respondToInvitation(accept: false, invitationID: invitation.id) }
            } message: { invitation in Text("\(invitation.name) に共有画面と原稿を送ります。自分の端末から接続を操作したか確認してください。") }
            .alert("確認が必要です", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("準備").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Text("資料と原稿").font(.headline)
                    Button(model.importing ? "読込中…" : "PPTXの原稿を選ぶ") { model.importDeck() }.disabled(model.importing)
                    Button("共有ウィンドウを探す", systemImage: "arrow.clockwise") { Task { await capture.refreshWindows() } }
                    Picker("共有画面", selection: $model.selectedWindowID) {
                        Text("選択してください").tag(nil as UInt32?)
                        ForEach(capture.windows.filter { showAllWindows || $0.isPowerPoint }) { window in
                            Text(window.label).tag(Optional(window.id))
                        }
                    }.labelsHidden()
                    DisclosureGroup("その他の画面") {
                        Toggle("PowerPoint以外も表示", isOn: $showAllWindows).font(.caption)
                        Text("PowerPoint以外は表示のみです。").font(.caption)
                    }
                    if capture.sharing {
                        Button("共有を停止") { Task { await model.stopSharing() } }
                    } else {
                        Button("共有を開始") { Task { await model.startSharing() } }
                            .buttonStyle(BrandPrimaryButtonStyle()).disabled(model.selectedWindowID == nil || model.timerFinishing)
                    }
                    if capture.sharing {
                        Text("発表用の画面か確認してください").font(.caption)
                        Button(model.monitoring ? "スライド操作を停止" : "この画面のスライドを操作") {
                            model.monitoring ? model.disableControl() : model.enableControl()
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("iPhone", systemImage: "iphone")
                    Text(link.connectedName ?? "近くのiPhoneから、このMacを選びます。").font(.callout)
                    Button(link.running ? "接続待機を停止" : "接続待機を開始") { link.running ? link.stop() : link.start() }
                }
                Divider()
                GroupBox("発表時間") {
                    PresentationTimerPanel(snapshot: model.state.timer, receivedAt: model.timerReceivedAt,
                        connected: true, canStart: capture.sharing,
                        send: { model.timerAction($0, duration: $1) })
                }
                Button { showCamera = true } label: { Label("カメラの設定・結果", systemImage: "video") }
                PresentationResultsButton(association: presentationResult, camera: camera)
                if camera.phase == .running { Text("\(camera.subject.title) · \(camera.summary.currentQuality)").font(.caption) }
                if showGuide {
                    HStack {
                        Image("BrandMascot").resizable().scaledToFit().frame(width: 60, height: 60)
                        Text(capture.sharing ? (link.connectedName == nil ? "次はiPhoneをつなごう" : "手元のスライドを触ってみよう") : "資料と共有画面を選ぼう").font(.callout)
                    }
                    Button("案内を閉じる") { showGuide = false }.font(.caption)
                } else { Button("案内を表示") { showGuide = true }.font(.caption) }
            }.padding(22)
        }.background(paper, in: RoundedRectangle(cornerRadius: 22))
    }
}
