import Foundation

enum RemoteAction: String, Codable { case next, previous, refresh }

struct PresentationState: Codable, Equatable {
    var title = "スライド未接続"
    var slideIndex: Int? = nil // 1-based source index, never guessed from taps
    var slideID: Int? = nil
    var totalSlides = 0
    var notes = ""
    var notesStatus = "pptxを読み込んでください"
    var canControl = false
    var isSharing = false
    var pointerSessionID: UUID? = nil
    var frameIdentity: SlideFrameIdentity? = nil
    var frameReady: Bool? = nil
    var message = "Macで共有するウィンドウを選択してください"
    var timer: PresentationTimerSnapshot? = nil

    var allowsSlideInteraction: Bool {
        timer.map { $0.phase == .running || $0.phase == .paused } ?? true
    }

    func canMoveSlide(_ action: RemoteAction) -> Bool {
        guard canControl, isSharing, allowsSlideInteraction,
              let index = slideIndex, index >= 1, index <= totalSlides else { return false }
        switch action {
        case .previous: return index > 1
        case .next: return index < totalSlides
        case .refresh: return false
        }
    }
}

struct WireMessage: Codable {
    var version = 1
    var kind: String
    var requestID: UUID = UUID()
    var action: RemoteAction? = nil
    var state: PresentationState? = nil
    var frameSequence: UInt64? = nil
    var timerCommand: PresentationTimerCommand? = nil
    var pointer: SlidePointerUpdate? = nil
    var frameIdentity: SlideFrameIdentity? = nil
}

enum WireCodec {
    static let maxMessageBytes = 256 * 1024
    static let maxFrameBytes = 180 * 1024
    static func decode(_ data: Data) -> WireMessage? {
        guard data.count <= maxMessageBytes,
              let value = try? JSONDecoder().decode(WireMessage.self, from: data),
              value.version == 1, ["control", "state", "frameAck", "timerControl", "pointer"].contains(value.kind),
              value.state?.timer?.isValid != false,
              value.state?.frameIdentity?.isValid != false,
              value.frameIdentity?.isValid != false else { return nil }
        return value
    }
    static func frame(_ jpeg: Data, sequence: UInt64, identity: SlideFrameIdentity) -> Data? {
        guard !jpeg.isEmpty, jpeg.count <= maxFrameBytes, identity.isValid, sequence > 0,
              let header = try? JSONEncoder().encode(SlideFrameHeader(sequence: sequence, identity: identity)),
              header.count <= 1024 else { return nil }
        var output = Data([0x4b, 0x46, 2, UInt8(header.count >> 8), UInt8(header.count & 255)])
        output.append(header)
        output.append(jpeg)
        return output
    }
    static func readFrame(_ packet: Data) -> SlideFramePacket? {
        guard packet.count > 5, packet.count <= maxFrameBytes + 1029,
              Array(packet.prefix(3)) == [0x4b, 0x46, 2] else { return nil }
        let count = packet.dropFirst(3).prefix(2).reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= 1024, packet.count > 5 + count,
              packet.count - 5 - count <= maxFrameBytes,
              let header = try? JSONDecoder().decode(SlideFrameHeader.self, from: packet.dropFirst(5).prefix(count)),
              header.sequence > 0, header.identity.isValid else { return nil }
        return SlideFramePacket(header: header, jpeg: Data(packet.dropFirst(5 + count)))
    }
}

struct ImportedSlide: Codable, Equatable {
    let id: Int
    let index: Int
    let notes: String
    var body: String = ""
}
struct ImportedDeck {
    let url: URL
    let slides: [ImportedSlide]
    var title: String { url.lastPathComponent }
}

struct SlideObservation: Codable {
    let sessionID: UUID
    let observedAt: Date
    let elapsedMs: Int
    let presentation: String
    let slideID: Int
    let slideIndex: Int
    let timingSource: String // polling observation, not exact rendering time
}

struct RequestDeduplicator {
    private var ids: [UUID] = []
    mutating func accept(_ id: UUID) -> Bool {
        guard !ids.contains(id) else { return false }
        ids.append(id)
        if ids.count > 256 { ids.removeFirst(ids.count - 256) }
        return true
    }
}
