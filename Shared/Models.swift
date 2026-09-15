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
    var message = "Macで共有するウィンドウを選択してください"
}

struct WireMessage: Codable {
    var version = 1
    var kind: String
    var requestID: UUID = UUID()
    var action: RemoteAction? = nil
    var state: PresentationState? = nil
    var frameSequence: UInt64? = nil
    var pointer: SlidePointerUpdate? = nil
}

enum WireCodec {
    static let maxMessageBytes = 256 * 1024
    static let maxFrameBytes = 180 * 1024
    static func decode(_ data: Data) -> WireMessage? {
        guard data.count <= maxMessageBytes,
              let value = try? JSONDecoder().decode(WireMessage.self, from: data),
              value.version == 1, ["control", "state", "frameAck", "pointer"].contains(value.kind) else { return nil }
        return value
    }
    static func frame(_ jpeg: Data, sequence: UInt64) -> Data? {
        guard !jpeg.isEmpty, jpeg.count <= maxFrameBytes else { return nil }
        var output = Data([0x4b, 0x46, 1])
        for shift in stride(from: 56, through: 0, by: -8) { output.append(UInt8((sequence >> shift) & 255)) }
        output.append(jpeg)
        return output
    }
    static func readFrame(_ packet: Data) -> (UInt64, Data)? {
        guard packet.count > 11, packet.count <= maxFrameBytes + 11,
              Array(packet.prefix(3)) == [0x4b, 0x46, 1] else { return nil }
        let sequence = packet.dropFirst(3).prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return (sequence, Data(packet.dropFirst(11)))
    }
}

struct ImportedSlide: Codable, Equatable {
    let id: Int
    let index: Int
    let notes: String
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
