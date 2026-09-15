import SwiftUI

/// Offline design walkthrough. Never publishes samples to the live peer session.
struct ScreenReview: View {
    enum Step: String, CaseIterable, Identifiable {
        case connect = "接続", prepare = "準備", live = "発表", fixed = "固定", results = "結果"
        var id: String { rawValue }
    }
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .connect
        @State private var page = 1
    @State private var pointer: CGPoint?
    @State private var dragged = false
    @State private var showTranslation = false
    @State private var showTimeAdjustment = false
    @State private var sampleDuration: Double = 300
    @State private var resultTab = 0
    private let ink = Color(red: 92/255, green: 102/255, blue: 115/255)
    private let paper = Color(red: 249/255, green: 255/255, blue: 230/255)
    private let mint = Color(red: 217/255, green: 235/255, blue: 213/255)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 32, height: 32)
                VStack(alignment: .leading) {
                    Text("画面構成を試す").font(.headline)
                    Text("サンプル・通信／録音なし").font(.caption2)
                }
                Spacer()
                Menu {
                    ForEach(Step.allCases) { destination in
                        Button(destination.rawValue) { step = destination }
                    }
                    Divider()
                    Button("翻訳・原稿チェック") { showTranslation = true }
                    Button("閉じる") { dismiss() }
                } label: {
                    Label(step.rawValue, systemImage: "ellipsis.circle").frame(minHeight: 44)
                }.accessibilityLabel("画面メニュー")
            }
            Group {
                switch step {
                case .connect: connection
                case .prepare: preparation
                case .live: live
                case .fixed: fixed
                case .results: results
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16).background(mint.ignoresSafeArea()).foregroundStyle(ink)
        .tint(ink).preferredColorScheme(.light)
        .sheet(isPresented: $showTimeAdjustment) {
            TimeAdjustmentFlow(initialSeconds: sampleDuration, isSample: true) { seconds in
                sampleDuration = seconds
                return true
            }
        }
        .sheet(isPresented: $showTranslation) {
            VStack(alignment: .leading, spacing: 24) {
                Text("翻訳・原稿チェック").font(.title2.bold())
                Text("準備中です")
                Button("閉じる") { showTranslation = false }.buttonStyle(BrandPrimaryButtonStyle())
            }.padding(24)
            #if os(macOS)
            .frame(width: 400, height: 260)
            #endif
        }
        .onChange(of: step) { _, _ in pointer = nil; dragged = false }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 700, idealHeight: 800)
        #endif
    }

    private var connection: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)
                    Image("BrandMascot").resizable().scaledToFit().frame(width: 100, height: 100)
                    Text("Macにつなぐ").font(.largeTitle.bold())
                    Button { step = .prepare } label: {
                        Label("デモのMac", systemImage: "desktopcomputer").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(BrandPrimaryButtonStyle())
                    Text("接続の見本").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 24)
                }.frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("発表の準備").font(.largeTitle.bold())
                sampleSlide.interactive(false).aspectRatio(16/9, contentMode: .fit)
                HStack { Text("研究発表.pptx").font(.headline); Spacer(); Text("3枚").font(.caption) }
                VStack(alignment: .leading, spacing: 16) {
                    Button { showTimeAdjustment = true } label: {
                        HStack {
                            Text("時間を調整"); Spacer()
                            Text(PresentationTimerText.time(sampleDuration)).monospacedDigit()
                            Image(systemName: "chevron.right")
                        }.frame(minHeight: 44)
                    }
                }.padding(20).background(paper, in: RoundedRectangle(cornerRadius: 20))
                helper("準備ができたら、ここだよ")
                Button { step = .live } label: { Text("発表画面へ").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(BrandPrimaryButtonStyle())
            }
        }
    }

    private var live: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 3) {
                        Text("残り時間の見本").font(.caption)
                        Text(PresentationTimerText.time(sampleDuration)).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                    }.padding(.top, 8)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("原稿").font(.caption.bold())
                        Text(["まず、研究の背景を紹介します。", "ここで、研究の結果を紹介します。", "最後に、今後の課題をまとめます。"][page - 1])
                            .font(.title2).lineSpacing(8).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(22).background(paper, in: RoundedRectangle(cornerRadius: 20))
                    Label("音声分析は未接続", systemImage: "mic.slash").font(.caption)
                }
            }
            HStack {
                Text("\(page) / 3").monospacedDigit()
                Spacer()
                Button("終了して結果へ") { step = .results }.font(.callout)
            }
            sampleSlide.interactive(true).aspectRatio(16/9, contentMode: .fit)
                .accessibilityHint("右をタップで進み、左で戻ります。指を動かすと画面内のポインターが移動します。")
        }
    }

    private var fixed: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("固定カメラ").font(.largeTitle.bold())
                Image(systemName: "person.3.sequence").font(.system(size: 62)).padding(60)
                    .frame(maxWidth: .infinity).background(paper, in: RoundedRectangle(cornerRadius: 24))
                Text("カメラ映像の配置見本").font(.headline)
                Text("観測対象：視聴者").font(.callout)
                Text("撮影なし・配置の見本")
                    .font(.caption).multilineTextAlignment(.center)
                helper("スマホを動かない場所に置こう")
                Button("発表画面へ戻る") { step = .live }.buttonStyle(BrandPrimaryButtonStyle())
            }
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image("BrandMascot").resizable().scaledToFit().frame(width: 64, height: 64)
                    Text("おつかれさま！").font(.title.bold())
                }
                Text("サンプル結果・実測ではありません").font(.caption)
                Picker("結果の種類", selection: $resultTab) {
                    Text("話し方").tag(0); Text("カメラ").tag(1)
                }.pickerStyle(.menu)
                if resultTab == 0 {
                    resultRow("フィラー候補", value: "8回")
                    resultRow("無音の候補", value: "2か所")
                    Text("次は、結果を伝える前に一呼吸。").font(.title3.bold())
                    Text("分析は未接続です").font(.caption)
                } else {
                    resultRow("頷きの候補", value: "記録例")
                    resultRow("顔の向き", value: "測定できない区間あり")
                    Text("理解度・感情は判定しません").font(.callout)
                }
                Button { step = .prepare } label: { Text("もう一度準備する").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(BrandPrimaryButtonStyle())
            }
        }
    }

    private func resultRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).bold() }
            .padding(20).background(paper, in: RoundedRectangle(cornerRadius: 16))
    }

    private func helper(_ text: String) -> some View {
        Image("BrandMascot").resizable().scaledToFit().frame(width: 56, height: 56)
            .accessibilityHidden(true)
    }

    private var sampleSlide: ReviewSlide {
        ReviewSlide(page: $page, pointer: $pointer, dragged: $dragged, ink: ink, paper: paper)
    }
}

