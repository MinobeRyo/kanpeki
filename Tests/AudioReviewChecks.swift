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
        print("Audio review bounds: 10 cases passed")
    }
}
