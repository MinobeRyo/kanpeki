import XCTest
@testable import KanpekiCamera

final class PresentationResultAssociationTests: XCTestCase {
    func testPreparationCaptureExcludesBaselineAndUsesTimerElapsed() {
        var association = PresentationResultAssociation()
        let session = UUID(), capture = UUID()
        var camera = CameraResult(); camera.begin(id: capture, subject: .audience)
        var before = CameraSummary(); before.observableSeconds = 8; before.sampledSeconds = 10
        camera.update(id: capture, status: .collecting)
        association.observe(sessionID: session, phase: .ready, elapsedSeconds: 0, camera: camera, liveSummary: before)
        association.observe(sessionID: session, phase: .running, elapsedSeconds: 1, camera: camera, liveSummary: before)
        association.observe(sessionID: session, phase: .ended, elapsedSeconds: 42, camera: camera, liveSummary: before)
        var after = before; after.observableSeconds = 12; after.sampledSeconds = 15
        camera.update(id: capture, status: .finalizing, summary: after)
        XCTAssertEqual(association.cameraResult(from: camera)?.status, .finalizing)
        camera.update(id: capture, status: .completed, summary: after)
        XCTAssertEqual(association.cameraResult(from: camera)?.summary.observableSeconds, 4)
        XCTAssertEqual(association.elapsedSeconds, 42)
    }

    func testOldCompletedOrFailedCameraIsNeverAttachedToNewPresentation() {
        for status in [CameraResult.Status.completed, .failed("old")] {
            var association = PresentationResultAssociation()
            var camera = CameraResult(); let capture = UUID(), session = UUID()
            camera.begin(id: capture, subject: .audience); camera.update(id: capture, status: status)
            association.observe(sessionID: session, phase: .ready, elapsedSeconds: 0, camera: camera, liveSummary: .init())
            association.observe(sessionID: session, phase: .running, elapsedSeconds: 0, camera: camera, liveSummary: .init())
            association.observe(sessionID: session, phase: .ended, elapsedSeconds: 1, camera: camera, liveSummary: .init())
            XCTAssertNil(association.cameraResult(from: camera))
        }
    }

    func testMidPresentationJoinOnlyAcceptsNewExplicitCapture() {
        var association = PresentationResultAssociation()
        var camera = CameraResult(); let session = UUID()
        camera.begin(id: UUID(), subject: .audience)
        association.observe(sessionID: session, phase: .running, elapsedSeconds: 20, camera: camera, liveSummary: .init())
        XCTAssertNil(association.cameraID)
        camera.begin(id: UUID(), subject: .presenter)
        association.observe(sessionID: session, phase: .running, elapsedSeconds: 21, camera: camera, liveSummary: .init())
        XCTAssertEqual(association.cameraID, camera.id)
        association.observe(sessionID: session, phase: .ended, elapsedSeconds: 30, camera: camera, liveSummary: .init())
        camera.update(id: camera.id!, status: .permissionDenied)
        XCTAssertEqual(association.cameraResult(from: camera)?.status, .permissionDenied)
        let deleted = camera.id!; XCTAssertTrue(camera.delete(id: deleted))
        XCTAssertNil(association.cameraResult(from: camera))
        camera.begin(id: UUID(), subject: .audience)
        XCTAssertNil(association.cameraResult(from: camera))
    }

    func testNewSessionAndDisconnectClearAssociation() {
        var association = PresentationResultAssociation()
        var camera = CameraResult(); camera.begin(id: UUID(), subject: .audience)
        let session = UUID()
        association.observe(sessionID: session, phase: .ready, elapsedSeconds: 0, camera: camera, liveSummary: .init())
        association.observe(sessionID: session, phase: .running, elapsedSeconds: 0, camera: camera, liveSummary: .init())
        association.observe(sessionID: session, phase: .ended, elapsedSeconds: 10, camera: camera, liveSummary: .init())
        association.observe(sessionID: UUID(), phase: .ready, elapsedSeconds: 0, camera: camera, liveSummary: .init())
        XCTAssertNil(association.elapsedSeconds); XCTAssertNil(association.cameraID)
        association.observe(sessionID: nil, phase: nil, elapsedSeconds: 0, camera: camera, liveSummary: .init())
        XCTAssertNil(association.sessionID)
    }
}
