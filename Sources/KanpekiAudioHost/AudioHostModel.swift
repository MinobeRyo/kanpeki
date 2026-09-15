import Foundation
import AppKit
import CryptoKit
import Darwin

@MainActor public final class AudioHostModel: ObservableObject {
    @Published public private(set) var modelReady = false
    @Published public private(set) var preparing = false
    @Published public private(set) var receiving = false
    @Published public private(set) var starting = false
    @Published public private(set) var addresses: [String] = []
    @Published public private(set) var code = ""
    @Published public private(set) var status = "分析モデルを準備してください。"
    @Published public private(set) var error: String?
    @Published public private(set) var report: HostAudioReport?
    @Published public private(set) var reportID: String?
    private var server: AudioHTTPServer?
    private var generation = UUID()
    private var preparation: Task<Void,Never>?
    private let modelURL: URL
    nonisolated static let modelSHA256 = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
    static let modelDownload = URL(string:"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!

    public convenience init() {
        let url = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("KanpekiAudio",isDirectory:true).appendingPathComponent("ggml-base.bin")
        self.init(modelURL: url)
    }
    init(modelURL: URL) {
        self.modelURL = modelURL
        if FileManager.default.fileExists(atPath:modelURL.path) {
            preparing = true; status = "保存した分析モデルを確認中です。"
            let url = modelURL
            preparation = Task {
                defer { preparing = false }
                let valid = await Task.detached { (try? Self.validateModel(url)) != nil }.value
                guard !Task.isCancelled else { return }
                modelReady = valid; preparing = false
                status = valid ? "モデルの準備ができました。" : "分析モデルを準備し直してください。"
            }
        }
    }
    nonisolated static func validateModel(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        var hash = SHA256(), total = 0
        while let chunk = try handle.read(upToCount:1024*1024), !chunk.isEmpty {
            total += chunk.count
            guard total <= 160 * 1024 * 1024 else { throw AudioHostError.invalid("Whisper baseのモデルではありません。") }
            hash.update(data:chunk)
        }
        let digest = hash.finalize().map { String(format:"%02x",$0) }.joined()
        guard digest == modelSHA256 else { throw AudioHostError.invalid("モデルの内容が一致しません。「モデルを取得」で準備し直してください。") }
    }
    public func downloadModel() {
        guard !preparing, !starting, !receiving else { return }
        preparing = true; error = nil; status = "分析モデルを取得中です（約142MB）。"
        preparation = Task {
            do {
                let (temporary,response) = try await URLSession.shared.download(from:Self.modelDownload)
                defer { try? FileManager.default.removeItem(at:temporary) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw AudioHostError.invalid("モデルを取得できません。ネットワークを確認してください。") }
                try Task.checkCancellation()
                try await install(temporary)
            } catch is CancellationError { status = "モデルの取得を中止しました。" }
            catch { self.error = error.localizedDescription; status = "モデルを準備できませんでした。" }
            preparing = false
        }
    }
    public func chooseModel() {
        guard !preparing, !starting, !receiving else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Whisperの多言語baseモデル（ggml-base.bin）を選んでください。"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let scoped = source.startAccessingSecurityScopedResource()
        preparing = true; error = nil; status = "分析モデルを確認中です。"
        preparation = Task {
            defer { if scoped { source.stopAccessingSecurityScopedResource() }; preparing = false }
            do { try await install(source) }
            catch { self.error = error.localizedDescription; status = "モデルを準備できませんでした。" }
        }
    }
    private func install(_ source: URL) async throws {
        let target = modelURL
        try await Task.detached {
            try Self.validateModel(source)
            let manager = FileManager.default
            try manager.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            let incoming = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".partial")
            defer { try? manager.removeItem(at:incoming) }
            try manager.copyItem(at:source,to:incoming)
            if manager.fileExists(atPath:target.path) { _ = try manager.replaceItemAt(target,withItemAt:incoming) }
            else { try manager.moveItem(at:incoming,to:target) }
        }.value
        try Task.checkCancellation()
        modelReady = true; status = "モデルの準備ができました。"
    }
    public func cancelPreparation() { preparation?.cancel(); status = "モデルの準備を中止しています。" }
    public func start() {
        guard modelReady, !preparing, !starting, !receiving else { return }
        generation = UUID(); let generation = generation
        error = nil; report = nil; reportID = nil; starting = true; status = "音声の受信を開始しています。"
        let model = modelURL
        let server = AudioHTTPServer { recording,events,cancellation in
            do {
                let segments = try WhisperEngine().transcribe(recording.samples,model:model,cancellation:cancellation)
                return AudioMetrics.report(recording,events:events,segments:segments)
            } catch is CancellationError { throw CancellationError() }
            catch { return AudioMetrics.report(recording,events:events,segments:nil,failed:true) }
        }
        self.server = server
        server.onReady = { [weak self, weak server] port in
            Task { @MainActor in
                guard let self, let server, self.generation == generation else { return }
                let addresses = Self.localAddresses().map { "http://\($0):\(port)" }
                guard !addresses.isEmpty else {
                    self.stop(); self.error = "Wi-Fiなどのネットワークに接続してから受信を開始してください。"; return
                }
                self.addresses = addresses; self.code = server.token
                self.starting = false; self.receiving = true; self.status = "iPhoneからの音声を待っています。"
            }
        }
        server.onStatus = { [weak self] text in
            Task { @MainActor in guard let self, self.generation == generation else { return }; self.status = text }
        }
        server.onReport = { [weak self] id,report in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.reportID = id; self.report = report
            }
        }
        server.onFailure = { [weak self] text in
            Task { @MainActor in guard let self, self.generation == generation else { return }; self.stop(); self.error = text }
        }
        server.start()
    }
    public func stop() {
        generation = UUID(); server?.stop(); server = nil
        receiving = false; starting = false; code = ""; addresses = []; report = nil; reportID = nil
        status = "受信を停止しました。Macの結果は削除されました。"
    }
    public func clearDisplayedResult() { report = nil; reportID = nil }
    private static func localAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [(String,String)] = [], cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let entry = current.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating:0,count:Int(NI_MAXHOST))
            guard getnameinfo(address,socklen_t(address.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString:host), name = String(cString:entry.ifa_name)
            guard !value.hasPrefix("169.254."), name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            result.append((name,value))
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
