import Foundation

@main
struct ContractSmoke {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let api = try AudioAPI(address: arguments[1], token: arguments[2])
        let health = try await api.health()
        let id = UUID()
        let audio = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
        try await api.submit(id: id, audio: audio, slides: [SlideEvent(at: 0, slide: 1)])
        // Retry the exact same payload to verify client/server idempotency.
        try await api.submit(id: id, audio: audio, slides: [SlideEvent(at: 0, slide: 1)])
        for _ in 0..<360 {
            let job = try await api.result(id: id)
            if job.status == "failed" { throw AudioAPIError.message(job.error ?? "Failed") }
            if let report = job.report {
                precondition(report.duration > 0)
                precondition(report.slides.count == 1)
                precondition(report.slides[0].slide == 1)
                precondition(!report.warnings.isEmpty)
                if health.transcriptionReady {
                    precondition(report.transcriptionStatus == "complete", "Actual model did not produce a transcript")
                    precondition(!(report.transcript ?? []).isEmpty)
                    precondition(report.averageCharactersPerMinute != nil)
                } else {
                    precondition(report.transcriptionStatus == "not_configured")
                    precondition(report.averageCharactersPerMinute == nil)
                    precondition(report.fillerCandidates == nil)
                }
                print("PASS: Swift upload → Python analysis → Swift result decode")
                print("Duration: \(report.duration)s; recognition: \(report.transcriptionStatus); slide visits: \(report.slides.count)")
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw AudioAPIError.message("Timed out")
    }
}
