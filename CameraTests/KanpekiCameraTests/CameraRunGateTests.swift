import XCTest
@testable import KanpekiCamera

final class CameraRunGateTests: XCTestCase {
    func testCancelledPermissionCannotConfigureOrAttach() {
        let gate = CameraRunGate(), id = UUID(), output = NSObject()
        gate.begin(id)
        gate.invalidate(id)
        XCTAssertFalse(gate.accepts(id))
        XCTAssertFalse(gate.attach(output, to: id))
    }

    func testOldFramesAndNotificationsCannotBelongToRestart() {
        let gate = CameraRunGate(), old = UUID(), current = UUID()
        let oldOutput = NSObject(), currentOutput = NSObject()
        gate.begin(old)
        XCTAssertTrue(gate.attach(oldOutput, to: old))
        gate.begin(current)
        XCTAssertFalse(gate.accepts(current, input: oldOutput))
        XCTAssertTrue(gate.attach(currentOutput, to: current))
        XCTAssertFalse(gate.accepts(old)) // Queued notification/heartbeat/calibration.
        XCTAssertFalse(gate.accepts(current, input: oldOutput))
        XCTAssertTrue(gate.accepts(current, input: currentOutput))
    }

    func testOldFailureCannotCancelNewRun() {
        let gate = CameraRunGate(), old = UUID(), current = UUID()
        gate.begin(old)
        gate.begin(current)
        gate.invalidate(old)
        XCTAssertTrue(gate.accepts(current))
        gate.invalidate(current)
        XCTAssertFalse(gate.accepts(current))
    }
}
