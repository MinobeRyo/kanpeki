import AVFoundation
import Combine
import SwiftUI
import Vision
#if os(iOS)
import CoreMotion
import UIKit
#endif

/// Capture and analysis are serial; observable UI changes are published on the main queue.
public final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    @Published public private(set) var phase: CameraPhase = .stopped
    @Published public private(set) var summary = CameraSummary()
    @Published public private(set) var subject: CameraSubject = .audience
    @Published public private(set) var result = CameraResult()
    public let captureSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "kanpeki.camera", qos: .userInitiated)
    private var analysis: AnalysisSession?
    private var active = false
    private var requestID = UUID()
    private var activeID = UUID()
    private let runGate = CameraRunGate()
    private var startTime = 0.0
    private var lastFrame = 0.0
    private var lastPublished = -Double.infinity
    private var cadence = AnalysisCadence()
    private var heartbeat: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    #if os(iOS)
    private let motion = CMMotionManager()
    private var previousIdleTimer = false
    #endif

    private func observeInterruptions(id: UUID) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: captureSession, queue: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.runGate.accepts(id) else { return }
                    self.stop(interrupted: true)
                }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        heartbeat?.cancel()
    }

    /// Invoke UI actions on the main thread. Cancellation also invalidates pending permission requests.
    public func start(subject: CameraSubject, front: Bool) {
        guard phase != .preparing && phase != .running else { return }
        let id = UUID()
        requestID = id
        runGate.begin(id)
        self.subject = subject
        result.begin(id: id, subject: subject)
        phase = .preparing
        summary = CameraSummary()
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                guard allowed else {
                    self.runGate.invalidate(id)
                    self.result.update(id: id, status: .permissionDenied)
                    self.phase = .failed("カメラを使用できません。システム設定で許可してください。")
                    return
                }
                self.queue.async { self.configure(subject: subject, front: front, id: id) }
            }
        }
    }

    private func configure(subject: CameraSubject, front: Bool, id: UUID) {
        // The permission callback may have queued configuration before UI cancellation.
        guard runGate.accepts(id) else { return }
        activeID = id
        do {
            captureSession.beginConfiguration()
            do {
                defer { captureSession.commitConfiguration() }
                captureSession.inputs.forEach(captureSession.removeInput)
                captureSession.outputs.forEach(captureSession.removeOutput)
                if captureSession.canSetSessionPreset(.hd1280x720) { captureSession.sessionPreset = .hd1280x720 }
                #if os(iOS)
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
                #else
                let device = AVCaptureDevice.default(for: .video)
                #endif
                guard let device else { throw CameraError.message("利用できるカメラがありません") }
                let input = try AVCaptureDeviceInput(device: device)
                guard captureSession.canAddInput(input) else { throw CameraError.message("カメラ入力を開けません") }
                captureSession.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                guard captureSession.canAddOutput(output) else { throw CameraError.message("映像を取得できません") }
                captureSession.addOutput(output)
                guard runGate.attach(output, to: id) else { return }
                if let connection = output.connection(with: .video) {
                    #if os(iOS)
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    #endif
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }
                analysis = try AnalysisSession(subject: subject)
            }
            startTime = ProcessInfo.processInfo.systemUptime
            lastFrame = 0
            lastPublished = -.infinity
            cadence.reset()
            guard runGate.accepts(id) else { tearDown(); return }
            active = true
            observeInterruptions(id: id)
            #if os(iOS)
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates()
            #endif
            captureSession.startRunning()
            // startRunning is synchronous: an in-flight call cannot be preempted,
            // but a cancelled run must be stopped before publishing/processing input.
            guard runGate.accepts(id) else { tearDown(); return }
            guard captureSession.isRunning else { throw CameraError.message("カメラを開始できません") }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: .milliseconds(500))
            timer.setEventHandler { [weak self] in
                guard let self, self.active, self.runGate.accepts(id), self.activeID == id,
                      self.elapsed - self.lastFrame > 1100 else { return }
                do {
                    if let value = try self.analysis?.process(faces: [], at: self.elapsed, missing: true) { self.publish(value) }
                } catch { self.fail(error) }
            }
            heartbeat = timer
            timer.resume()
            DispatchQueue.main.async {
                guard self.requestID == id else { return }
                #if os(iOS)
                self.previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
                self.phase = .running
                self.result.update(id: id, status: .collecting)
            }
        } catch { fail(error) }
    }

    public func stop(interrupted: Bool = false) {
        guard phase == .running || phase == .preparing else { return }
        let sessionID = requestID
        runGate.invalidate(sessionID)
        let wasRunning = phase == .running
        let finalStatus: CameraResult.Status = wasRunning ? (interrupted ? .inputInterrupted : .completed) : .cancelled
        result.update(id: sessionID, status: .finalizing, summary: summary)
        requestID = UUID()
        let stoppedID = requestID
        #if os(iOS)
        if phase == .running { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        #endif
        phase = interrupted ? .interrupted : .stopped
        queue.async {
            let finalSummary = self.analysis?.summary
            self.tearDown()
            DispatchQueue.main.async {
                guard self.requestID == stoppedID else { return }
                if let finalSummary { self.summary = finalSummary }
                self.result.update(id: sessionID, status: finalStatus, summary: self.summary)
            }
        }
    }

    /// The caller must confirm deletion and pass the displayed session identity.
    public func deleteResult(id: UUID) {
        guard result.delete(id: id) else { return }
        requestID = UUID()
        summary = CameraSummary()
        phase = .stopped
    }

    private func tearDown() {
        active = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        heartbeat?.cancel()
        heartbeat = nil
        captureSession.stopRunning()
        #if os(iOS)
        motion.stopDeviceMotionUpdates()
        #endif
        analysis = nil
    }

    public func calibrate(_ target: String) {
        guard phase == .running, summary.calibrating == nil else { return }
        summary.calibrating = target
        summary.calibrationRemaining = 3
        let id = requestID
        queue.async {
            guard self.active, self.activeID == id, self.runGate.accepts(id) else { return }
            do { try self.analysis?.calibrate(target, at: self.elapsed) }
            catch { self.fail(error) }
        }
    }

    private var elapsed: Double { (ProcessInfo.processInfo.systemUptime - startTime) * 1000 }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active, runGate.accepts(activeID, input: output),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = elapsed
        let thermal = ProcessInfo.processInfo.thermalState
        let fps = thermal == .serious || thermal == .critical ? 6.0 : 25.0
        guard cadence.shouldProcess(seconds: time / 1000, fps: fps) else { return }
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            let observations = try VisionFaceAnalyzer.perform(VNDetectFaceRectanglesRequest(), using: handler)
            var faces = observations.map(VisionFaceAdapter.normalized)
            try FaceLandmarkFeatures.attach(to: &faces, observations: observations, handler: handler,
                                           imageWidth: Double(CVPixelBufferGetWidth(buffer)),
                                           imageHeight: Double(CVPixelBufferGetHeight(buffer)))
            var moving = false
            #if os(iOS)
            if let m = motion.deviceMotion {
                let r = m.rotationRate, a = m.userAcceleration
                moving = sqrt(r.x*r.x + r.y*r.y + r.z*r.z) > 0.15 || sqrt(a.x*a.x + a.y*a.y + a.z*a.z) > 0.08
            }
            #endif
            lastFrame = time
            if var value = try analysis?.process(faces: faces, at: time, moving: moving), time - lastPublished >= 250 {
                lastPublished = time
                if thermal == .serious || thermal == .critical { value.warning = "端末の負荷に合わせて解析頻度を下げています" }
                publish(value)
            }
        } catch { fail(error) }
    }

    private func publish(_ value: CameraSummary) {
        let id = activeID
        DispatchQueue.main.async { if self.requestID == id && self.phase == .running { self.summary = value } }
    }

    private func fail(_ error: Error) {
        let id = activeID
        runGate.invalidate(id)
        let finalSummary = analysis?.summary
        tearDown()
        DispatchQueue.main.async {
            guard self.requestID == id else { return }
            #if os(iOS)
            if self.phase == .running { UIApplication.shared.isIdleTimerDisabled = self.previousIdleTimer }
            #endif
            self.phase = .failed(error.localizedDescription)
            if let finalSummary { self.summary = finalSummary }
            self.result.update(id: id, status: .failed(error.localizedDescription), summary: self.summary)
        }
    }
}
