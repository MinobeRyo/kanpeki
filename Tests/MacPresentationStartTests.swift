import Foundation

@main struct MacPresentationStartTests {
    static func main() {
        var timer = PresentationTimerSnapshot(sessionID: UUID(), revision: 1, sequence: 1,
            durationSeconds: 60, elapsedSeconds: 0, phase: .ready)
        let connected = UUID()
        var connectionID: UUID? = connected
        let intent = MacPresentationStart(windowID: 7, documentPath: "/slides.pptx",
            timerSessionID: timer.sessionID, timerRevision: timer.revision, requiresPowerPoint: true,
            requiredConnectionID: connected)
        var activeID: UUID? = intent.id
        func permits(window: UInt32? = 7, path: String? = "/slides.pptx", sharing: Bool = true,
                     frame: Bool = true, image: Bool = true, control: Bool = true) -> Bool {
            intent.canStart(activeIntentID: activeID, connectionID: connectionID, windowID: window, documentPath: path, timer: timer,
                sharing: sharing, frameReady: frame, hasImage: image, controlsReady: control)
        }
        precondition(permits())
        precondition(!permits(window: 8) && !permits(window: nil))
        precondition(!permits(path: "/other.pptx"))
        precondition(!permits(sharing: false))
        precondition(!permits(frame: false) && !permits(image: false))
        precondition(!permits(control: false))
        activeID = nil; precondition(!permits()) // Cancelled, even if a late image succeeds.
        activeID = UUID(); precondition(!permits()) // A different attempt cannot complete this one.
        activeID = intent.id
        connectionID = nil; precondition(!permits()) // Required phone disconnected.
        connectionID = UUID(); precondition(!permits()) // Reconnection is a different intent.
        connectionID = connected; precondition(permits())
        timer.revision += 1; precondition(!permits()); timer.revision -= 1
        timer.phase = .running; precondition(!permits()); timer.phase = .ready
        timer.isFinishing = true; precondition(!permits()); timer.isFinishing = false
        timer.durationSeconds = nil; precondition(!permits()); timer.durationSeconds = 60
        timer.sessionID = UUID(); precondition(!permits())
        let displayOnly = MacPresentationStart(windowID: 7, documentPath: nil,
            timerSessionID: timer.sessionID, timerRevision: timer.revision, requiresPowerPoint: false)
        precondition(displayOnly.canStart(activeIntentID: displayOnly.id, connectionID: nil, windowID: 7, documentPath: nil, timer: timer,
            sharing: true, frameReady: true, hasImage: true, controlsReady: false))
        func keys(editing: Bool = false, sheet: Bool = false, modifier: Bool = false,
                  keyWindow: Bool = true, repeated: Bool = false) -> Bool {
            MacPresentationKeyboard.canNavigate(isKeyWindow: keyWindow, editingText: editing,
                hasSheet: sheet, hasModifiers: modifier, isRepeating: repeated)
        }
        precondition(keys() && !keys(editing: true) && !keys(sheet: true))
        precondition(!keys(modifier: true) && !keys(keyWindow: false) && !keys(repeated: true))
        print("PASS: Mac unified-start validation, changed intent, cancellation and keyboard editing guards")
    }
}
