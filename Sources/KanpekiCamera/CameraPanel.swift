import AVFoundation
import SwiftUI

private enum Palette {
    static let background = Color(red: 217/255, green: 235/255, blue: 213/255)
    static let surface = Color(red: 249/255, green: 1, blue: 230/255)
    static let ink = Color(red: 92/255, green: 102/255, blue: 115/255)
}

/// Camera preparation, live status and results. A presentation host can place this above its slide.
public struct CameraPanel: View {
    @StateObject private var camera: CameraController
    @Environment(\.scenePhase) private var scenePhase
    @State private var subject: CameraSubject = .audience
    @State private var front = false
    @State private var showResult = false
    @State private var confirmEnd = false
    @State private var confirmDelete = false
    @State private var deletingID: UUID?
    @State private var details = false
    private let onContinueWithoutAnalysis: (() -> Void)?

    public init(controller: CameraController = CameraController(), onContinueWithoutAnalysis: (() -> Void)? = nil) {
        _camera = StateObject(wrappedValue: controller)
        self.onContinueWithoutAnalysis = onContinueWithoutAnalysis
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(showResult ? "カメラの振り返り" : camera.phase == .running ? "カメラ分析" : "入力を確認")
                    .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                if showResult {
                    result
                } else if camera.phase == .running {
                    live
                } else {
                    preparation
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background)
        .tint(Palette.ink)
        .preferredColorScheme(.light)
        .confirmationDialog("カメラ分析を終了しますか？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("終了して結果を見る") { camera.stop(); showResult = true }
            Button("続ける", role: .cancel) {}
        }
        .confirmationDialog("このカメラ結果を削除しますか？ 元に戻せません。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("結果を削除", role: .destructive) {
                if let id = deletingID { camera.deleteResult(id: id) }
                showResult = false
            }
            Button("残す", role: .cancel) {}
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            if (phase != .active && camera.phase == .running) || (phase == .background && camera.phase == .preparing) {
                camera.stop(interrupted: true)
            }
            #else
            if phase == .background { camera.stop(interrupted: true) }
            #endif
        }
        .onAppear { subject = camera.subject }
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("映す対象と撮影範囲を確認してください。解析はこの端末で行い、映像や顔画像は保存しません。")
            Picker("撮影対象", selection: $subject) {
                ForEach(CameraSubject.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(camera.phase == .preparing)
            #if os(iOS)
            Toggle("前面カメラを使う", isOn: $front).disabled(camera.phase == .preparing)
            Text("端末を縦向きで固定し、映る方への説明・同意を確認してから開始してください。")
                .font(.callout)
            #else
            Text("Macの標準カメラを使用します。映る方への説明・同意を確認してから開始してください。")
                .font(.callout)
            #endif
            switch camera.phase {
            case .failed(let message): Label(message, systemImage: "exclamationmark.triangle")
            case .interrupted:
                Label("カメラは停止しました。結果を確認するか、撮影範囲を確認して新しく開始できます。", systemImage: "pause.circle")
            case .preparing: ProgressView("カメラを準備中")
            default: EmptyView()
            }
            if camera.phase != .preparing {
                Button(camera.result.id == nil ? "計測状態を確認" : "結果・計測状態を見る") { showResult = true }
            }
            if camera.phase == .preparing {
                Button("キャンセル") { camera.stop() }
            } else {
                Button("撮影して分析を開始") { showResult = false; camera.start(subject: subject, front: front) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text("うなずきは候補として扱います。小さな動きや会話中の揺れには、見落とし・誤検出があります。")
                .font(.footnote)
            if let onContinueWithoutAnalysis {
                Button("分析なしで続ける") { camera.stop(); onContinueWithoutAnalysis() }
            }
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("撮影中 · \(camera.subject.title)", systemImage: "video.fill")
                .font(.headline)
            CameraPreview(session: camera.captureSession)
                .aspectRatio(4/3, contentMode: .fit)
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("撮影範囲のプレビュー")
            Text(camera.summary.currentQuality)
            DisclosureGroup("解析の詳細", isExpanded: $details) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("検出できた顔：\(camera.summary.faceCount.map(String.init) ?? "未計測")")
                    if camera.subject == .presenter {
                        Text("向き先：\(targetName(camera.summary.gazeTarget))")
                        Text("向き先を確認する場合は、各方向を約3秒見続けてください。頭の向きによる推定です。")
                        ForEach(["audience", "notes", "screen"], id: \.self) { target in
                            Button("\(targetName(target))を確認\(camera.summary.calibrated.contains(target) ? " ✓" : "")") {
                                camera.calibrate(target)
                            }.disabled(camera.summary.calibrating != nil)
                        }
                        if let target = camera.summary.calibrating {
                            Text("\(targetName(target))を見続けてください · 残り\(camera.summary.calibrationRemaining, specifier: "%.1f")秒")
                        }
                    }
                    if !camera.summary.warning.isEmpty { Text(camera.summary.warning) }
                }.padding(.top, 8)
            }
            Button("カメラ分析を終了") { confirmEnd = true }.buttonStyle(.bordered)
        }
    }

    private var result: some View {
        let snapshot = camera.result
        let summary = snapshot.summary
        return VStack(alignment: .leading, spacing: 16) {
            Text("おつかれさまでした").font(.title2)
            Text(snapshot.status.message)
            if snapshot.status == .finalizing { ProgressView("カメラ結果を確定中") }
            Text(snapshot.id == nil ? "カメラ" : "カメラ · \(snapshot.subject.title)").font(.headline)
            if summary.observableSeconds == 0 {
                Text("判別できた区間はありません。未計測を0点として評価しません。")
            } else {
                Text("顔の向きを取得できた時間：約\(summary.observableSeconds)秒")
                if snapshot.subject == .audience {
                    Text("うなずき候補のあった時間：\(summary.nodCandidateSeconds)秒")
                        .font(.title3.bold())
                    Text("1秒ごとに候補の有無を集計しています。動作の回数や人数ではありません。")
                        .font(.footnote)
                }
            }
            if summary.missingSeconds > 0 {
                Label("未計測・判別できない区間：約\(summary.missingSeconds)秒", systemImage: "exclamationmark.circle")
            }
            DisclosureGroup("話し方") {
                Text("音声分析は未接続です。フィラー・間・改善候補はまだ表示できません。")
            }
            Text("これはカメラ計測の結果です。発表全体の経過時間や評価ではありません。")
                .font(.footnote)
            Text("結果は端末内で一時的に保持します。新しい分析を開始するか、アプリを終了すると破棄されます。")
                .font(.footnote)
            Button("準備に戻る") { showResult = false }.buttonStyle(.borderedProminent)
            if let id = snapshot.id, snapshot.status != .finalizing {
                Button("結果を削除", role: .destructive) { deletingID = id; confirmDelete = true }
            }
        }
        .padding(20)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func targetName(_ target: String?) -> String {
        switch target {
        case "audience": return "観客"
        case "notes": return "原稿"
        case "screen": return "画面"
        case "away": return "確認した方向の外"
        default: return "未確認"
        }
    }
}

#if os(macOS)
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        return view
    }
    func updateNSView(_ view: PreviewView, context: Context) {}
    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            preview.videoGravity = .resizeAspect
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
#else
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = preview.connection {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
            }
        }
    }
}
#endif
