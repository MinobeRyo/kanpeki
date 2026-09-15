import Foundation

enum TimerClock {
    private static let origin = ContinuousClock.now
    static var now: TimeInterval {
        let value = origin.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}

enum PresentationTimerPhase: String, Codable { case ready, running, paused, ended }
enum PresentationTimerAction: String, Codable { case configure, start, pause, resume, end, reset }

struct PresentationTimerSnapshot: Codable, Equatable {
    var sessionID: UUID
    var revision: UInt64
    var sequence: UInt64
    var durationSeconds: Double?
    var elapsedSeconds: Double
    var phase: PresentationTimerPhase
    var isFinishing: Bool? = nil

    var isValid: Bool {
        elapsedSeconds.isFinite && elapsedSeconds >= 0 &&
        (durationSeconds == nil || (durationSeconds!.isFinite && (1...86400).contains(durationSeconds!))) &&
        (phase == .ready || durationSeconds != nil)
    }

    func elapsed(at now: TimeInterval, receivedAt: TimeInterval) -> Double {
        elapsedSeconds + (phase == .running ? min(3, max(0, now - receivedAt)) : 0)
    }
}

/// Sequence belongs to the host connection, not just one presentation session.
struct PresentationTimerReceiver {
    private var lastSequence: UInt64?
    mutating func accept(_ snapshot: PresentationTimerSnapshot?) -> Bool {
        guard let snapshot else { return lastSequence == nil }
        guard snapshot.isValid, lastSequence.map({ snapshot.sequence > $0 }) ?? true else { return false }
        lastSequence = snapshot.sequence
        return true
    }
}

struct PresentationTimerCommand: Codable {
    var sessionID: UUID
    var revision: UInt64
    var sequence: UInt64
    var action: PresentationTimerAction
    var durationSeconds: Double? = nil
}

/// Mac owns the stopwatch. Only elapsed durations, never device wall clocks, cross the wire.
struct PresentationTimerAuthority {
    private(set) var sessionID = UUID()
    private(set) var revision: UInt64 = 0
    private(set) var phase: PresentationTimerPhase = .ready
    private(set) var durationSeconds: Double?
    private var accumulated: Double = 0
    private var runningSince: Double?
    private var sequence: UInt64 = 0
    private var leases: [(sequence: UInt64, at: Double)] = []

    func elapsed(at now: Double) -> Double {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }

    mutating func snapshot(at now: Double) -> PresentationTimerSnapshot {
        sequence &+= 1
        leases.append((sequence, now))
        leases = Array(leases.filter { now - $0.at <= 3 }.suffix(32))
        return PresentationTimerSnapshot(sessionID: sessionID, revision: revision, sequence: sequence,
            durationSeconds: durationSeconds, elapsedSeconds: elapsed(at: now), phase: phase)
    }

    /// Stale/repeated requests cannot restart, unpause, or end a different presentation.
    @discardableResult mutating func apply(_ command: PresentationTimerCommand, at now: Double) -> Bool {
        guard now.isFinite, command.sessionID == sessionID, command.revision == revision,
              leases.contains(where: { $0.sequence == command.sequence && now >= $0.at && now - $0.at <= 3 }) else { return false }
        switch command.action {
        case .configure:
            guard phase == .ready, let seconds = command.durationSeconds,
                  seconds.isFinite, (1...86400).contains(seconds) else { return false }
            durationSeconds = seconds
        case .start:
            guard phase == .ready, durationSeconds != nil else { return false }
            runningSince = now
            phase = .running
        case .pause:
            guard phase == .running else { return false }
            accumulated = elapsed(at: now)
            runningSince = nil
            phase = .paused
        case .resume:
            guard phase == .paused else { return false }
            runningSince = now
            phase = .running
        case .end:
            guard phase == .running || phase == .paused else { return false }
            accumulated = elapsed(at: now)
            runningSince = nil
            phase = .ended
        case .reset:
            guard phase == .ended else { return false }
            sessionID = UUID()
            accumulated = 0
            phase = .ready
            leases = []
        }
        revision &+= 1
        return true
    }
}

enum PresentationTimerText {
    static func time(_ seconds: Double) -> String {
        let value = Int(min(35999999, max(0, seconds.isFinite ? seconds.rounded(.up) : 0)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
