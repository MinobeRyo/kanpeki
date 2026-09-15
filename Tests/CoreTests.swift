import Foundation

@main struct CoreTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        guard value() else { fatalError("FAIL: \(description)") }
        count += 1
        print("PASS: \(description)")
    }
    static func main() throws {
        try testSlidePointer()
        try testSlideFrames()
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let deck = try PPTXImporter.load(folder.appendingPathComponent("reordered.pptx"))
        expect(deck.slides.map(\.id) == [400, 256, 900], "presentation.xml defines order; filenames do not")
        expect(deck.slides.map(\.body) == ["Body 9 & value", "Body 1 & value", "Body 2 & value"], "body text follows presentation relationships and decodes entities")
        expect(deck.slides.map(\.index) == [1, 2, 3], "display indexes are 1 based")
        expect(deck.slides[0].notes == "最初の原稿\n二行目 & 続き", "Japanese notes preserve paragraphs and entities")
        expect(deck.slides[1].notes.isEmpty, "missing notes remain empty")
        expect(deck.slides[2].notes == "最後の原稿", "notes relationships need not have matching numeric filenames")
        expect(!deck.slides[0].notes.contains("999"), "exclude slide number and other placeholders")
        do {
            _ = try PPTXImporter.load(folder.appendingPathComponent("broken.pptx"))
            fatalError("broken relationship accepted")
        } catch { count += 1; print("PASS: reject broken slide relationships") }
        do {
            _ = try PPTXImporter.resolve("../../../secret.xml", relativeTo: "ppt/slides/slide1.xml")
            fatalError("unsafe path accepted")
        } catch { count += 1; print("PASS: reject archive path escape") }
        do {
            _ = try PPTXImporter.resolve("*.xml", relativeTo: "ppt/slides/slide1.xml")
            fatalError("ZIP wildcard accepted")
        } catch { count += 1; print("PASS: reject ZIP wildcard") }
        let payload = Data([0xff, 0xd8, 0xff, 0xd9])
        let identity = SlideFrameIdentity(sessionID: UUID(), revision: 1, slideID: 42, slideIndex: 1)
        let packet = WireCodec.frame(payload, sequence: 0x1020304050607080, identity: identity)!
        let decoded = WireCodec.readFrame(packet)!
        expect(decoded.header.sequence == 0x1020304050607080 && decoded.jpeg == payload && decoded.header.identity == identity, "frame sequence, identity and payload roundtrip")
        expect(WireCodec.readFrame(Data([0x4b, 0x46])) == nil, "reject truncated frame")
        expect(WireCodec.frame(Data(repeating: 0, count: WireCodec.maxFrameBytes + 1), sequence: 1, identity: identity) == nil, "bound transmitted image size")
        expect(WireCodec.decode(Data("{\"version\":99,\"kind\":\"control\"}".utf8)) == nil, "reject incompatible protocol")
        let control = WireMessage(kind: "control", action: .next)
        let received = WireCodec.decode(try JSONEncoder().encode(control))
        expect(received?.action == .next && received?.requestID == control.requestID, "control request preserves identity")
        var dedup = RequestDeduplicator()
        expect(dedup.accept(control.requestID), "first request accepted")
        expect(!dedup.accept(control.requestID), "duplicate request rejected")
        let sample = try PPTXImporter.load(folder.appendingPathComponent("sample.pptx"))
        expect(sample.slides.count == 3 && sample.slides.allSatisfy { !$0.notes.isEmpty }, "all-note fixture has three note-bearing slides")
        print("\(count) checks passed")
    }
}
