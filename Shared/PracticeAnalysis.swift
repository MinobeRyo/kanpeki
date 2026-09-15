import Foundation

/// Seconds relative to one recording, never the presentation timer or camera clock.
struct PracticeAudioRange: Codable, Equatable {
    let recordingID: UUID
    let startSeconds: Double
    let endSeconds: Double
    var isValid: Bool {
        startSeconds.isFinite && endSeconds.isFinite && startSeconds >= 0 &&
        startSeconds < endSeconds && endSeconds <= 900.001001
    }
}

/// Source material, never instructions. Recording/capture clocks are independent of the timer.
struct PracticeFact: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let text: String
    var audioRange: PracticeAudioRange? = nil
    var isValid: Bool {
        !id.isEmpty && id.utf8.count <= 160 && ["audio", "camera", "slide", "timer"].contains(kind) &&
        !text.isEmpty && text.utf8.count <= 64 * 1024 &&
        (audioRange.map { $0.isValid && kind == "audio" && id.hasPrefix("audio.\($0.recordingID.uuidString.lowercased()).") } ?? true)
    }
    var isCoachingTarget: Bool {
        if kind == "slide" { return id.range(of: #"^slide\.[1-9][0-9]*\z"#, options: .regularExpression) != nil }
        if kind == "timer" { return ["timer.observed", "timer.comparison"].contains(id) }
        guard kind == "audio" else { return false }
        return id.range(of: #"^audio\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(transcript|pace|quiet|filler)\.[0-9]+\z"#, options: .regularExpression) != nil
    }
    static func timerComparison(elapsedSeconds: Double, durationSeconds: Double?) -> Self? {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0,
              let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else { return nil }
        let difference = elapsedSeconds - durationSeconds
        return Self(id: "timer.comparison", kind: "timer",
                    text: "発表全体の実測時間: \(elapsedSeconds)秒。予定時間: \(durationSeconds)秒。実測−予定: \(difference >= 0 ? "+" : "")\(difference)秒。正は予定超過、負は予定未満です。スライド別の時間や修正による短縮量ではありません。")
    }
    static func valid(_ facts: [Self], maxBytes: Int = 2 * 1024 * 1024) -> Bool {
        facts.count <= 4096 && facts.allSatisfy(\.isValid) && Set(facts.map(\.id)).count == facts.count &&
        (try? JSONEncoder().encode(facts).count).map { $0 <= maxBytes } == true
    }
}

struct PhoneAnalysisEvidence: Codable, Equatable {
    let sharingID: UUID
    let presentationID: UUID
    let sequence: UInt64
    let recordingID: UUID?
    let cameraID: UUID?
    let facts: [PracticeFact]
    var isValid: Bool {
        sequence > 0 && PracticeFact.valid(facts, maxBytes: 180 * 1024) && facts.allSatisfy {
            ($0.kind == "audio" && recordingID != nil && $0.id.hasPrefix("audio.\(recordingID!.uuidString.lowercased()).")) ||
            ($0.kind == "camera" && cameraID != nil && $0.id.hasPrefix("phoneCamera.\(cameraID!.uuidString.lowercased())."))
        }
    }
}

struct PhoneEvidenceReceiver {
    private(set) var latest: PhoneAnalysisEvidence?
    mutating func accept(_ value: PhoneAnalysisEvidence, sharingID: UUID?, presentationID: UUID?) -> Bool {
        guard value.isValid, value.sharingID == sharingID, value.presentationID == presentationID,
              latest.map({ $0.sharingID != value.sharingID || $0.presentationID != value.presentationID || value.sequence > $0.sequence }) ?? true else { return false }
        latest = value
        return true
    }
}

struct PracticeAnalysisRequest: Codable, Equatable {
    let schemaVersion: Int
    let requestID: UUID
    let presentationID: UUID
    let createdAt: Double
    let facts: [PracticeFact]
    let instructions: String
    var isValid: Bool { [1, 2].contains(schemaVersion) && createdAt.isFinite && !facts.isEmpty && PracticeFact.valid(facts) }
}

struct PracticeCoachingStep: Codable, Equatable {
    let targetEvidenceID: String
    let change: String
    let rehearsal: String
    var isValid: Bool {
        !targetEvidenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetEvidenceID.utf8.count <= 160 &&
        [change, rehearsal].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 600 }
    }
}

struct PracticeAnalysisItem: Codable, Equatable {
    let kind: String
    let text: String
    let evidenceIDs: [String]
    // Populated by the native client from the frozen request, never trusted from GPT.
    var sources: [String]?
    var coaching: PracticeCoachingStep? = nil
    var isValid: Bool {
        ["strength", "improvement", "limitation"].contains(kind) &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 1200 &&
        (1...8).contains(evidenceIDs.count) && Set(evidenceIDs).count == evidenceIDs.count &&
        evidenceIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 160 } &&
        (sources == nil || (sources!.count <= 8 && sources!.allSatisfy { $0.utf16.count <= 700 })) &&
        (coaching.map { $0.isValid && kind == "improvement" && evidenceIDs.contains($0.targetEvidenceID) } ?? true)
    }
}

struct PracticeAnalysisResult: Codable, Equatable {
    let requestID: UUID
    let presentationID: UUID
    var items: [PracticeAnalysisItem]
    var isValid: Bool { (1...8).contains(items.count) && items.allSatisfy(\.isValid) }
    var firstImprovementIndex: Int? { items.firstIndex { $0.kind == "improvement" } }
    var remainingFeedbackIndices: [Int] { items.indices.filter { $0 != firstImprovementIndex } }
    func validated(for request: PracticeAnalysisRequest) -> Self? {
        guard isValid, request.isValid, requestID == request.requestID,
              presentationID == request.presentationID else { return nil }
        let facts = Dictionary(uniqueKeysWithValues: request.facts.map { ($0.id, $0.text) })
        guard items.allSatisfy({ $0.evidenceIDs.allSatisfy { facts[$0] != nil } }) else { return nil }
        let targets = Set(request.facts.filter(\.isCoachingTarget).map(\.id))
        guard items.allSatisfy({ $0.coaching.map { targets.contains($0.targetEvidenceID) } ?? true }) else { return nil }
        if request.schemaVersion == 2 {
            let improvements = items.filter { $0.kind == "improvement" }
            guard improvements.count <= 3, improvements.allSatisfy({ $0.coaching != nil }) else { return nil }
        }
        var result = self
        result.items = items.map { item in
            var item = item
            item.sources = item.evidenceIDs.map { id in
                var excerpt = ""
                var units = 0
                for character in facts[id] ?? "" {
                    let length = String(character).utf16.count
                    guard units + length <= 700 else { break }
                    excerpt.append(character)
                    units += length
                }
                return excerpt
            }
            return item
        }
        return result
    }
}
