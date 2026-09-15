import Foundation

/// Fixed session-clock buckets avoid losing an entire capture frame to tiny timer jitter.
struct AnalysisCadence {
    private var next = 0.0
    mutating func reset() { next = 0 }
    mutating func shouldProcess(seconds: Double, fps: Double) -> Bool {
        guard seconds.isFinite, seconds >= 0, fps.isFinite, fps > 0,
              seconds + 0.000001 >= next else { return false }
        next = (floor(seconds * fps + 0.000001) + 1) / fps
        return true
    }
}
