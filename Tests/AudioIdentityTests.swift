import Foundation

@main struct AudioIdentityTests {
    static func main() throws {
        var identity = AudioRecordingIdentity()
        let presentation = UUID()
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
