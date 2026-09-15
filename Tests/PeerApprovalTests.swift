import Foundation

@main struct PeerApprovalTests {
    static var checks = 0
    static func expect(_ result: Bool, _ message: String) {
        precondition(result, message); checks += 1; print("PASS: \(message)")
    }
    static func main() {
        var state = PeerApprovalState<String>()
        expect(state.begin(peer: "A", needsApproval: true) == nil, "stopped cannot accept invitation")
        state.start()
        let first = state.begin(peer: "A", needsApproval: true)!
        expect(state.begin(peer: "B", needsApproval: true) == nil, "pending approval reserves one peer")
        expect(!state.connected(peer: "A", operationID: first), "unapproved peer cannot connect")
        expect(!state.allowsTraffic(from: "A"), "pending peer cannot receive private data")
        expect(!state.allowsFrameAcknowledgement(from: "A"), "unapproved frames get no acknowledgement")
        expect(!state.approve(operationID: UUID()), "stale approval cannot accept invitation")
        expect(state.approve(operationID: first), "explicit approval moves to connecting")
        expect(!state.approve(operationID: first), "approval can be consumed only once")
        expect(state.begin(peer: "B", needsApproval: true) == nil, "accepted-but-not-connected peer retains reservation")
        expect(!state.allowsTraffic(from: "A"), "connecting peer is not yet a traffic target")
        expect(state.allowsFrameAcknowledgement(from: "A"), "early approved frame can be ACKed before connected callback")
        expect(!state.allowsFrameAcknowledgement(from: "B"), "early foreign frame cannot be ACKed")
        expect(!state.connected(peer: "B", operationID: first), "foreign connected callback cannot replace reserved peer")
        expect(!state.disconnected(peer: "B", operationID: first), "foreign disconnect cannot erase reservation")
        expect(state.connected(peer: "A", operationID: first), "reserved peer connects")
        expect(state.allowsTraffic(from: "A") && !state.allowsTraffic(from: "B"), "traffic targets exactly approved peer")
        expect(!state.cancel(operationID: first), "old invitation timeout cannot close connected session")
        expect(!state.connected(peer: "A", operationID: first), "duplicate connect does not reset session")
        expect(state.disconnected(peer: "A", operationID: first), "current peer disconnects")
        expect(!state.allowsTraffic(from: "A"), "disconnected peer cannot receive data")
        let second = state.begin(peer: "B", needsApproval: false)!
        expect(second != first, "retry gets unique operation")
        expect(!state.cancel(operationID: first), "old timeout cannot cancel new invitation")
        expect(state.peer == "B", "retry keeps chosen peer")
        expect(state.cancel(operationID: second), "current timeout frees reservation")
        expect(state.phase == .idle, "timed out can retry")
        let third = state.begin(peer: "A", needsApproval: true)!
        expect(state.cancel(operationID: third), "explicit rejection releases reservation")
        let fourth = state.begin(peer: "A", needsApproval: false)!
        state.stop()
        expect(!state.cancel(operationID: fourth), "timeout after stop is ignored")
        expect(!state.connected(peer: "A", operationID: fourth), "connected after stop is ignored")
        state.start()
        let fifth = state.begin(peer: "A", needsApproval: true)!
        expect(!state.approve(operationID: third), "old approval after restart is ignored")
        expect(!state.cancel(operationID: fourth), "old same-peer timeout after restart is ignored")
        expect(state.approve(operationID: fifth), "new same-peer operation remains valid")
        expect(!state.connected(peer: "A", operationID: first), "old same-peer connect cannot finish new attempt")
        expect(!state.disconnected(peer: "A", operationID: first), "old same-peer disconnect cannot erase new attempt")
        expect(state.connected(peer: "A", operationID: fifth), "new same-peer connects using exact operation")
        let callbacks = PeerCallbackGate<String>()
        let oldSession = NSObject(), newSession = NSObject()
        callbacks.begin(source: oldSession, peer: "A")
        let oldTicket = callbacks.ticket(source: oldSession, peer: "A")!
        expect(callbacks.ticket(source: oldSession, peer: "B", ending: true) == nil, "foreign disconnect cannot invalidate approved traffic")
        expect(callbacks.accepts(oldTicket, source: oldSession), "foreign callback preserves current epoch")
        let endedTicket = callbacks.ticket(source: oldSession, peer: "A", ending: true)!
        expect(!callbacks.accepts(oldTicket, source: oldSession), "observed disconnect invalidates already queued data")
        expect(callbacks.accepts(endedTicket, source: oldSession, ended: true), "current disconnect can be handled on main")
        expect(callbacks.ticket(source: oldSession, peer: "A") == nil, "ended session cannot silently reconnect")
        callbacks.begin(source: newSession, peer: "A")
        let newTicket = callbacks.ticket(source: newSession, peer: "A")!
        expect(!callbacks.accepts(endedTicket, source: oldSession, ended: true), "old disconnect cannot erase new same-peer session")
        expect(callbacks.ticket(source: oldSession, peer: "A", ending: true) == nil, "retired session cannot advance current epoch")
        expect(callbacks.accepts(newTicket, source: newSession), "new operation keeps fresh callbacks")
        print("\(checks) peer approval state checks passed")
    }
}
