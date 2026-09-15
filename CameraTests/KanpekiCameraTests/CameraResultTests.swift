import XCTest
@testable import KanpekiCamera

final class CameraResultTests: XCTestCase {
    func testOffIsNotACompletedZeroScore() {
        let result = CameraResult()
        XCTAssertEqual(result.status, .off)
        XCTAssertNil(result.id)
    }

    func testNewSessionRejectsOldSummaryAndKeepsSubject() {
        var result = CameraResult()
        let old = UUID(), current = UUID()
        result.begin(id: old, subject: .audience)
        var measured = CameraSummary()
        measured.observableSeconds = 7
        result.update(id: old, status: .completed, summary: measured)
        result.begin(id: current, subject: .presenter)
        result.update(id: old, status: .completed, summary: measured)
        XCTAssertEqual(result.status, .preparing)
        XCTAssertEqual(result.subject, .presenter)
        XCTAssertEqual(result.summary.observableSeconds, 0)
        XCTAssertFalse(result.delete(id: old))
        XCTAssertEqual(result.id, current)
    }

    func testDeletionOnlyForDisplayedFinishedSession() {
        var result = CameraResult()
        let id = UUID()
        result.begin(id: id, subject: .audience)
        for status in [CameraResult.Status.preparing, .collecting, .finalizing] {
            result.update(id: id, status: status)
            XCTAssertFalse(result.delete(id: id))
        }
        result.update(id: id, status: .completed)
        XCTAssertTrue(result.delete(id: id))
        result.update(id: id, status: .failed("late callback"))
        XCTAssertEqual(result.status, .off)
        XCTAssertNil(result.id)
    }

    func testMissingReasonsRemainDistinctAndPreservePartialResults() {
        let reasons: [CameraResult.Status] = [.permissionDenied, .inputInterrupted, .cancelled, .failed("テスト")]
        XCTAssertEqual(Set(reasons.map(\.message)).count, reasons.count)
        for status in reasons {
            var result = CameraResult()
            let id = UUID()
            result.begin(id: id, subject: .audience)
            var measured = CameraSummary()
            measured.observableSeconds = 3
            measured.missingSeconds = 2
            result.update(id: id, status: status, summary: measured)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.summary, measured)
        }
    }
}
