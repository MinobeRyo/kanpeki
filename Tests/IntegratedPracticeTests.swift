import Foundation
import SwiftUI
import KanpekiAudioHost

@main struct IntegratedPracticeTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = MacModel()
        model.beginPractice()
        precondition(model.state.timer?.phase == .ready, "Unpaired practice must not begin")
        model.link.connectedName = "Synthetic iPhone"
        model.beginPractice()
        precondition(model.state.timer?.phase == .ready, "Practice needs a ready receiver")
        model.updateAudioConnection(address: "http://192.168.1.10:8765", token: String(repeating: "x", count: 32))
        model.configureMCP(folder: folder)
        model.beginPractice()
        precondition(model.state.timer?.phase == .running && model.state.isPractice == true)
        precondition(model.state.timer?.durationSeconds == 300 && !model.capture.sharing)
        let id = model.state.timer!.sessionID
        let recordingID = UUID()
        let fact = PracticeFact(id: "audio.\(recordingID.uuidString.lowercased()).segment.0", kind: "audio",
            text: "予備評価の条件を説明します。", audioRange: PracticeAudioRange(recordingID: recordingID, startSeconds: 0, endSeconds: 2))
        let evidence = PhoneAnalysisEvidence(sharingID: model.state.analysisSharingID!, presentationID: id,
            sequence: 1, recordingID: recordingID, cameraID: nil, facts: [fact])
        model.link.onMessage?(WireMessage(kind: "analysisEvidence", analysisEvidence: evidence))
        precondition(model.sharedAudioAvailable)
        model.timerAction(.end, duration: nil)
        for _ in 0..<100 where model.timerFinishing { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.state.timer?.phase == .ended && !model.timerFinishing)
        precondition(model.sharedAudioAvailable, "Ending without screen sharing must preserve evidence")
        model.requestPracticeAnalysis(copyPrompt: false)
        let requestData = try Data(contentsOf: folder.appendingPathComponent("practice-request.json"))
        let request = try JSONDecoder().decode(PracticeAnalysisRequest.self, from: requestData)
        precondition(request.presentationID == id && request.facts.contains(fact))
        precondition(!String(decoding: requestData, as: UTF8.self).contains(String(repeating: "x", count: 32)), "Pairing token must not enter MCP")
        if let directory = ProcessInfo.processInfo.environment["KANPEKI_INTEGRATION_SNAPSHOTS"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let audio = AudioHostModel()
            try render(MacScreen(model: model, capture: model.capture, link: model.link, audio: audio, showScreenReview: .constant(false)), path: directory + "/home.png")
            try render(RehearsalFlow(model: model, audio: audio, link: model.link, connect: {}, feedback: {}, audioDetails: {}), path: directory + "/review.png")
        }
        model.timerAction(.reset, duration: nil)
        precondition(model.state.timer?.sessionID != id && !model.sharedAudioAvailable)
        precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("practice-request.json").path))
        let timeDraft = MacPreparationDraft(timer: model.state.timer!, connectionID: model.preparationConnectionID)
        precondition(model.canAdjustRehearsalTime(timeDraft))
        model.timerAction(.configure, duration: 120)
        precondition(!model.canAdjustRehearsalTime(timeDraft), "A changed revision must reject the old time confirmation")
        let currentDraft = MacPreparationDraft(timer: model.state.timer!, connectionID: model.preparationConnectionID)
        precondition(model.canAdjustRehearsalTime(currentDraft))
        var otherSession = currentDraft.timer
        otherSession.sessionID = UUID()
        precondition(!model.canAdjustRehearsalTime(MacPreparationDraft(timer: otherSession, connectionID: currentDraft.connectionID)), "Another presentation must reject the time confirmation")
        model.importing = true
        precondition(!model.canAdjustRehearsalTime(currentDraft), "Importing must block time changes")
        model.importing = false
        model.link.onConnection?(false)
        precondition(!model.canAdjustRehearsalTime(currentDraft), "A changed connection generation must reject the time confirmation")
        print("PASS: rehearsal time confirmation rejects changed revision/session/connection and busy preparation")
        model.updateAudioConnection(address: nil, token: "")
        precondition(model.state.audioConnection == nil)
        model.stopMCP()
        print("PASS: integrated practice start/end, paired endpoint, same-session audio → MCP, token exclusion, reset invalidation. Synthetic peer; no actual device or ChatGPT.")
    }
    @MainActor static func render<V: View>(_ view: V, path: String) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
