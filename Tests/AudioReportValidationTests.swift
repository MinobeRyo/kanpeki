import Foundation

@main struct AudioReportValidationTests {
    static func main() throws {
        let base: [String: Any] = [
            "duration": 10.0, "transcription_status": "not_configured",
            "quiet_seconds": 2.0, "quiet_intervals": [["start": 1.0, "end": 3.0, "duration": 2.0]],
            "filler_candidates": NSNull(), "pace": NSNull(), "transcript": NSNull(),
            "average_characters_per_minute": NSNull(), "slides": [], "warnings": []
        ]
        func decode(_ json: [String: Any]) throws -> AudioReport {
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AudioReport.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let unmeasured = try decode(base)
        try unmeasured.validate()
        precondition(unmeasured.fillerCandidates == nil && unmeasured.pace == nil && unmeasured.averageCharactersPerMinute == nil)
        func rejected(_ key: String, _ value: Any) throws {
            var json = base; json[key] = value
            do { try decode(json).validate(); fatalError("Corrupt report accepted: \(key)") }
            catch is AudioAPIError { }
        }
        for duration in [-1.0, 0.0, 0.099, 900.01, 1e30] { try rejected("duration", duration) }
        try rejected("quiet_seconds", -1.0)
        try rejected("quiet_seconds", 11.0)
        try rejected("quiet_seconds", 0.0)
        try rejected("average_characters_per_minute", -1.0)
        try rejected("transcription_status", "unknown")
        try rejected("quiet_intervals", [["start": 0, "end": 1e30, "duration": 1]])
        try rejected("quiet_intervals", [["start": -1, "end": 1, "duration": 2]])
        try rejected("quiet_intervals", [["start": 3, "end": 1, "duration": 2]])
        try rejected("quiet_intervals", [["start": 1, "end": 3, "duration": 9]])
        try rejected("quiet_intervals", [["start": 3, "end": 4, "duration": 1], ["start": 1, "end": 2, "duration": 1]])
        try rejected("pace", [["start": 1, "end": 2, "characters_per_minute": -1]])
        try rejected("transcript", [["start": 0, "end": 11, "text": "bad"]])
        try rejected("filler_candidates", [["start": 0, "end": 11, "text": "えー", "context": "test", "slide": 1]])
        try rejected("slides", [["start": 0, "end": 1, "duration": 1, "slide": 0]])
        // Backend can round duration down 0.5 ms, and a slide event at recording end has zero length.
        var rounding = base
        rounding["slides"] = [["slide": 1, "start": 0, "end": 10.0004, "duration": 10], ["slide": 2, "start": 10.0004, "end": 10.0004, "duration": 0]]
        try decode(rounding).validate()
        precondition(AudioTimeText.clock(61.9) == "01:01")
        for invalid in [1e30, Double.infinity, Double.nan, -1.0] { precondition(AudioTimeText.clock(invalid) == "未計測") }
        for invalid in [Double.infinity, Double.nan] {
            let report = AudioReport(duration: 10, transcriptionStatus: "complete", averageCharactersPerMinute: invalid,
                quietSeconds: 0, quietIntervals: [], fillerCandidates: nil, pace: nil, transcript: nil, slides: [], warnings: [])
            do { try report.validate(); fatalError("Nonfinite metric accepted") } catch is AudioAPIError { }
        }
        print("PASS: bounded audio reports, malformed timestamps/metrics, nil preservation and safe clock (synthetic only)")
    }
}
