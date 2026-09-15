import Foundation

/// Shared only for cancellation/identity checks across the main and capture queues.
/// No frame data or capture operations execute under this lock.
final class CameraRunGate: @unchecked Sendable {
    private let lock = NSLock()
    private var runID: UUID?
    private var inputID: ObjectIdentifier?

    func begin(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        runID = id
        inputID = nil
    }

    @discardableResult func attach(_ input: AnyObject, to id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard runID == id else { return false }
        inputID = ObjectIdentifier(input)
        return true
    }

    func accepts(_ id: UUID, input: AnyObject? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard runID == id else { return false }
        return input.map { inputID == ObjectIdentifier($0) } ?? true
    }

    func invalidate(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard runID == id else { return }
        runID = nil
        inputID = nil
    }
}
