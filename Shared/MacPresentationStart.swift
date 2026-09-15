import Foundation

/// Immutable user intent; asynchronous preparation must not apply to a changed selection/session.
struct MacPresentationStart: Equatable {
    let id = UUID()
    let windowID: UInt32
    let documentPath: String?
    let timerSessionID: UUID
    let timerRevision: UInt64
    let requiresPowerPoint: Bool
    var requiredConnectionID: UUID? = nil

    func matches(windowID: UInt32?, documentPath: String?, timer: PresentationTimerSnapshot?) -> Bool {
        self.windowID == windowID && self.documentPath == documentPath &&
        timer?.sessionID == timerSessionID && timer?.revision == timerRevision &&
        timer?.phase == .ready && timer?.durationSeconds != nil && timer?.isFinishing != true
    }

    func canStart(activeIntentID: UUID?, connectionID: UUID?, windowID: UInt32?, documentPath: String?, timer: PresentationTimerSnapshot?,
                  sharing: Bool, frameReady: Bool, hasImage: Bool, controlsReady: Bool) -> Bool {
        activeIntentID == id && (requiredConnectionID == nil || requiredConnectionID == connectionID) &&
        matches(windowID: windowID, documentPath: documentPath, timer: timer) &&
        sharing && frameReady && hasImage && (!requiresPowerPoint || controlsReady)
    }
}

enum MacPresentationKeyboard {
    static func canNavigate(isKeyWindow: Bool, editingText: Bool, hasSheet: Bool,
                            hasModifiers: Bool, isRepeating: Bool) -> Bool {
        isKeyWindow && !editingText && !hasSheet && !hasModifiers && !isRepeating
    }
}
