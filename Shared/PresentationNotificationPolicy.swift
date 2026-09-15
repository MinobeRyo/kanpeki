import Foundation

/// Inputs are current, confirmed presentation state; this type does not run a timer.
struct PresentationNotificationInput: Equatable {
    var sessionID: UUID?
    var isExpired: Bool
    var isPresenting: Bool
    var isQuestionMode = false
    var isForeground = true
    var isConnected = true

    var showsTimeExpired: Bool {
        sessionID != nil && isExpired && isPresenting && !isQuestionMode && isConnected
    }
}

/// Keep this policy alive across view redraws, interruptions and reconnects.
struct PresentationNotificationPolicy {
    private var observedExpirations = Set<UUID>()
    private var lastSpeechNotification: [UUID: TimeInterval] = [:]

    mutating func consumeTimeExpiration(_ input: PresentationNotificationInput) -> Bool {
        guard let id = input.sessionID, input.isExpired else { return false }
        // Consume even while inactive. Returning from Q&A/background must not replay an alert.
        guard observedExpirations.insert(id).inserted else { return false }
        return input.showsTimeExpired && input.isForeground
    }

    /// Hook for a future explicitly enabled speech-analysis notifier. No analyzer is enabled here.
    /// Caller supplies a monotonic clock and an agreed minimum interval, not wall time.
    mutating func consumeSpeechNotice(
        _ input: PresentationNotificationInput,
        analysisEnabled: Bool,
        now: TimeInterval,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard let id = input.sessionID, analysisEnabled, input.isPresenting,
              !input.isQuestionMode, input.isForeground, input.isConnected,
              !input.isExpired, now.isFinite, minimumInterval.isFinite,
              minimumInterval > 0 else { return false }
        if let last = lastSpeechNotification[id], now - last < minimumInterval { return false }
        lastSpeechNotification[id] = now
        return true
    }
}
