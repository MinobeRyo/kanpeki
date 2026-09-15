import Foundation

/// Local provenance only. This never transfers camera data or guesses a join after reconnect.
public struct PresentationResultAssociation {
    public enum Phase: String { case ready, running, paused, ended }
    public private(set) var sessionID: UUID?
    public private(set) var elapsedSeconds: Double?
    public private(set) var cameraID: UUID?
    private var previousPhase: Phase?
    private var previousCameraID: UUID?
    private var baseline = CameraSummary()
    public init() {}

    public mutating func observe(sessionID: UUID?, phase: Phase?, elapsedSeconds: Double,
                                 camera: CameraResult, liveSummary: CameraSummary) {
        guard let sessionID, let phase, elapsedSeconds.isFinite, elapsedSeconds >= 0 else {
            self = Self(); return
        }
        if self.sessionID != sessionID {
            self = Self()
            self.sessionID = sessionID
            // The first snapshot may arrive halfway through a presentation.
            previousCameraID = camera.id
        }
        let activeCamera = camera.status == .preparing || camera.status == .collecting
        if phase == .running || phase == .paused {
            let observedStart = previousPhase == .ready && phase == .running
            let newCapture = previousPhase == .running || previousPhase == .paused
            // SwiftUI may coalesce preparing → denied/failed. A genuinely new ID
            // witnessed during this presentation still belongs to this attempt.
            let newAttempt = newCapture && camera.id != nil && camera.id != previousCameraID
            if (activeCamera && observedStart) || newAttempt {
                cameraID = camera.id
                baseline = newAttempt ? CameraSummary() : liveSummary
            }
        }
        if phase == .ended { self.elapsedSeconds = elapsedSeconds }
        previousPhase = phase
        previousCameraID = camera.id
    }

    /// A deletion or a different capture cannot resurrect a stored copy of the result.
    public func cameraResult(from current: CameraResult) -> CameraResult? {
        guard elapsedSeconds != nil, let cameraID, current.id == cameraID else { return nil }
        var result = current
        var summary = current.summary
        summary.sampledSeconds = max(0, summary.sampledSeconds - baseline.sampledSeconds)
        summary.observableSeconds = max(0, summary.observableSeconds - baseline.observableSeconds)
        summary.missingSeconds = max(0, summary.missingSeconds - baseline.missingSeconds)
        summary.nodCandidateSeconds = max(0, summary.nodCandidateSeconds - baseline.nodCandidateSeconds)
        result.update(id: cameraID, status: current.status, summary: summary)
        return result
    }
}
