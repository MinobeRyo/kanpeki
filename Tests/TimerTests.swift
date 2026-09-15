import Foundation

@main struct TimerTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message); checks += 1; print("PASS: \(message)")
    }
    static func main() throws {
        var timer = PresentationTimerAuthority()
        func command(_ action: PresentationTimerAction, _ snapshot: PresentationTimerSnapshot, seconds: Double? = nil) -> PresentationTimerCommand {
            PresentationTimerCommand(sessionID: snapshot.sessionID, revision: snapshot.revision, sequence: snapshot.sequence, action: action, durationSeconds: seconds)
        }
        var sample = timer.snapshot(at: 0)
        expect(sample.durationSeconds == nil, "no invented default duration")
        expect(!PresentationState(timer: sample).allowsSlideInteraction, "preparation does not send slide controls")
        expect(!timer.apply(command(.start, sample), at: 0), "cannot start unconfigured")
        expect(!timer.apply(command(.configure, sample, seconds: .infinity), at: 0), "reject invalid duration")
        expect(!timer.apply(command(.configure, sample, seconds: 0), at: 0), "reject zero duration")
        expect(timer.apply(command(.configure, sample, seconds: 60), at: 0), "configure duration")
        expect(!timer.apply(command(.start, sample), at: 0), "stale revision rejected")
        sample = timer.snapshot(at: 10)
        let start = command(.start, sample)
        expect(timer.apply(start, at: 10), "start exactly once")
        expect(!timer.apply(start, at: 11), "double start rejected")
        expect(timer.elapsed(at: 20) == 10, "elapsed uses monotonic difference")
        sample = timer.snapshot(at: 20)
        expect(timer.apply(command(.pause, sample), at: 21), "pause")
        expect(timer.elapsed(at: 100) == 11, "paused time does not grow")
        sample = timer.snapshot(at: 100)
        expect(timer.apply(command(.resume, sample), at: 100), "resume")
        expect(timer.elapsed(at: 130) == 41, "resume preserves elapsed time")
        sample = timer.snapshot(at: 140)
        expect(!timer.apply(command(.pause, sample), at: 144), "expired snapshot lease rejects buffered control")
        sample = timer.snapshot(at: 200)
        expect(sample.elapsedSeconds == 111 && sample.phase == .running, "expiry never ends presentation")
        expect(PresentationState(timer: sample).allowsSlideInteraction, "expired running timer keeps slide controls")
        expect(sample.elapsed(at: 505, receivedAt: 500) == 114, "stale phone estimate capped at three seconds")
        expect(timer.elapsed(at: 202) == 113, "opening/cancelling confirmation does not pause")
        expect(timer.apply(command(.end, sample), at: 202), "explicit finish")
        expect(timer.elapsed(at: 500) == 113, "ended elapsed fixed")
        sample = timer.snapshot(at: 500)
        let oldSession = sample.sessionID
        expect(timer.apply(command(.reset, sample), at: 500), "return to preparation")
        sample = timer.snapshot(at: 501)
        expect(sample.sessionID != oldSession && sample.elapsedSeconds == 0 && sample.durationSeconds == 60, "reset changes session and retains chosen duration")
        expect(!timer.apply(start, at: 501), "old session command rejected")
        var receiver = PresentationTimerReceiver()
        let previous = PresentationTimerSnapshot(sessionID: oldSession, revision: 0, sequence: sample.sequence - 1, durationSeconds: 60, elapsedSeconds: 10, phase: .running)
        expect(receiver.accept(previous) && receiver.accept(sample), "receive old then new session")
        expect(!receiver.accept(previous), "late previous session cannot replace current session")
        expect(!receiver.accept(nil), "missing timer cannot erase supported host state")
        receiver = PresentationTimerReceiver()
        expect(receiver.accept(previous), "new connection accepts new host sequence")
        let encoded = try JSONEncoder().encode(WireMessage(kind: "state", state: PresentationState(timer: sample)))
        expect(WireCodec.decode(encoded)?.state?.timer == sample, "timer state wire roundtrip")
        let wire = WireMessage(kind: "timerControl", timerCommand: command(.start, sample))
        expect(WireCodec.decode(try JSONEncoder().encode(wire))?.timerCommand?.action == .start, "timer command wire roundtrip")
        let old = WireMessage(kind: "state", state: PresentationState())
        expect(WireCodec.decode(try JSONEncoder().encode(old))?.state?.timer == nil, "older state without timer remains compatible")
        var invalid = sample; invalid.elapsedSeconds = -1
        expect(WireCodec.decode(try JSONEncoder().encode(WireMessage(kind: "state", state: PresentationState(timer: invalid)))) == nil, "invalid timer sample rejected")
        expect(PresentationTimerText.time(0) == "00:00" && PresentationTimerText.time(60.1) == "01:01", "remaining display rounds up")
        var controls = PresentationState(slideIndex: 2, totalSlides: 3, canControl: true, isSharing: true, timer: sample)
        expect(!controls.canMoveSlide(.next), "UI disables slide buttons in preparation")
        controls.timer?.phase = .running
        expect(controls.canMoveSlide(.next) && controls.canMoveSlide(.previous), "UI enables both directions during presentation")
        controls.timer?.phase = .paused
        expect(controls.canMoveSlide(.next), "UI keeps manual movement enabled while paused")
        controls.timer?.phase = .ended
        expect(!controls.canMoveSlide(.next), "UI disables movement after end")
        controls.timer?.phase = .running
        controls.slideIndex = 1
        expect(!controls.canMoveSlide(.previous), "UI cannot move before first slide")
        controls.slideIndex = 3
        expect(!controls.canMoveSlide(.next), "UI cannot move after last slide")
        controls.slideIndex = 4
        expect(!controls.canMoveSlide(.previous), "invalid slide index is not actionable")
        controls.slideIndex = 2; controls.isSharing = false
        expect(!controls.canMoveSlide(.next), "stopped sharing disables UI movement")
        print("\(checks) timer checks passed")
    }
}
