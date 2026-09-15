import Foundation

@main struct AudioIdentityTests {
    static func main() throws {
        var identity = AudioRecordingIdentity()
        let presentation = UUID()
        precondition(AudioRecordingIdentity.canStart(presentationID: presentation, currentID: presentation, active: true, receivedAt: 10, now: 12.9))
        precondition(!AudioRecordingIdentity.canStart(presentationID: presentation, currentID: UUID(), active: true, receivedAt: 10, now: 11))
        precondition(!AudioRecordingIdentity.canStart(presentationID: presentation, currentID: presentation, active: false, receivedAt: 10, now: 11))
        precondition(!AudioRecordingIdentity.canStart(presentationID: presentation, currentID: presentation, active: true, receivedAt: nil, now: 11))
        for stale in [13.0, 9.0, Double.infinity, Double.nan] {
            precondition(!AudioRecordingIdentity.canStart(presentationID: presentation, currentID: presentation, active: true, receivedAt: 10, now: stale))
        }
        precondition(!identity.belongs(to: presentation))
        identity.begin(presentationID: presentation)
        let recording = identity.recordingID!
        precondition(identity.belongs(to: presentation))
        precondition(!identity.belongs(to: UUID()))
        precondition(!identity.belongs(to: nil))
        identity.begin(presentationID: nil)
        precondition(identity.recordingID != recording)
        precondition(!identity.belongs(to: presentation))
        let oldRecorder = NSObject(), newRecorder = NSObject()
        precondition(AudioRecordingIdentity.isCurrentRecorder(newRecorder, current: newRecorder))
        precondition(!AudioRecordingIdentity.isCurrentRecorder(oldRecorder, current: newRecorder))
        precondition(!AudioRecordingIdentity.isCurrentRecorder(oldRecorder, current: nil))
        try AudioAPI.validateSessionID(recording.uuidString.lowercased(), expected: recording)
        try AudioAPI.validateSessionID(recording.uuidString.uppercased(), expected: recording)
        for invalid in [UUID().uuidString, "", "not-a-uuid"] {
            do {
                try AudioAPI.validateSessionID(invalid, expected: recording)
                fatalError("Mismatched session response was accepted")
            } catch is AudioAPIError { }
        }
        print("PASS: audio presentation identity, late recorder callbacks and response UUID validation (no recording/network)")
    }
}
