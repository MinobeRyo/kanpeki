import Foundation

@main struct CoreTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        guard value() else { fatalError("FAIL: \(description)") }
        count += 1
        print("PASS: \(description)")
    }
    static func main() throws {
        var audioState = PresentationState()
        audioState.audioConnection = PresentationAudioConnection(address: "http://192.168.1.10:8765", token: String(repeating: "a", count: 32))
        let audioWire = try JSONEncoder().encode(WireMessage(kind: "state", state: audioState))
        expect(WireCodec.decode(audioWire)?.state?.audioConnection == audioState.audioConnection, "paired audio endpoint survives state roundtrip")
        for address in ["https://example.com:8765", "http://127.0.0.1:8765", "http://8.8.8.8:8765", "http://192.168.1.10:8765/path", "http://user@192.168.1.10:8765"] {
            audioState.audioConnection = PresentationAudioConnection(address: address, token: String(repeating: "a", count: 32))
            expect(WireCodec.decode(try! JSONEncoder().encode(WireMessage(kind: "state", state: audioState))) == nil, "reject invalid audio destination: " + address)
        }
        audioState.audioConnection = nil
        expect(WireCodec.decode(try! JSONEncoder().encode(WireMessage(kind: "state", state: audioState)))?.state?.audioConnection == nil, "receiver stop removes paired endpoint")
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
        var preparedState = PresentationState()
        preparedState.slideID = 259; preparedState.slideIndex = 1
        preparedState.notes = String(repeating: "\"\\\n", count: 5000)
        preparedState.notesStatus = "採用した要点案（原文は保持）"
        let preparedData = try JSONEncoder().encode(WireMessage(kind: "state", state: preparedState))
        expect(preparedData.count < WireCodec.maxMessageBytes, "current prepared page stays within wire bound even with escaping")
        expect(WireCodec.decode(preparedData)?.state == preparedState, "phone wire decoder preserves prepared notes, source label and source slide identity")
        let received = WireCodec.decode(try JSONEncoder().encode(control))
        expect(received?.action == .next && received?.requestID == control.requestID, "control request preserves identity")
        let sharedID = UUID(), presentationID = UUID(), recordingID = UUID()
        let audioFact = PracticeFact(id: "audio.\(recordingID.uuidString.lowercased()).status", kind: "audio", text: "文字起こし未計測")
        let evidence = PhoneAnalysisEvidence(sharingID: sharedID, presentationID: presentationID,
            sequence: 1, recordingID: recordingID, cameraID: nil, facts: [audioFact])
        let evidenceMessage = WireMessage(kind: "analysisEvidence", analysisEvidence: evidence)
        let evidenceData = try JSONEncoder().encode(evidenceMessage)
        expect(WireCodec.decode(evidenceData)?.analysisEvidence == evidence, "analysis evidence wire roundtrip")
        let emptyEvidenceData = try JSONEncoder().encode(WireMessage(kind: "analysisEvidence"))
        expect(WireCodec.decode(emptyEvidenceData) == nil, "reject absent analysis payload")
        let wrongRecording = PhoneAnalysisEvidence(sharingID: sharedID, presentationID: presentationID,
            sequence: 1, recordingID: UUID(), cameraID: nil, facts: [audioFact])
        expect(!wrongRecording.isValid, "source IDs must match recording ID")
        var resultState = PresentationState()
        resultState.practiceAnalysis = PracticeAnalysisResult(requestID: UUID(), presentationID: presentationID,
            items: [PracticeAnalysisItem(kind: "limitation", text: "未計測です", evidenceIDs: [audioFact.id], sources: [audioFact.text])])
        let mismatchedResultData = try JSONEncoder().encode(WireMessage(kind: "state", state: resultState))
        expect(WireCodec.decode(mismatchedResultData) == nil, "reject analysis with no matching timer session")
        var dedup = RequestDeduplicator()
        expect(dedup.accept(control.requestID), "first request accepted")
        expect(!dedup.accept(control.requestID), "duplicate request rejected")
        let sample = try PPTXImporter.load(folder.appendingPathComponent("sample.pptx"))
        expect(sample.slides.count == 3 && sample.slides.allSatisfy { !$0.notes.isEmpty }, "all-note fixture has three note-bearing slides")
        print("\(count) checks passed")
    }
}
