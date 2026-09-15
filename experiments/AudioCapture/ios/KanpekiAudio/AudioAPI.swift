import Foundation

struct AudioRecordingIdentity: Equatable {
    static func canStart(presentationID: UUID, currentID: UUID?, active: Bool,
                         receivedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard presentationID == currentID, active, let receivedAt,
              receivedAt.isFinite, now.isFinite else { return false }
        return (0..<3).contains(now - receivedAt)
    }
    private(set) var recordingID: UUID?
    private(set) var presentationID: UUID?
    mutating func begin(presentationID: UUID?) {
        recordingID = UUID()
        self.presentationID = presentationID
    }
    func belongs(to presentationID: UUID?) -> Bool {
        presentationID != nil && self.presentationID == presentationID && recordingID != nil
    }
    static func isCurrentRecorder(_ callback: AnyObject, current: AnyObject?) -> Bool {
        current === callback
    }
}

struct AudioReport: Decodable {
    let duration: Double
    let transcriptionStatus: String
    let averageCharactersPerMinute: Double?
    let quietSeconds: Double
    let quietIntervals: [QuietInterval]
    let fillerCandidates: [FillerCandidate]?
    let pace: [PaceWindow]?
    let transcript: [TranscriptSegment]?
    let slides: [SlideInterval]
    let warnings: [String]

    func validate() throws {
        // Backend accepts 0.1...900 seconds and rounds duration fields to milliseconds.
        let tolerance = 0.001001
        func require(_ condition: Bool) throws {
            if !condition { throw AudioAPIError.message("音声結果の数値・時間範囲が不正です。結果は表示せず、同じ録音で再取得してください。") }
        }
        try require(duration.isFinite && (0.1...900).contains(duration))
        try require(["not_configured", "complete", "failed", "no_speech_recognized"].contains(transcriptionStatus))
        func metric(_ value: Double) throws { try require(value.isFinite && value >= 0) }
        func intervals(_ values: [(Double, Double)], allowOverlap: Bool = false, allowEmpty: Bool = false) throws {
            var previous = -Double.infinity
            for (start, end) in values {
                try require(start.isFinite && end.isFinite && start >= 0 && end <= duration + tolerance &&
                            (allowEmpty ? end >= start : end > start) && start >= previous - tolerance)
                previous = allowOverlap ? start : end
            }
        }
        if let averageCharactersPerMinute { try metric(averageCharactersPerMinute) }
        try metric(quietSeconds)
        try require(quietSeconds <= duration + tolerance)
        try intervals(quietIntervals.map { ($0.start, $0.end) })
        for interval in quietIntervals {
            try metric(interval.duration)
            try require(abs(interval.duration - (interval.end - interval.start)) <= tolerance)
        }
        try require(abs(quietSeconds - quietIntervals.reduce(0) { $0 + $1.duration }) <= tolerance)
        if let pace {
            try intervals(pace.map { ($0.start, $0.end) })
            for window in pace { try metric(window.charactersPerMinute) }
        }
        if let transcript { try intervals(transcript.map { ($0.start, $0.end) }, allowOverlap: true) }
        if let fillerCandidates {
            try intervals(fillerCandidates.map { ($0.start, $0.end) }, allowOverlap: true)
            for candidate in fillerCandidates {
                if let slide = candidate.slide { try require((1...10000).contains(slide)) }
            }
        }
        try intervals(slides.map { ($0.start, $0.end) }, allowEmpty: true)
        for slide in slides {
            try require((1...10000).contains(slide.slide))
            try metric(slide.duration)
            try require(abs(slide.duration - (slide.end - slide.start)) <= tolerance)
        }
    }
}

enum AudioTimeText {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, (0...900.001001).contains(seconds) else { return "未計測" }
        let whole = Int(seconds)
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}
struct QuietInterval: Decodable { let start, end, duration: Double }
struct FillerCandidate: Decodable { let text, context: String; let start, end: Double; let slide: Int? }
struct PaceWindow: Decodable { let start, end, charactersPerMinute: Double }
struct TranscriptSegment: Decodable { let start, end: Double; let text: String }
struct SlideInterval: Decodable { let slide: Int; let start, end, duration: Double }
struct SlideEvent: Codable { let at: Double; let slide: Int }
struct AnalysisJob: Decodable { let id, status: String; let report: AudioReport?; let error: String? }
struct Health: Decodable { let status: String; let transcriptionReady: Bool }
private struct ServerError: Decodable { let error: String }

