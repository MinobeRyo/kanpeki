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
    @Published private(set) var needsScreenPermission = !CGPreflightScreenCaptureAccess()
    @Published private(set) var refreshing = false
    @Published var message = "画面収録を許可して共有画面を選んでください"
    var onJPEG: ((Data) -> Void)?
    var onStopped: (() -> Void)?
    var usesObservedSnapshots = false
    private var snapshotFilter: SCContentFilter?
    private var snapshotConfiguration: SCStreamConfiguration?
    private var lifecycleID = UUID()
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "kanpeki.capture", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastTime: TimeInterval = 0
    private var cachedJPEG: Data?

    @MainActor func refreshWindows(requestPermission: Bool = false) async {
        guard !refreshing else { return }
        needsScreenPermission = !CGPreflightScreenCaptureAccess()
        if needsScreenPermission {
            guard requestPermission else { return }
            _ = CGRequestScreenCaptureAccess()
            needsScreenPermission = !CGPreflightScreenCaptureAccess()
            guard !needsScreenPermission else {
                message = "画面収録の許可が必要です。システム設定で許可した後、再読み込みしてください。"
                return
            }
        }
        refreshing = true
        defer { refreshing = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            windows = content.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 160 && $0.frame.height > 100
            }.map(CaptureWindow.init).sorted { $0.label < $1.label }
            message = windows.isEmpty ? "共有できるウィンドウがありません。スライドショーを開いてください" : "発表用スライドのウィンドウを選んでください（ノート表示画面に注意）"
        } catch {
            needsScreenPermission = !CGPreflightScreenCaptureAccess()
            message = "画面取得に失敗しました。画面収録の許可を確認してください: \(error.localizedDescription)"
        }
    }

    @MainActor func openScreenPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor func start(window: CaptureWindow) async {
        let attempt = UUID()
        lifecycleID = attempt
        if let previous = clearStreamState() { try? await previous.stopCapture() }
        guard lifecycleID == attempt else { return }
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
            guard lifecycleID == attempt, self.stream === stream else {
                try? await stream.stopCapture()
                return
            }
            sharing = true
            snapshotFilter = filter
            snapshotConfiguration = config
            message = "共有中 · 最大5fps / JPEG · 音声なし"
        } catch {
            guard lifecycleID == attempt else { return }
            _ = clearStreamState()
            needsScreenPermission = !CGPreflightScreenCaptureAccess()
            message = "共有を開始できません: \(error.localizedDescription)"
        }
    }

    @MainActor func stop() async {
        lifecycleID = UUID()
        // Clear before suspension: a late stop completion must not clear a newer stream.
        if let previous = clearStreamState() { try? await previous.stopCapture() }
    }

    @MainActor private func clearStreamState() -> SCStream? {
        let previous = stream
        stream = nil
        snapshotFilter = nil
        snapshotConfiguration = nil
        sharing = false
        image = nil
        message = "共有停止"
        return previous
    }

    /// A fresh request; never re-labels an idle stream buffer after a page observation.
    @MainActor func snapshot() async throws -> Data? {
        guard sharing, let stream, let filter = snapshotFilter, let config = snapshotConfiguration else { return nil }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard self.stream === stream, sharing else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        for quality in [0.55, 0.25, 0.1] {
            if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]),
               !jpeg.isEmpty, jpeg.count <= WireCodec.maxFrameBytes { return jpeg }
        }
        return nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.stream === stream else { return }
            self.lifecycleID = UUID()
            _ = self.clearStreamState()
            self.message = "共有が停止しました: \(error.localizedDescription)"
            self.onStopped?()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !usesObservedSnapshots else { return }
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
