import XCTest
@testable import KanpekiCamera

final class CameraTimeBandTests: XCTestCase {
    func testJSBoundaryToleranceCountsOneSecondOnlyOnce() {
        var value = CameraTimeBands()
        for time in [979.0, 980, 999, 1000, 1019, 1020] {
            value.record(second: CameraTimeBands.second(atMilliseconds: time)!, observable: true, nod: true)
        }
        XCTAssertEqual(value.sampledSeconds, 1)
        XCTAssertEqual(value.observableSeconds, 1)
        XCTAssertEqual(value.nodCandidateSeconds, 1)
        value.record(second: CameraTimeBands.second(atMilliseconds: 1980)!, observable: true, nod: true)
        XCTAssertEqual(value.sampledSeconds, 2)
        XCTAssertEqual(value.nodCandidateSeconds, 2)
    }

    func testUnknownGapIsNotZeroReaction() {
        var value = CameraTimeBands()
        value.record(second: 1, observable: true, nod: true)
        value.record(second: 30, observable: false, nod: true)
        XCTAssertEqual(value.bands.count, 3)
        XCTAssertEqual(value.bands[1].observableSeconds, 0)
        XCTAssertEqual(value.bands[1].missingSeconds, 10)
        XCTAssertEqual(value.bands[1].nodCandidateSeconds, 0)
        XCTAssertEqual(value.missingSeconds, 29)
        XCTAssertEqual(value.nodCandidateSeconds, 1)
    }

    func testCompactionPreservesAllIntervalsAndTotals() {
        var value = CameraTimeBands()
        for second in 1...3600 {
            value.record(second: second, observable: second % 5 != 0, nod: second % 3 == 0)
        }
        XCTAssertLessThanOrEqual(value.bands.count, CameraTimeBands.capacity)
        XCTAssertGreaterThan(value.width, 10)
        XCTAssertEqual(value.bands.first?.startSecond, 0)
        XCTAssertEqual(value.bands.last?.endSecond, 3600)
        for (left, right) in zip(value.bands, value.bands.dropFirst()) { XCTAssertEqual(left.endSecond, right.startSecond) }
        XCTAssertEqual(value.bands.reduce(0) { $0 + $1.sampledSeconds }, 3600)
        XCTAssertEqual(value.bands.reduce(0) { $0 + $1.observableSeconds }, value.observableSeconds)
        XCTAssertEqual(value.bands.reduce(0) { $0 + $1.missingSeconds }, value.missingSeconds)
        XCTAssertEqual(value.bands.reduce(0) { $0 + $1.nodCandidateSeconds }, value.nodCandidateSeconds)
        XCTAssertEqual(value.observableSeconds + value.missingSeconds, 3600)
    }

    func testHugeGapRemainsBoundedWithoutDroppingDuration() {
        var value = CameraTimeBands()
        value.record(second: 1, observable: true, nod: true)
        value.record(second: 1_000_000_000, observable: true, nod: true)
        XCTAssertLessThanOrEqual(value.bands.count, 120)
        XCTAssertEqual(value.sampledSeconds, 1_000_000_000)
        XCTAssertEqual(value.observableSeconds, 2)
        XCTAssertEqual(value.missingSeconds, 999_999_998)
        XCTAssertEqual(value.nodCandidateSeconds, 2)
        XCTAssertEqual(value.bands.reduce(0) { $0 + $1.sampledSeconds }, value.sampledSeconds)
    }

    func testInvalidAndOutOfOrderSecondsDoNotMutate() {
        XCTAssertNil(CameraTimeBands.second(atMilliseconds: .nan))
        XCTAssertNil(CameraTimeBands.second(atMilliseconds: .infinity))
        XCTAssertNil(CameraTimeBands.second(atMilliseconds: -1))
        XCTAssertNil(CameraTimeBands.second(atMilliseconds: 1e100))
        var value = CameraTimeBands()
        value.record(second: 20, observable: true, nod: false)
        let bands = value.bands
        for second in [-1, 0, 10, 20, Int.max] { value.record(second: second, observable: true, nod: true) }
        XCTAssertEqual(value.bands, bands)
    }

    func testAnalysisSummaryAndBandsUseSameSampleClock() throws {
        let session = try AnalysisSession(subject: .audience)
        let face: [String: Any] = ["bbox": ["x": 0.2, "y": 0.2, "width": 0.3, "height": 0.3], "yaw": 0.0, "pitch": 0.0]
        try session.process(faces: [face], at: 979)
        let first = try session.process(faces: [face], at: 980)
        XCTAssertEqual(first.observableSeconds, 1)
        let last = try session.process(faces: [], at: 10_020, missing: true)
        XCTAssertEqual(last.sampledSeconds, 10)
        XCTAssertEqual(last.missingSeconds, 9)
        XCTAssertEqual(last.timeBands.reduce(0) { $0 + $1.observableSeconds }, last.observableSeconds)
        XCTAssertEqual(last.timeBands.reduce(0) { $0 + $1.missingSeconds }, last.missingSeconds)
        XCTAssertEqual(last.timeBands.reduce(0) { $0 + $1.nodCandidateSeconds }, last.nodCandidateSeconds)
    }

    func testDeletionAndNewCaptureCannotRetainOrRestoreOldBands() {
        let old = UUID(), next = UUID()
        var bands = CameraTimeBands()
        bands.record(second: 10, observable: true, nod: true)
        var summary = CameraSummary(); summary.timeBands = bands.bands
        var result = CameraResult()
        result.begin(id: old, subject: .audience)
        result.update(id: old, status: .completed, summary: summary)
        XCTAssertFalse(result.summary.timeBands.isEmpty)
        XCTAssertTrue(result.delete(id: old))
        result.update(id: old, status: .completed, summary: summary)
        XCTAssertTrue(result.summary.timeBands.isEmpty)
        result.begin(id: next, subject: .presenter)
        result.update(id: old, status: .completed, summary: summary)
        XCTAssertTrue(result.summary.timeBands.isEmpty)
    }

    func testPresentationCroppedResultDoesNotClaimCaptureBands() {
        let id = UUID(), presentation = UUID()
        var camera = CameraResult()
        camera.begin(id: id, subject: .audience)
        camera.update(id: id, status: .collecting)
        var association = PresentationResultAssociation()
        association.observe(sessionID: presentation, phase: .ready, elapsedSeconds: 0, camera: camera, liveSummary: CameraSummary())
        association.observe(sessionID: presentation, phase: .running, elapsedSeconds: 0, camera: camera, liveSummary: CameraSummary())
        var summary = CameraSummary()
        var bands = CameraTimeBands(); bands.record(second: 10, observable: true, nod: true)
        summary.timeBands = bands.bands
        camera.update(id: id, status: .completed, summary: summary)
        association.observe(sessionID: presentation, phase: .ended, elapsedSeconds: 5, camera: camera, liveSummary: summary)
        XCTAssertNotNil(association.cameraResult(from: camera))
        XCTAssertEqual(association.cameraResult(from: camera)?.summary.timeBands, [])
        XCTAssertFalse(camera.summary.timeBands.isEmpty)
    }
}
