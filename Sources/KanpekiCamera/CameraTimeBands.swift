import Foundation

/// Capture-relative completed-second buckets. Never a presentation/audio time axis.
public struct CameraTimeBand: Equatable {
    public var startSecond: Int
    public var endSecond: Int
    public var observableSeconds: Int
    public var missingSeconds: Int
    public var nodCandidateSeconds: Int
    public var sampledSeconds: Int { endSecond - startSecond }
}

struct CameraTimeBands {
    static let capacity = 120
    private(set) var width = 10
    private(set) var bands: [CameraTimeBand] = []
    private(set) var sampledSeconds = 0
    private(set) var observableSeconds = 0
    private(set) var missingSeconds = 0
    private(set) var nodCandidateSeconds = 0

    /// Align with the JS engine's 20ms sample-boundary tolerance, not a new clock.
    static func second(atMilliseconds time: Double) -> Int? {
        guard time.isFinite, time >= 0 else { return nil }
        let second = floor((time + 20) / 1000)
        guard second <= Double(Int.max / 4) else { return nil }
        return Int(second)
    }

    mutating func record(second: Int, observable: Bool, nod: Bool) {
        guard second > sampledSeconds, second <= Int.max / 4 else { return }
        // Grow the interval BEFORE filling a gap: work stays bounded even for huge gaps.
        while (second - 1) / width + 1 > Self.capacity {
            width *= 2
            var merged: [CameraTimeBand] = []
            for band in bands {
                let start = (band.startSecond / width) * width
                if merged.last?.startSecond == start {
                    let index = merged.count - 1
                    merged[index].endSecond = band.endSecond
                    merged[index].observableSeconds += band.observableSeconds
                    merged[index].missingSeconds += band.missingSeconds
                    merged[index].nodCandidateSeconds += band.nodCandidateSeconds
                } else {
                    var value = band; value.startSecond = start
                    merged.append(value)
                }
            }
            bands = merged
        }
        let gap = second - sampledSeconds
        let known = observable ? 1 : 0
        append(from: sampledSeconds, to: second - known, observable: false, nod: false)
        if observable { append(from: second - 1, to: second, observable: true, nod: nod) }
        sampledSeconds = second
        observableSeconds += known
        missingSeconds += gap - known
        nodCandidateSeconds += observable && nod ? 1 : 0
    }

    private mutating func append(from start: Int, to end: Int, observable: Bool, nod: Bool) {
        var cursor = start
        while cursor < end {
            let bandStart = (cursor / width) * width
            let next = min(end, bandStart + width)
            if bands.last?.startSecond != bandStart {
                bands.append(CameraTimeBand(startSecond: bandStart, endSecond: cursor,
                    observableSeconds: 0, missingSeconds: 0, nodCandidateSeconds: 0))
            }
            let index = bands.count - 1
            bands[index].endSecond = next
            bands[index].observableSeconds += observable ? next - cursor : 0
            bands[index].missingSeconds += observable ? 0 : next - cursor
            bands[index].nodCandidateSeconds += observable && nod ? 1 : 0
            cursor = next
        }
    }
}