enum AudioAPIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// Do not follow a redirect carrying a recording or pairing token to another host.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct AudioAPI {
    let baseURL: URL
    let token: String
    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    init(address: String, token: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw AudioAPIError.message("MacのURLを http://Mac名.local:8765 の形式で入力してください。")
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioAPIError.message("Macに表示された接続コードを入力してください。")
        }
        self.baseURL = url
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AudioAPIError.message("Macから応答がありません。") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(response.statusCode) else {
            throw AudioAPIError.message((try? decoder.decode(ServerError.self, from: data).error) ?? "Macへの接続に失敗しました（\(response.statusCode)）。")
        }
        return try decoder.decode(T.self, from: data)
    }

    func health() async throws -> Health { try await send("health") }

    func submit(id: UUID, audio: Data, slides: [SlideEvent]) async throws {
        struct Submission: Encodable { let id, audio_base64: String; let slide_events: [SlideEvent] }
        struct Accepted: Decodable { let id: String }
        let body = try JSONEncoder().encode(Submission(id: id.uuidString.lowercased(), audio_base64: audio.base64EncodedString(), slide_events: slides))
        let accepted: Accepted = try await send("v1/sessions", method: "POST", body: body)
        try Self.validateSessionID(accepted.id, expected: id)
    }

    func result(id: UUID) async throws -> AnalysisJob {
        let job: AnalysisJob = try await send("v1/sessions/\(id.uuidString.lowercased())")
        try Self.validateSessionID(job.id, expected: id)
        try job.report?.validate()
        return job
    }

    static func validateSessionID(_ returned: String, expected: UUID) throws {
        guard UUID(uuidString: returned) == expected else {
            throw AudioAPIError.message("別の録音の応答を受信しました。結果は表示せず、同じ録音で再取得してください。")
        }
    }
}

/// A bounded replay excerpt around a detected candidate; timestamps are recording-relative.
struct AudioReviewRange {
    let start: Double
    let end: Double

    init?(candidateStart: Double, candidateEnd: Double, duration: Double) {
        guard candidateStart.isFinite, candidateEnd.isFinite, duration.isFinite,
              duration > 0, candidateStart >= 0, candidateEnd >= candidateStart,
              candidateStart < duration else { return nil }
        start = max(0, candidateStart - 2)
        end = min(duration, candidateEnd + 2)
    }
}

/// UI-only chapters: no new detection, score or cross-device clock conversion.
struct AudioReviewChapter: Identifiable, Equatable {
    enum Kind: Int { case filler, quiet }
    let kind: Kind
    let sourceIndex: Int
    let start: Double
    let end: Double
    let text: String
    let context: String
    let slide: Int?
    var id: String { "\(kind.rawValue):\(sourceIndex)" }
    var label: String { kind == .filler ? "フィラー候補" : "低音量区間" }

    static func make(from report: AudioReport) -> [Self] {
        // The API validates reports. Keep this pure UI boundary safe for local callers too.
        guard report.duration.isFinite, (0.1...900).contains(report.duration) else { return [] }
        func valid(_ start: Double, _ end: Double) -> Bool {
            start.isFinite && end.isFinite && start >= 0 && end > start &&
                start < report.duration && end <= report.duration + 0.001001
        }
        var chapters = (report.fillerCandidates ?? []).enumerated().compactMap { index, item -> Self? in
            guard valid(item.start, item.end) else { return nil }
            return Self(kind: .filler, sourceIndex: index, start: item.start, end: item.end,
                        text: item.text, context: item.context, slide: item.slide)
        }
        chapters += report.quietIntervals.enumerated().compactMap { index, item -> Self? in
            guard valid(item.start, item.end) else { return nil }
            return Self(kind: .quiet, sourceIndex: index, start: item.start, end: item.end,
                        text: "低音量が続いた区間", context: "小さい声や意図的な間も含みます。失敗の判定ではありません。",
                        slide: nil)
        }
        // Keep distinct detections, including identical timestamps, in deterministic order.
        return chapters.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.sourceIndex < $1.sourceIndex
        }
    }
}

/// A timer/notification queued by an old player cannot control the next player.
struct AudioReviewPlaybackGate {
    private(set) var playbackID: UUID?
    private(set) var recordingID: UUID?
    private(set) var contextID: UUID?

    mutating func begin(recordingID: UUID, contextID: UUID) -> UUID {
        let id = UUID()
        self.playbackID = id
        self.recordingID = recordingID
        self.contextID = contextID
        return id
    }
    func accepts(_ playbackID: UUID, recordingID: UUID?, contextID: UUID) -> Bool {
        self.playbackID == playbackID && self.recordingID == recordingID && self.contextID == contextID
    }
    mutating func invalidate() { playbackID = nil; recordingID = nil; contextID = nil }
}
