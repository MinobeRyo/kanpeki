import SwiftUI
import Charts

private enum Brand {
    static let green = Color(red: 217/255, green: 235/255, blue: 213/255)
    static let ivory = Color(red: 249/255, green: 255/255, blue: 230/255)
    static let slate = Color(red: 92/255, green: 102/255, blue: 115/255)
    static let coral = Color(red: 1, green: 87/255, blue: 87/255)
}

struct AudioCaptureView: View {
    @ObservedObject var model: RecorderModel
    var logoName = "Logo"
    var onClose: (() -> Void)? = nil
    @AppStorage("macAddress") private var address = "http://Mac名.local:8765"
    @State private var token = ""
    @State private var confirmDiscard = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        Image(logoName).resizable().scaledToFit().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("声から、次の一歩。").font(.title2.bold())
                            Text(model.identity.presentationID != nil ? "発表に関連する録音・スライド時刻は未同期" : onClose == nil ? "発表の話し方を振り返ろう" : "音声の試験機能・スライド同期は未対応").font(.subheadline)
                        }
                    }
                    if model.phase == .ready || model.phase == .recorded {
                        connectionCard
                    }
                    recordingCard
                    if let message = model.notice { Label(message, systemImage: "info.circle").font(.footnote) }
                    if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout) }
                    if let report = model.report { reportView(report) }
                    Text("音声は指定したMacで処理します。iPhoneの録音は破棄または次回起動時に削除。Macの結果は最長1時間保持します。")
                        .font(.caption).foregroundStyle(Brand.slate)
                }
                .padding(24)
            }
            .background(Brand.green)
            .foregroundStyle(Brand.slate)
            .tint(Brand.slate)
            .navigationTitle("カンペき 音声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("戻る", action: onClose).disabled(model.phase == .requesting)
                    }
                }
            }
            .alert("このiPhoneの録音を破棄しますか？", isPresented: $confirmDiscard) {
                Button("破棄して準備に戻る", role: .destructive) { model.discard() }
                Button("戻る", role: .cancel) { }
            } message: { Text("この録音の再送ができなくなります。Macに送信済みの結果は残ります。") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stopForInterruption() }
            }
        }
        .onDisappear {
            model.stopForInterruption()
            if model.isBusy { model.cancelWaiting() }
        }
        .preferredColorScheme(.light)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Macとつなぐ", systemImage: "laptopcomputer").font(.headline)
            TextField("MacのURL", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .textFieldStyle(.roundedBorder).accessibilityLabel("MacのURL")
            SecureField("接続コード", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Button { Task { await model.check(address: address, token: token) } } label: {
                HStack { if model.checking { ProgressView() }; Text("接続を確認") }
            }.disabled(model.checking)
            if let message = model.connectionMessage { Text(message).font(.footnote) }
            Text("Macで音声分析サーバーを起動し、同じWi-Fiで接続してください。接続前でも録音できます。")
                .font(.caption)
        }.card()
    }

    private var recordingCard: some View {
        VStack(spacing: 20) {
            Text(statusTitle).font(.headline)
            Text(clock(model.elapsed)).font(.system(size: 56, weight: .medium, design: .rounded)).monospacedDigit()
            if model.phase == .recording {
                ProgressView(value: Double(model.level)).tint(Brand.slate).accessibilityLabel("マイク入力レベル")
                Text("音声を取得しています").font(.caption)
                Button { model.stop() } label: { Label("録音を終了", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
            } else if model.isBusy {
                ProgressView()
                if model.phase != .requesting { Button("待機を終了") { model.cancelWaiting() } }
            } else if model.phase == .ready {
                Text("まずは1分、いつものように話してみよう。\n最大15分まで録音できます。")
                    .font(.subheadline).multilineTextAlignment(.center)
                Button { Task { await model.start() } } label: { Label("録音をはじめる", systemImage: "mic.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
            } else {
                if model.phase == .recorded {
                    Button { model.analyze(address: address, token: token) } label: {
                        Label("Macで分析する・再取得", systemImage: "waveform").frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryButton())
                }
                Button("録音を破棄して準備に戻る") { confirmDiscard = true }.font(.subheadline)
            }
        }.frame(maxWidth: .infinity).card()
    }

    private var statusTitle: String {
        switch model.phase {
        case .ready: "発表の練習"
        case .requesting: "マイクを準備しています"
        case .recording: "録音中"
        case .recorded: "録音できました"
        case .sending: "Macへ音声を送っています"
        case .analyzing: "話し方を分析しています"
        case .complete: "おつかれさま！"
        }
    }

    @ViewBuilder private func reportView(_ report: AudioReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("話し方の振り返り").font(.title2.bold())
            HStack(alignment: .top, spacing: 12) {
                metric("話速の目安", value: report.averageCharactersPerMinute.map { String(format: "%.0f", $0) } ?? "未計測", unit: "文字 / 分")
                metric("フィラー候補", value: report.fillerCandidates.map { String($0.count) } ?? "未計測", unit: "回・要確認")
            }
            if let pace = report.pace, !pace.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("話速の推移（推定）").font(.headline)
                    Chart(Array(pace.enumerated()), id: \.offset) { _, item in
                        BarMark(x: .value("開始からの秒数", item.start), y: .value("文字/分", item.charactersPerMinute))
                            .foregroundStyle(Brand.slate)
                    }.frame(height: 150).chartXAxisLabel("開始からの秒数").chartYAxisLabel("文字/分")
                }.card()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("低音量が続いた区間").font(.headline)
                Text("合計 \(report.quietSeconds, specifier: "%.1f") 秒").font(.title3)
                if report.quietIntervals.isEmpty { Text("条件に当てはまる区間はありません。") }
                ForEach(Array(report.quietIntervals.enumerated()), id: \.offset) { _, interval in
                    Text("\(clock(interval.start))–\(clock(interval.end))　\(interval.duration, specifier: "%.1f") 秒")
                }
                Text("小さい声や意図的な間も含まれます。失敗を示すものではありません。").font(.caption)
            }.card()
            if let fillers = report.fillerCandidates, !fillers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("フィラー候補の場所").font(.headline)
                    ForEach(Array(fillers.enumerated()), id: \.offset) { _, filler in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(clock(filler.start))–\(clock(filler.end))　「\(filler.text)」").bold()
                            Text(filler.context).font(.subheadline)
                        }
                    }
                }.card()
            }
            if !report.slides.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("スライドごとの時間").font(.headline)
                    ForEach(Array(report.slides.enumerated()), id: \.offset) { _, item in
                        Text("\(item.slide)枚目　\(item.duration, specifier: "%.1f")秒（\(clock(item.start))〜）")
                    }
                }.card()
            }
            if let transcript = report.transcript, !transcript.isEmpty {
                DisclosureGroup("文字起こしを確認") {
                    ForEach(Array(transcript.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading) {
                            Text(clock(segment.start)).font(.caption).monospacedDigit()
                            Text(segment.text)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }.card()
            }
            DisclosureGroup("結果の読み方・未計測の項目") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.warnings, id: \.self) { Text($0).font(.footnote) }
                }.padding(.top, 12)
            }.card()
        }
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption)
            Text(value).font(.title.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func clock(_ seconds: Double) -> String {
        AudioTimeText.clock(seconds)
    }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(16).foregroundStyle(Brand.ivory)
            .background(Brand.slate.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension View {
    func card() -> some View { padding(20).background(Brand.ivory, in: RoundedRectangle(cornerRadius: 24)) }
}
