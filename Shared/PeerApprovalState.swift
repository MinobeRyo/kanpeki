import Foundation

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
}
