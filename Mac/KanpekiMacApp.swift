import SwiftUI
import KanpekiCamera

@main struct KanpekiMacApp: App {
    @StateObject private var model = MacModel()
    var body: some Scene {
        WindowGroup("カンペき · Mac") { MacScreen(model: model, capture: model.capture, link: model.link) }
            .defaultSize(width: 1160, height: 790)
    }
}

struct MacScreen: View {
    @ObservedObject var model: MacModel
    @ObservedObject var capture: WindowCapture
    @ObservedObject var link: PeerLink
    @State private var showAllWindows = false
    @StateObject private var camera = CameraController()
    @State private var showCamera = false
    private let accent = Color(red: 92/255, green: 102/255, blue: 115/255)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Image("BrandMascot").resizable().scaledToFit().frame(width: 48, height: 48); Text("カンペき").font(.system(size: 29, weight: .bold)) }
                        Text("スライドを手元に。").font(.caption).foregroundStyle(.secondary)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("1  スライドを選ぶ", systemImage: "macwindow").font(.headline)
                            Text("PowerPointで発表用のウィンドウを開いてください。").font(.caption).foregroundStyle(.secondary)
                            Button("ウィンドウを探す", systemImage: "arrow.clockwise") { Task { await capture.refreshWindows() } }
                            Picker("共有する画面", selection: $model.selectedWindowID) {
                                Text("選択してください").tag(nil as UInt32?)
                                ForEach(capture.windows.filter { showAllWindows || $0.isPowerPoint }) { window in
                                    Text(window.label).tag(Optional(window.id))
                                }
                            }.labelsHidden().frame(maxWidth: .infinity)
                            Toggle("他のアプリも表示（表示のみ）", isOn: $showAllWindows).font(.caption)
                            HStack {
                                Button("共有開始") { Task { await model.startSharing() } }.buttonStyle(.borderedProminent).disabled(model.selectedWindowID == nil)
                                Button("停止") { Task { await model.stopSharing() } }.disabled(!capture.sharing)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("2  iPhoneを接続", systemImage: "iphone.gen3.radiowaves.left.and.right").font(.headline)
                            Text(link.status).font(.caption).textSelection(.enabled)
                            Button(link.running ? "接続を停止" : "接続待機を開始") { link.running ? link.stop() : link.start() }
                            Text("iPhoneでこのMacを選び、Mac側で接続を許可します。").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("3  操作と原稿", systemImage: "text.bubble").font(.headline)
                            Button(model.importing ? "読込中…" : "pptxの原稿を読み込む") { model.importDeck() }.disabled(model.importing)
                            if let deck = model.deck { Text("\(deck.title) · \(deck.slides.count)枚").font(.caption).foregroundStyle(.secondary) }
                            Text("プレビューが発表用スライドであることを確認してから有効にしてください。").font(.caption).foregroundStyle(.secondary)
                            Button(model.monitoring ? "PowerPoint操作を停止" : "PowerPoint操作を有効化") {
                                model.monitoring ? model.disableControl() : model.enableControl()
                            }.disabled(!capture.sharing)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        GroupBox("発表時間") {
                            PresentationTimerPanel(snapshot: model.state.timer, receivedAt: model.timerReceivedAt,
                                connected: true, canStart: capture.sharing,
                                send: { model.timerAction($0, duration: $1) })
                        }
                        Button { showCamera = true } label: { Label("カメラ分析", systemImage: "video") }
                        if camera.phase == .running {
                            Text("\(camera.subject.title) · \(camera.summary.currentQuality)").font(.caption)
                        }
                        Text("切替記録 · \(model.events.count)件").font(.headline)
                        HStack {
                            Button("JSONを書き出す") { model.exportLog() }.disabled(model.events.isEmpty)
                            Button("新規記録") { model.resetLog() }
                        }
                        EmptyView()
                    }
                }.padding(22)
            }.frame(width: 310).background(Color(red: 217/255, green: 235/255, blue: 213/255))
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.state.title).font(.title2.bold()).lineLimit(1)
                        Text(model.state.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                    Label(capture.sharing ? "共有中" : "未共有", systemImage: capture.sharing ? "dot.radiowaves.left.and.right" : "circle")
                        .font(.caption.bold()).foregroundStyle(capture.sharing ? accent : .secondary)
                    PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color(red: 249/255, green: 255/255, blue: 230/255))
                    if let image = capture.image {
                        Image(nsImage: image).resizable().scaledToFit().padding(4)
                    } else {
                        VStack(spacing: 15) {
                            Image("BrandMascot").resizable().scaledToFit().frame(width: 100, height: 100)
                            Text("いつものスライドを、ここに。").font(.title3.bold()).foregroundStyle(accent)
                            Text("左側から共有するウィンドウを選択してください").foregroundStyle(accent.opacity(0.8)).font(.callout)
                        }
                    }
                }.frame(minHeight: 250, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 18) {
                    Button { model.move(.previous) } label: { Label("戻る", systemImage: "chevron.left") }.disabled(!model.state.canControl || model.state.slideIndex == 1)
                    Text(model.state.slideIndex.map { "\($0) / \(model.state.totalSlides)" } ?? "— / —").font(.system(.title3, design: .monospaced)).frame(minWidth: 85)
                    Button { model.move(.next) } label: { Label("次へ", systemImage: "chevron.right") }.buttonStyle(.borderedProminent).disabled(!model.state.canControl || model.state.slideIndex == model.state.totalSlides)
                    Spacer()
                    EmptyView()
                }.controlSize(.large)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("発表者ノート", systemImage: "text.alignleft").font(.headline)
                        Spacer()
                        Text("発表者用画面").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(model.state.notesStatus).font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(model.state.notes.isEmpty ? "対応する原稿がここに表示されます。" : model.state.notes)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).font(.body).lineSpacing(5)
                    }.frame(height: 110)
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
                Text(capture.message).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.padding(24).background(Color(red: 217/255, green: 235/255, blue: 213/255))
        }.frame(minWidth: 950, minHeight: 700).tint(accent).foregroundStyle(accent).preferredColorScheme(.light)
        .sheet(isPresented: $showCamera) {
            VStack {
                HStack { Spacer(); Button("発表画面に戻る") { showCamera = false } }.padding()
                CameraPanel(controller: camera, onContinueWithoutAnalysis: { showCamera = false })
            }.frame(width: 560, height: 650)
        }
        .onDisappear { camera.stop() }
        .onChange(of: model.state.timer?.phase) { _, phase in
            if phase == .ended { camera.stop() }
        }
        .alert("iPhoneからの接続", isPresented: Binding(get: { link.invitationName != nil }, set: { if !$0 { link.respondToInvitation(accept: false) } })) {
            Button("許可") { link.respondToInvitation(accept: true) }
            Button("拒否", role: .cancel) { link.respondToInvitation(accept: false) }
        } message: { Text("\(link.invitationName ?? "iPhone") に共有画面と原稿を送り、スライド操作を許可します。自分の端末名と一致するか確認してください。") }
        .alert("確認が必要です", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
