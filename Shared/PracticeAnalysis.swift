import Foundation

/// Source material, never instructions. Recording/capture clocks are independent of the timer.
struct PracticeFact: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let text: String
    var isValid: Bool {
        !id.isEmpty && id.utf8.count <= 160 && ["audio", "camera", "slide", "timer"].contains(kind) &&
        !text.isEmpty && text.utf8.count <= 64 * 1024
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
    var isValid: Bool { schemaVersion == 1 && createdAt.isFinite && !facts.isEmpty && PracticeFact.valid(facts) }
}

struct PracticeAnalysisItem: Codable, Equatable {
    let kind: String
    let text: String
    let evidenceIDs: [String]
    // Populated by the native client from the frozen request, never trusted from GPT.
    var sources: [String]?
    var isValid: Bool {
        ["strength", "improvement", "limitation"].contains(kind) &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 1200 &&
        (1...8).contains(evidenceIDs.count) && Set(evidenceIDs).count == evidenceIDs.count &&
        evidenceIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 160 } &&
        (sources == nil || (sources!.count <= 8 && sources!.allSatisfy { $0.count <= 700 }))
    }
}

struct PracticeAnalysisResult: Codable, Equatable {
    let requestID: UUID
    let presentationID: UUID
    var items: [PracticeAnalysisItem]
    var isValid: Bool { (1...8).contains(items.count) && items.allSatisfy(\.isValid) }
    func validated(for request: PracticeAnalysisRequest) -> Self? {
        guard isValid, request.isValid, requestID == request.requestID,
              presentationID == request.presentationID else { return nil }
        let facts = Dictionary(uniqueKeysWithValues: request.facts.map { ($0.id, $0.text) })
        guard items.allSatisfy({ $0.evidenceIDs.allSatisfy { facts[$0] != nil } }) else { return nil }
        var result = self
        result.items = items.map { item in
            var item = item
            item.sources = item.evidenceIDs.map { String((facts[$0] ?? "").prefix(700)) }
            return item
        }
        return result
    }
}
