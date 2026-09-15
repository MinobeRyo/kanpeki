import Foundation

@main
struct NotificationTests {
    static func main() {
        let id = UUID()
        var input = PresentationNotificationInput(sessionID: id, isExpired: false, isPresenting: true)
        var policy = PresentationNotificationPolicy()
        precondition(!policy.consumeTimeExpiration(input))
        input.isExpired = true
        precondition(policy.consumeTimeExpiration(input))
        precondition(!policy.consumeTimeExpiration(input))
        input.isConnected = false
        precondition(!input.showsTimeExpired)
        input.isConnected = true
        precondition(input.showsTimeExpired && !policy.consumeTimeExpiration(input))
        input.sessionID = UUID()
        precondition(policy.consumeTimeExpiration(input))
        input.sessionID = id
        precondition(!policy.consumeTimeExpiration(input), "Old sessions cannot replay")
        for key in [\PresentationNotificationInput.isForeground, \.isConnected, \.isPresenting] {
            var suppressed = input
            suppressed.sessionID = UUID()
            suppressed[keyPath: key] = false
            precondition(!policy.consumeTimeExpiration(suppressed))
            suppressed[keyPath: key] = true
            precondition(!policy.consumeTimeExpiration(suppressed))
        }
        input.sessionID = UUID()
        input.isQuestionMode = true
        precondition(!input.showsTimeExpired && !policy.consumeTimeExpiration(input))
        input.isQuestionMode = false
        precondition(!policy.consumeTimeExpiration(input))
        input.sessionID = nil
        precondition(!input.showsTimeExpired && !policy.consumeTimeExpiration(input))

        let interruptedID = UUID()
        input = PresentationNotificationInput(sessionID: interruptedID, isExpired: false, isPresenting: true)
        precondition(!policy.consumeTimeExpiration(input))
        input.sessionID = nil; input.isConnected = false
        precondition(!policy.consumeTimeExpiration(input))
        input.sessionID = interruptedID; input.isConnected = true; input.isExpired = true
        precondition(!policy.consumeTimeExpiration(input), "Do not vibrate late when first post-reconnect sample is expired")
        input = PresentationNotificationInput(sessionID: UUID(), isExpired: false, isPresenting: true)
        input.isForeground = false
        precondition(!policy.consumeTimeExpiration(input))
        input.isForeground = true
        precondition(!policy.consumeTimeExpiration(input))
        input.isExpired = true
        precondition(policy.consumeTimeExpiration(input), "Return before expiry allows the future on-time alert")

        input = PresentationNotificationInput(sessionID: UUID(), isExpired: false, isPresenting: true)
        func speech(_ enabled: Bool = true, _ now: Double = 0, _ interval: Double = 60) -> Bool {
            policy.consumeSpeechNotice(input, analysisEnabled: enabled, now: now, minimumInterval: interval)
        }
        precondition(!speech(false))
        precondition(speech())
        precondition(!speech(true, 59))
        precondition(!speech(true, -1))
        precondition(speech(true, 60))
        precondition(!speech(true, .nan))
        precondition(!speech(true, 120, 0))
        input.isQuestionMode = true
        precondition(!speech(true, 120))
        input.isQuestionMode = false
        input.isExpired = true
        precondition(!speech(true, 120))
        input.isExpired = false
        input.isForeground = false
        precondition(!speech(true, 120))
        input.isForeground = true
        input.isConnected = false
        precondition(!speech(true, 120))
        input.isConnected = true
        input.isPresenting = false
        precondition(!speech(true, 120))
        print("PASS: notification expiration, suppression, reconnect, speech gating and throttling")
    }
}
