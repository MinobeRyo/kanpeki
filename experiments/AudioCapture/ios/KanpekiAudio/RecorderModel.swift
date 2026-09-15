import AVFoundation
import Combine
import SwiftUI

@MainActor
final class RecorderModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum Phase { case ready, requesting, recording, recorded, sending, analyzing, complete }
    @Published var phase = Phase.ready
    @Published var elapsed = 0.0
    @Published var level: Float = 0
    @Published var error: String?
    @Published var notice: String?
    @Published var report: AudioReport?
    @Published var connectionMessage: String?
    @Published var checking = false
    private var idleTimerWasDisabled: Bool?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    @Published private(set) var identity = AudioRecordingIdentity()
    private var pendingStartID: UUID?
    private var operationID = UUID()
    private var slideEvents: [SlideEvent] = []
    private var operation: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    var isBusy: Bool { [.requesting, .sending, .analyzing].contains(phase) }
    var hasRecording: Bool { fileURL != nil && phase != .recording && phase != .requesting }

    override init() {
        super.init()
        // Recoverable audio lasts only for this run. Purge abandoned app-owned files on launch.
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.recordingDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "wav" { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static var recordingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kanpeki-recordings", isDirectory: true)
    }

    func check(address: String, token: String) async {
        checking = true
        connectionMessage = nil
        defer { checking = false }
        do {
            let health = try await AudioAPI(address: address, token: token).health()
            connectionMessage = health.transcriptionReady ? "Macにつながりました。音声分析を使えます。" : "Macにつながりました。文字起こしモデルは未設定です。"
        } catch { connectionMessage = error.localizedDescription }
    }

    func start(presentationID: UUID? = nil) async {
        guard phase == .ready else { return }
        identity.begin(presentationID: presentationID)
        let attempt = identity.recordingID!
        pendingStartID = attempt
        phase = .requesting
        error = nil; notice = nil; report = nil; slideEvents = []
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard pendingStartID == attempt, phase == .requesting else { return }
        pendingStartID = nil
        guard allowed else {
            error = "マイクが許可されていません。iPhoneの設定からマイクを許可してください。"
            phase = .ready
            return
        }
        guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { phase = .ready; return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            try FileManager.default.createDirectory(at: Self.recordingDirectory, withIntermediateDirectories: true)
            let url = Self.recordingDirectory.appendingPathComponent(attempt.uuidString).appendingPathExtension("wav")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: 900) else {
                try? FileManager.default.removeItem(at: url)
                throw AudioAPIError.message("録音を開始できませんでした。マイクを確認してください。")
            }
            self.recorder = recorder; fileURL = url; elapsed = 0; phase = .recording
            interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor in
                    guard let self, self.identity.recordingID == attempt else { return }
                    self.stopForInterruption()
                }
            }
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.identity.recordingID == attempt else { return }
                    self.updateMeter()
                }
            }
        } catch {
            self.error = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false)
            phase = .ready
        }
    }

    private func updateMeter() {
        guard phase == .recording, let recorder else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 60) / 60))
    }

    func stop() {
        guard phase == .recording else { return }
        elapsed = recorder?.currentTime ?? elapsed
        phase = .recorded
        recorder?.stop()
        finishCapture()
    }

    private func finishCapture() {
        timer?.invalidate(); timer = nil; level = 0
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if let previous = idleTimerWasDisabled {
            UIApplication.shared.isIdleTimerDisabled = previous
            idleTimerWasDisabled = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func stopForInterruption() {
        if phase == .requesting {
            pendingStartID = nil
            phase = .ready
            notice = "録音の開始を取り消しました。録音はしていません。"
            return
        }
        guard phase == .recording else { return }
        stop()
        notice = "録音を中断しました。中断までの音声を分析できます。再開する場合は新しく録音してください。"
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard AudioRecordingIdentity.isCurrentRecorder(recorder, current: self.recorder), self.phase == .recording else { return }
            self.elapsed = max(self.elapsed, recorder.currentTime)
            self.phase = .recorded
            self.finishCapture()
            self.notice = flag ? "録音を終了しました（上限15分）。" : "録音が中断されました。取得できた音声を送信できます。"
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard AudioRecordingIdentity.isCurrentRecorder(recorder, current: self.recorder) else { return }
            self.stopForInterruption()
            self.error = "音声の保存中にエラーが起きました。取得できた音声の送信を試すか、新しく録音してください。"
        }
    }

    func analyze(address: String, token: String) {
        guard let fileURL, let sessionID = identity.recordingID, phase == .recorded || phase == .complete else { return }
        let attempt = UUID()
        operationID = attempt
        error = nil
        phase = .sending
        operation = Task {
            do {
                let api = try AudioAPI(address: address, token: token)
                let audio = try Data(contentsOf: fileURL)
                try await api.submit(id: sessionID, audio: audio, slides: slideEvents)
                guard operationID == attempt, identity.recordingID == sessionID else { return }
                phase = .analyzing
                for _ in 0..<360 {
                    try Task.checkCancellation()
                    let job = try await api.result(id: sessionID)
                    try Task.checkCancellation()
                    guard operationID == attempt, identity.recordingID == sessionID else { return }
                    if job.status == "complete", let report = job.report {
                        self.report = report; phase = .complete
                        return
                    }
                    if job.status == "failed" { throw AudioAPIError.message(job.error ?? "分析に失敗しました。") }
                    try await Task.sleep(for: .seconds(2))
                }
                throw AudioAPIError.message("分析に時間がかかっています。Macの状態を確認してから、もう一度結果を取得してください。")
            } catch is CancellationError {
                guard operationID == attempt else { return }
                phase = .recorded
            } catch {
                guard operationID == attempt else { return }
                self.error = error.localizedDescription
                phase = .recorded
            }
        }
    }

    func cancelWaiting() {
        operation?.cancel()
        operationID = UUID()
        if phase == .sending || phase == .analyzing { phase = .recorded }
        if phase == .requesting { stopForInterruption() }
        notice = "待機を終了しました。Macで受信済みの分析は続きます。同じ録音を再送して結果を取得できます。"
    }

    /// Only ends an explicitly attached recording; never attaches an older trial.
    func observePresentation(id: UUID?, active: Bool) {
        guard identity.presentationID != nil else { return }
        if !active || !identity.belongs(to: id) { stopForInterruption() }
    }

    /// Integration point: pass the capture-relative timestamp, not network arrival time.
    /// The standalone recorder supplies no slides; absence is represented as unmeasured.
    func recordSlideChange(slide: Int, at recordingSeconds: Double) {
        guard phase == .recording, slide > 0, recordingSeconds.isFinite,
              recordingSeconds >= 0, recordingSeconds <= (recorder?.currentTime ?? 0),
              recordingSeconds > (slideEvents.last?.at ?? -1) else { return }
        slideEvents.append(SlideEvent(at: recordingSeconds, slide: slide))
    }

    func discard() {
        guard !isBusy, phase != .recording else { return }
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil; recorder = nil; report = nil; elapsed = 0; error = nil; notice = nil; phase = .ready
        identity = AudioRecordingIdentity()
        pendingStartID = nil
        operationID = UUID()
    }
}
