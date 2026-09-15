import Foundation

/// Invalidates already queued traffic at the instant a matching session disconnects.
/// Retired sessions and foreign peers cannot change the current callback epoch.
final class PeerCallbackGate<Peer: Equatable>: @unchecked Sendable {
    private let lock = NSLock()
    private var source: ObjectIdentifier?
    private var peer: Peer?
    private var epoch = UUID()
    private var ended = false

    func begin(source: AnyObject, peer: Peer?) {
        lock.lock(); defer { lock.unlock() }
        self.source = ObjectIdentifier(source)
        self.peer = peer
        epoch = UUID(); ended = false
    }

    func ticket(source: AnyObject, peer: Peer, ending: Bool = false) -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard self.source == ObjectIdentifier(source), self.peer == peer, !ended else { return nil }
        if ending { ended = true; epoch = UUID() }
        return epoch
    }

    func accepts(_ ticket: UUID, source: AnyObject, ended: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return self.source == ObjectIdentifier(source) && epoch == ticket && self.ended == ended
    }
}

/// Single-peer admission, independent of MultipeerConnectivity and UI callbacks.
/// The transport must also reject callbacks from retired MCSession instances.
struct PeerApprovalState<Peer: Equatable> {
    enum Phase { case stopped, idle, awaitingApproval, connecting, connected }
    private(set) var phase: Phase = .stopped
    private(set) var peer: Peer?
    private(set) var operationID: UUID?

    mutating func start() { self = Self(); phase = .idle }
    mutating func stop() { self = Self() }

    /// Reserve immediately, including the interval between acceptance and connection.
    mutating func begin(peer: Peer, needsApproval: Bool) -> UUID? {
        guard phase == .idle else { return nil }
        let id = UUID()
        self.peer = peer
        operationID = id
        phase = needsApproval ? .awaitingApproval : .connecting
        return id
    }

    mutating func approve(operationID: UUID) -> Bool {
        guard self.operationID == operationID, phase == .awaitingApproval else { return false }
        phase = .connecting
        return true
    }

    mutating func connected(peer: Peer, operationID: UUID) -> Bool {
        guard self.peer == peer, self.operationID == operationID, phase == .connecting else { return false }
        phase = .connected
        return true
    }

    mutating func disconnected(peer: Peer, operationID: UUID) -> Bool {
        guard self.peer == peer, self.operationID == operationID,
              phase != .stopped, phase != .idle else { return false }
        self = Self(); phase = .idle
        return true
    }

    /// Expiry/rejection is tied to one operation; connected sessions never time out here.
    mutating func cancel(operationID: UUID) -> Bool {
        guard self.operationID == operationID,
              phase == .awaitingApproval || phase == .connecting else { return false }
        self = Self(); phase = .idle
        return true
    }

    func allowsTraffic(from peer: Peer) -> Bool { phase == .connected && self.peer == peer }
    // An approved peer may deliver a frame before its connected callback reaches main.
    // ACK only; never release private state or display that frame before connected.
    func allowsFrameAcknowledgement(from peer: Peer) -> Bool {
        (phase == .connecting || phase == .connected) && self.peer == peer
    }
}