private struct ReviewSlide: View {
    @Binding var page: Int
    @Binding var pointer: CGPoint?
    @Binding var dragged: Bool
    let ink: Color
    let paper: Color
    var enabled = false
    @State private var started: Date?
    func interactive(_ value: Bool) -> Self { var copy = self; copy.enabled = value; return copy }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16).fill(paper)
                VStack(alignment: .leading, spacing: 12) {
                    Text(["研究の背景", "研究の結果", "今後の課題"][page - 1]).font(.title3.bold())
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.2 + Double(i) * 0.15))
                            .frame(width: max(0, geo.size.width - 48) * [0.6, 0.85, 0.7][i], height: 14)
                    }
                }.padding(24)
                if let pointer {
                    Circle().fill(ink).frame(width: 13, height: 13).position(pointer)
                        .allowsHitTesting(false)
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard enabled else { return }
                    if started == nil { started = value.time }
                    if hypot(value.translation.width, value.translation.height) > 8 { dragged = true }
                    if dragged {
                        pointer = CGPoint(x: min(max(value.location.x, 0), geo.size.width), y: min(max(value.location.y, 0), geo.size.height))
                    }
                }.onEnded { value in
                    defer { dragged = false; started = nil; pointer = nil }
                    guard enabled, !dragged, value.time.timeIntervalSince(started ?? value.time) < 0.5 else { return }
                    page = min(3, max(1, page + (value.location.x < geo.size.width/2 ? -1 : 1)))
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("サンプルスライド、\(page)枚目")
                .accessibilityAction(named: "次のスライド") { if enabled { page = min(3, page + 1) } }
                .accessibilityAction(named: "前のスライド") { if enabled { page = max(1, page - 1) } }
        }
    }
}

/// Keeps the primary action readable in both active and inactive Mac windows.
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Color(red: 92/255, green: 102/255, blue: 115/255), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
