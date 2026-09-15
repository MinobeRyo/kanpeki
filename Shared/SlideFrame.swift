import Foundation

/// Identity of the observed page and sharing/connection generation, not a pixel classifier.
struct SlideFrameIdentity: Codable, Equatable {
    var sessionID: UUID
    var revision: UInt64
    var slideID: Int?
    var slideIndex: Int?
    var isValid: Bool {
        revision > 0 && ((slideID == nil && slideIndex == nil) ||
            (slideID.map { $0 > 0 } == true && slideIndex.map { $0 > 0 } == true))
    }
}

struct SlideFrameHeader: Codable {
    var sequence: UInt64
    var identity: SlideFrameIdentity
}

struct SlideFramePacket {
    var header: SlideFrameHeader
    var jpeg: Data
}

struct SlideCaptureLease {
    let identity: SlideFrameIdentity
    let beganAt: TimeInterval
    func accepts(current: SlideFrameIdentity?, now: TimeInterval) -> Bool {
        identity == current && now.isFinite && beganAt.isFinite && (0..<2).contains(now - beganAt)
    }
}

struct SlideCaptureRequests {
    private(set) var activeID: UUID?
    mutating func begin() -> UUID? {
        guard activeID == nil else { return nil }
        let id = UUID(); activeID = id; return id
    }
    mutating func invalidate() { activeID = nil }
    @discardableResult mutating func finish(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }
}

/// No deferred frame queue: a mismatched frame is ACKed by transport, but never displayed.
struct SlideFrameReceiver {
    private(set) var displayedIdentity: SlideFrameIdentity?
    private var sequence: UInt64 = 0
    mutating func update(state: PresentationState) {
        if !state.isSharing || state.frameReady != true || displayedIdentity != state.frameIdentity {
            displayedIdentity = nil
        }
    }
    mutating func accept(_ frame: SlideFramePacket, state: PresentationState) -> Bool {
        guard state.isSharing, state.frameReady == true, frame.header.identity.isValid,
              frame.header.identity == state.frameIdentity, frame.header.sequence > sequence else { return false }
        sequence = frame.header.sequence
        displayedIdentity = frame.header.identity
        return true
    }
    func matches(_ state: PresentationState) -> Bool {
        state.isSharing && state.frameReady == true && displayedIdentity != nil && displayedIdentity == state.frameIdentity
    }
}
