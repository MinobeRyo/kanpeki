import Foundation

@main struct AudioReviewChecks {
    static func main() {
        let normal = AudioReviewRange(candidateStart: 10, candidateEnd: 11, duration: 20)!
        precondition(normal.start == 8 && normal.end == 13)
        let first = AudioReviewRange(candidateStart: 0, candidateEnd: 1, duration: 20)!
        precondition(first.start == 0 && first.end == 3)
        let last = AudioReviewRange(candidateStart: 19, candidateEnd: 25, duration: 20)!
        precondition(last.start == 17 && last.end == 20)
        for (start, end, duration) in [(20.0, 21.0, 20.0), (-1, 1, 20), (5, 4, 20), (0, 1, 0), (.nan, 1, 20), (0, .infinity, 20), (0, 1, .infinity)] {
            precondition(AudioReviewRange(candidateStart: start, candidateEnd: end, duration: duration) == nil)
        }
        func report(fillers: [FillerCandidate]?, quiet: [QuietInterval], duration: Double = 20) -> AudioReport {
            AudioReport(duration: duration, transcriptionStatus: fillers == nil ? "not_configured" : "complete",
                        averageCharactersPerMinute: nil, quietSeconds: quiet.reduce(0) { $0 + $1.duration },
                        quietIntervals: quiet, fillerCandidates: fillers, pace: nil, transcript: nil,
                        slides: [], warnings: [])
        }
        let quiet = QuietInterval(start: 2, end: 4, duration: 2)
        let noTranscription = report(fillers: nil, quiet: [quiet])
        let quietOnly = AudioReviewChapter.make(from: noTranscription)
        precondition(noTranscription.fillerCandidates == nil) // Unmeasured is not converted to zero.
        precondition(quietOnly.count == 1 && quietOnly[0].kind == .quiet && quietOnly[0].slide == nil)
        precondition(AudioReviewRange(candidateStart: quietOnly[0].start, candidateEnd: quietOnly[0].end,
                                      duration: 20)?.start == 0)
        let filler = FillerCandidate(text: "えー", context: "元の発話", start: 2, end: 4, slide: 3)
        let earlier = FillerCandidate(text: "えっと", context: "先の発話", start: 0, end: 1, slide: nil)
        let mixed = AudioReviewChapter.make(from: report(fillers: [filler, earlier, filler], quiet: [quiet]))
        precondition(mixed.count == 4)
        precondition(mixed.map(\.start) == [0, 2, 2, 2])
        precondition(mixed.map(\.id) == ["0:1", "0:0", "0:2", "1:0"])
        precondition(Set(mixed.map(\.id)).count == 4) // Duplicate timestamps/text are distinct source observations.
        precondition(mixed[1].slide == 3 && mixed[1].context == "元の発話")
        precondition(mixed == AudioReviewChapter.make(from: report(fillers: [filler, earlier, filler], quiet: [quiet])))
        precondition(AudioReviewChapter.make(from: report(fillers: [], quiet: [])).isEmpty)
        precondition(AudioReviewChapter.make(from: report(fillers: nil, quiet: [])).isEmpty)
        precondition(AudioReviewChapter.make(from: report(fillers: nil, quiet: [quiet], duration: .infinity)).isEmpty)
        let invalid = [QuietInterval(start: .nan, end: 3, duration: 1),
                       QuietInterval(start: -1, end: 3, duration: 4),
                       QuietInterval(start: 5, end: 4, duration: 1),
                       QuietInterval(start: 19, end: 21, duration: 2)]
        precondition(AudioReviewChapter.make(from: report(fillers: nil, quiet: invalid)).isEmpty)
        let roundedEnd = QuietInterval(start: 19, end: 20.001, duration: 1.001)
        precondition(AudioReviewChapter.make(from: report(fillers: nil, quiet: [roundedEnd])).count == 1)

        var gate = AudioReviewPlaybackGate()
        let recording = UUID(), context = UUID()
        let old = gate.begin(recordingID: recording, contextID: context)
        precondition(gate.accepts(old, recordingID: recording, contextID: context))
        let next = gate.begin(recordingID: recording, contextID: context)
        precondition(!gate.accepts(old, recordingID: recording, contextID: context))
        precondition(gate.accepts(next, recordingID: recording, contextID: context))
        precondition(!gate.accepts(next, recordingID: UUID(), contextID: context))
        precondition(!gate.accepts(next, recordingID: nil, contextID: context))
        precondition(!gate.accepts(next, recordingID: recording, contextID: UUID()))
        gate.invalidate()
        precondition(!gate.accepts(next, recordingID: recording, contextID: context))
        let restarted = gate.begin(recordingID: recording, contextID: context)
        precondition(!gate.accepts(next, recordingID: recording, contextID: context))
        precondition(gate.accepts(restarted, recordingID: recording, contextID: context))
        print("PASS: audio review bounds, mixed/quiet-only chapters, duplicate ordering, unmeasured and stale playback callbacks (synthetic)")
    }
}
