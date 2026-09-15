import Foundation

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
        let _: Accepted = try await send("v1/sessions", method: "POST", body: body)
    }

    func result(id: UUID) async throws -> AnalysisJob {
        try await send("v1/sessions/\(id.uuidString.lowercased())")
    }
}
