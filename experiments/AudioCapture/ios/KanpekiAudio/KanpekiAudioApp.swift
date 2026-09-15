import SwiftUI

@main
struct KanpekiAudioApp: App {
    @StateObject private var recorder = RecorderModel()
    var body: some Scene {
        WindowGroup { AudioCaptureView(model: recorder) }
    }
}
