import Foundation

@main struct PreparationNotesTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool) {
            precondition(value(), "Preparation notes check \(checks + 1)"); checks += 1
        }
        let version = UUID(), requestID = UUID()
        let pages = [PreparationDeck.Page(slideIndex: 1, slideID: 259, body: "比較結果", notes: "効果は未検証です。"),
                     PreparationDeck.Page(slideIndex: 2, slideID: 256, body: "結論", notes: "次に検証します。")]
        let deck = PreparationDeck(schemaVersion: 1, deckVersion: version, title: "fixture", available: true, slides: pages)
        let notes = PreparationNotes(schemaVersion: 1, requestID: requestID, deckVersion: version,
            fingerprint: deck.fingerprint, pages: pages.map { .init(slideIndex: $0.slideIndex, slideID: $0.slideID, text: $0.notes) })
        func changed(_ slides: [PreparationDeck.Page]) -> PreparationDeck {
            PreparationDeck(schemaVersion: 1, deckVersion: version, title: "fixture", available: true, slides: slides)
        }
        check(deck.isValid)
        check(notes.matches(deck, requestID: requestID))
        check(!notes.matches(deck, requestID: UUID()))
        check(!notes.matches(PreparationDeck(schemaVersion: 1, deckVersion: UUID(), title: "fixture", available: true, slides: pages), requestID: requestID))
        check(!notes.matches(changed(Array(pages.reversed())), requestID: requestID))
        check(!notes.matches(changed([.init(slideIndex: 1, slideID: 259, body: "変更", notes: pages[0].notes), pages[1]]), requestID: requestID))
        check(!notes.matches(changed([.init(slideIndex: 1, slideID: 259, body: pages[0].body, notes: "変更"), pages[1]]), requestID: requestID))
        check(!changed([pages[0], .init(slideIndex: 2, slideID: 259, body: "重複", notes: "")]).isValid)
        let oversized = PreparationNotes(schemaVersion: 1, requestID: requestID, deckVersion: version,
            fingerprint: deck.fingerprint, pages: [.init(slideIndex: 1, slideID: 259, text: String(repeating: "語", count: 6000)), notes.pages[1]])
        check(!oversized.matches(deck, requestID: requestID))
        check(!PreparationNotes(schemaVersion: 1, requestID: requestID, deckVersion: version, fingerprint: deck.fingerprint, pages: [notes.pages[0]]).matches(deck, requestID: requestID))
        let context = PreparationNotesContext(deckVersion: version, connectionID: UUID(), timerSessionID: UUID(), timerRevision: 2, sharingID: UUID())
        var selection = PreparationNotesSelection()
        check(!selection.review(notes, deck: deck, currentID: requestID, context: context, ready: false))
        check(selection.review(notes, deck: deck, currentID: requestID, context: context, ready: true))
        check(selection.accepted == nil)
        selection.cancel()
        check(!selection.apply(current: notes, deck: deck, currentID: requestID, context: context, ready: true))
        let contexts = [
            PreparationNotesContext(deckVersion: UUID(), connectionID: context.connectionID, timerSessionID: context.timerSessionID, timerRevision: 2, sharingID: context.sharingID),
            PreparationNotesContext(deckVersion: version, connectionID: UUID(), timerSessionID: context.timerSessionID, timerRevision: 2, sharingID: context.sharingID),
            PreparationNotesContext(deckVersion: version, connectionID: context.connectionID, timerSessionID: UUID(), timerRevision: 2, sharingID: context.sharingID),
            PreparationNotesContext(deckVersion: version, connectionID: context.connectionID, timerSessionID: context.timerSessionID, timerRevision: 3, sharingID: context.sharingID),
            PreparationNotesContext(deckVersion: version, connectionID: context.connectionID, timerSessionID: context.timerSessionID, timerRevision: 2, sharingID: UUID())]
        for other in contexts {
            _ = selection.review(notes, deck: deck, currentID: requestID, context: context, ready: true)
            check(!selection.apply(current: notes, deck: deck, currentID: requestID, context: other, ready: true))
        }
        _ = selection.review(notes, deck: deck, currentID: requestID, context: context, ready: true)
        check(!selection.apply(current: notes, deck: deck, currentID: requestID, context: context, ready: false))
        _ = selection.review(notes, deck: deck, currentID: requestID, context: context, ready: true)
        check(selection.apply(current: notes, deck: deck, currentID: requestID, context: context, ready: true))
        check(selection.text(slideID: 259, index: 1, deckVersion: version) == pages[0].notes)
        check(selection.text(slideID: 256, index: 1, deckVersion: version) == nil)
        check(selection.text(slideID: 259, index: 1, deckVersion: UUID()) == nil)
        selection.clear()
        check(selection.accepted == nil && selection.pending == nil)
        check(deck.slides == pages)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.json")
        try JSONEncoder().encode(notes).write(to: file)
        let decoded = try PreparationNotesFile.read(PreparationNotes.self, from: file, limit: PreparationNotes.maxBytes)
        check(decoded == notes && decoded.matches(deck, requestID: requestID))
        do {
            _ = try PreparationNotesFile.read(PreparationNotes.self, from: file, limit: 8)
            preconditionFailure("Unbounded file accepted")
        } catch { checks += 1 }
        print("Preparation notes: \(checks) checks passed")
    }
}
