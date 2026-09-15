import AppKit
import ScreenCaptureKit
import CoreImage
import Combine

struct CaptureWindow: Identifiable {
    let window: SCWindow
    var id: CGWindowID { window.windowID }
    var label: String { "\(window.owningApplication?.applicationName ?? "App") — \(window.title ?? "タイトルなし")" }
    var isPowerPoint: Bool { window.owningApplication?.bundleIdentifier.lowercased() == "com.microsoft.powerpoint" }
}

final class WindowCapture: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var windows: [CaptureWindow] = []
    @Published var image: NSImage?
    @Published var sharing = false
    @Published var message = "「ウィンドウを探す」で画面収録を許可してください"
    var onJPEG: ((Data) -> Void)?
    var onStopped: (() -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "kanpeki.capture", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastTime: TimeInterval = 0
    private var cachedJPEG: Data?

    @MainActor func refreshWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            windows = content.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 160 && $0.frame.height > 100
            }.map(CaptureWindow.init).sorted { $0.label < $1.label }
            message = windows.isEmpty ? "共有できるウィンドウがありません。スライドショーを開いてください" : "発表用スライドのウィンドウを選んでください（ノート表示画面に注意）"
        } catch { message = "画面取得に失敗しました。画面収録の許可を確認してください: \(error.localizedDescription)" }
    }

    @MainActor func start(window: CaptureWindow) async {
        await stop()
        queue.sync { cachedJPEG = nil; lastTime = 0 }
        let filter = SCContentFilter(desktopIndependentWindow: window.window)
        let config = SCStreamConfiguration()
        let ratio = window.window.frame.height / max(1, window.window.frame.width)
        config.width = 1280
        config.height = max(2, Int(1280 * ratio))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            self.stream = stream
            try await stream.startCapture()
            sharing = true
            message = "共有中 · 最大5fps / JPEG · 音声なし"
        } catch {
            self.stream = nil
            message = "共有を開始できません: \(error.localizedDescription)"
        }
    }

    @MainActor func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        sharing = false
        image = nil
        message = "共有停止"
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.sharing = false
            self.stream = nil
            self.image = nil
            self.message = "共有が停止しました: \(error.localizedDescription)"
            self.onStopped?()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTime >= 0.19 else { return }
        lastTime = now
        if status == SCFrameStatus.idle.rawValue, let jpeg = cachedJPEG {
            DispatchQueue.main.async { [weak self, weak stream] in
                guard let self, self.stream === stream, self.sharing else { return }
                self.onJPEG?(jpeg)
            }
            return
        }
        guard status == SCFrameStatus.complete.rawValue, let pixel = buffer.imageBuffer else { return }
        let ci = CIImage(cvPixelBuffer: pixel)
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        var jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.55])
        if (jpeg?.count ?? Int.max) > WireCodec.maxFrameBytes {
            jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.25])
        }
        guard let jpeg, jpeg.count <= WireCodec.maxFrameBytes else { return }
        cachedJPEG = jpeg
        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self, self.stream === stream, self.sharing else { return }
            self.image = NSImage(cgImage: cg, size: .zero)
            self.onJPEG?(jpeg)
        }
    }
}
