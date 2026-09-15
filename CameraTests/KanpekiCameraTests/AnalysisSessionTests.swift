import XCTest
@testable import KanpekiCamera

final class AnalysisSessionTests: XCTestCase {
    let face: [String: Any] = ["bbox": ["x": 0.2, "y": 0.2, "width": 0.3, "height": 0.3], "yaw": 0.0, "pitch": 0.0]

    func testMissingInputDoesNotBecomeZeroReaction() throws {
        let session = try AnalysisSession(subject: .audience)
        try session.process(faces: [face], at: 0)
        let good = try session.process(faces: [face], at: 1000)
        XCTAssertEqual(good.observableSeconds, 1)
        let missing = try session.process(faces: [], at: 4000, missing: true)
        XCTAssertNil(missing.faceCount)
        XCTAssertEqual(missing.observableSeconds, 1)
        XCTAssertEqual(missing.missingSeconds, 3)
    }

    func testSubjectIsManualEvenWithMultipleFaces() throws {
        let session = try AnalysisSession(subject: .presenter)
        for t in stride(from: 0.0, through: 6000, by: 200) {
            try session.process(faces: [face, face, face], at: t)
        }
        // Calibration would throw if automatic audience voting had changed the role.
        XCTAssertNoThrow(try session.calibrate("notes", at: 6001))
    }

    func testMovementAndNoFacesAreUnobservable() throws {
        let session = try AnalysisSession(subject: .audience)
        try session.process(faces: [face], at: 1000, moving: true)
        let result = try session.process(faces: [], at: 2000)
        XCTAssertEqual(result.observableSeconds, 0)
        XCTAssertEqual(result.missingSeconds, 2)
        XCTAssertEqual(result.nodCandidateSeconds, 0)
    }

    func testOutOfOrderFrameDoesNotChangeSummary() throws {
        let session = try AnalysisSession(subject: .audience)
        let first = try session.process(faces: [face], at: 1000)
        XCTAssertEqual(try session.process(faces: [], at: 900), first)
    }

    func testCadenceUsesTimeBucketsWithoutCatchUpBurst() {
        var cadence = AnalysisCadence()
        XCTAssertTrue(cadence.shouldProcess(seconds: 0, fps: 6))
        XCTAssertFalse(cadence.shouldProcess(seconds: 0.1, fps: 6))
        XCTAssertTrue(cadence.shouldProcess(seconds: 4, fps: 6))
        XCTAssertFalse(cadence.shouldProcess(seconds: 4.01, fps: 6))
    }
}
