import Foundation
import CryptoKit

/// The main app is the source of slide order and persistent PPTX slide IDs.
struct PreparationDeck: Codable, Equatable {
    struct Page: Codable, Equatable {
        let slideIndex: Int
        let slideID: Int
        let body: String
        let notes: String
    }
    let schemaVersion: Int
    let deckVersion: UUID
    let title: String
    let available: Bool
    let slides: [Page]

    var isValid: Bool {
        schemaVersion == 1 && available && (1...500).contains(slides.count)
        && Set(slides.map(\.slideID)).count == slides.count
        && slides.enumerated().allSatisfy { index, page in
            page.slideIndex == index + 1 && page.slideID > 0
            && page.body.utf8.count <= 128 * 1024 && page.notes.utf8.count <= 64 * 1024
        }
    }
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(slides)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}

/// No prompt, raw report, model-generated quote, or original media is transferred.
struct PreparationNotes: Codable, Equatable {
    struct Page: Codable, Equatable {
        let slideIndex: Int
        let slideID: Int
        let text: String
    }
    static let maxBytes = 512 * 1024
    static let maxPageBytes = 16 * 1024
    let schemaVersion: Int
    let requestID: UUID
    let deckVersion: UUID
    let fingerprint: String
    let pages: [Page]

    func matches(_ deck: PreparationDeck, requestID currentID: UUID) -> Bool {
        schemaVersion == 1 && requestID == currentID && deck.isValid
        && deckVersion == deck.deckVersion && fingerprint == deck.fingerprint
        && pages.count == deck.slides.count
        && zip(pages, deck.slides).allSatisfy { page, source in
            page.slideIndex == source.slideIndex && page.slideID == source.slideID
            && !page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && page.text.utf8.count <= Self.maxPageBytes
        }
        && ((try? JSONEncoder().encode(self).count) ?? Int.max) <= Self.maxBytes
    }
}

/// Confirmation is invalidated by any change to its source or session context.
struct PreparationNotesContext: Equatable {
    let deckVersion: UUID
    let connectionID: UUID
    let timerSessionID: UUID
    let timerRevision: UInt64
    let sharingID: UUID
}

struct PreparationNotesSelection {
    private(set) var pending: PreparationNotes?
    private(set) var accepted: PreparationNotes?
    private var context: PreparationNotesContext?

    mutating func review(_ notes: PreparationNotes, deck: PreparationDeck, currentID: UUID,
                         context: PreparationNotesContext, ready: Bool) -> Bool {
        pending = nil
        guard ready, notes.matches(deck, requestID: currentID) else { return false }
        if accepted != notes { accepted = nil }
        pending = notes; self.context = context
        return true
    }
    mutating func apply(current notes: PreparationNotes, deck: PreparationDeck, currentID: UUID,
                        context: PreparationNotesContext, ready: Bool) -> Bool {
        guard ready, self.context == context, pending == notes,
              notes.matches(deck, requestID: currentID) else { cancel(); return false }
        accepted = notes; cancel(); return true
    }
    mutating func cancel() { pending = nil; context = nil }
    mutating func clear() { cancel(); accepted = nil }
    func text(slideID: Int, index: Int, deckVersion: UUID) -> String? {
        guard let accepted, accepted.deckVersion == deckVersion else { return nil }
        return accepted.pages.first { $0.slideID == slideID && $0.slideIndex == index }?.text
    }
}

enum PreparationNotesFile {
    static func read<T: Decodable>(_ type: T.Type, from url: URL, limit: Int) throws -> T {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadUnsupportedScheme) }
        // Read at most limit+1 bytes, even if the file changes after metadata inspection.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(type, from: data)
    }
}
