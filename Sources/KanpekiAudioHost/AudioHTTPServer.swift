import Foundation
import Network
import CryptoKit

struct AudioHTTPRequest {
    let method, path: String
    let headers: [String:String]
    let body: Data
}
struct AudioHTTPParser {
    static let bodyLimit = 40 * 1024 * 1024
    private var buffer = Data()
    private var headerEnd: Int?
    private var length = 0
    private var method = "", path = ""
    private var headers: [String:String] = [:]
    mutating func append(_ data: Data, authorize: (String?) -> Bool) throws -> AudioHTTPRequest? {
        guard buffer.count + data.count <= Self.bodyLimit + 16384 else { throw AudioHostError.invalid("413") }
        buffer.append(data)
        if headerEnd == nil {
            guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 16384 { throw AudioHostError.invalid("431") }
                return nil
            }
            guard range.upperBound <= 16384, let text = String(data: buffer[..<range.lowerBound], encoding: .utf8) else { throw AudioHostError.invalid("400") }
            let lines = text.components(separatedBy: "\r\n")
            let first = lines[0].split(separator: " ")
            guard first.count == 3, first[2] == "HTTP/1.1" || first[2] == "HTTP/1.0", first[1].hasPrefix("/") else { throw AudioHostError.invalid("400") }
            method = String(first[0]); path = String(first[1])
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { throw AudioHostError.invalid("400") }
                let key = line[..<colon].lowercased()
                guard !key.isEmpty, headers[key] == nil else { throw AudioHostError.invalid("400") }
                headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard authorize(headers["authorization"]) else { throw AudioHostError.invalid("401") }
            guard headers["transfer-encoding"] == nil else { throw AudioHostError.invalid("400") }
            if let size = headers["content-length"] {
                guard !size.isEmpty, size.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(size), value >= 0 else { throw AudioHostError.invalid("400") }
                guard value <= Self.bodyLimit else { throw AudioHostError.invalid("413") }
                length = value
            } else if method == "POST" { throw AudioHostError.invalid("411") }
            headerEnd = range.upperBound
        }
        guard let end = headerEnd, buffer.count >= end + length else { return nil }
        guard buffer.count == end + length else { throw AudioHostError.invalid("400") }
        return AudioHTTPRequest(method: method, path: path, headers: headers, body: Data(buffer[end...]))
    }
}

struct HostSubmission: Decodable {
    let id: String
    let audio_base64: String
    let slide_events: [AudioSlideEvent]
}

/// All mutable transport/job state belongs to `queue`. Analysis runs one at a time elsewhere.
final class AudioHTTPServer {
    typealias Analyze = (PCMRecording, [AudioSlideEvent], AudioCancellation) throws -> HostAudioReport
    private let queue = DispatchQueue(label: "kanpeki.audio.http")
    private let worker = DispatchQueue(label: "kanpeki.audio.analysis", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier:NWConnection] = [:]
    private var jobs: [String:Job] = [:]
    private var active: AudioCancellation?
    private var generation = UUID()
    private var expiryTimer: DispatchSourceTimer?
    private let analyze: Analyze
    let token: String
    var onReady: ((UInt16) -> Void)?
    var onStatus: ((String) -> Void)?
    var onReport: ((String,HostAudioReport) -> Void)?
    var onFailure: ((String) -> Void)?
    private struct Job {
        let fingerprint: Data
        let created: Date
        var status: String
        var report: HostAudioReport?
        var error: String?
    }
    init(analyze: @escaping Analyze) {
        self.analyze = analyze
        token = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    }
    func start() {
        queue.async {
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, self.listener === listener else { return }
                    switch state {
                    case .ready: if let port = listener?.port { self.onReady?(port.rawValue) }
                    case .failed: self.stopOnQueue(); self.onFailure?("音声の受信を開始できません。ネットワークの許可を確認してください。")
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] in self?.accept($0) }
                listener.start(queue: self.queue)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now()+30, repeating: 30)
                timer.setEventHandler { [weak self] in self?.expire() }
                timer.resume(); self.expiryTimer = timer
            } catch { self.onFailure?("音声の受信を開始できませんでした。") }
        }
    }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID(); listener?.cancel(); listener = nil
        active?.cancel(); active = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll(); jobs.removeAll()
        expiryTimer?.cancel(); expiryTimer = nil
    }
    private func expire() {
        jobs = jobs.filter { $0.value.status == "analyzing" || Date().timeIntervalSince($0.value.created) < 3600 }
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 4, listener != nil else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now()+60) { [weak self, weak connection] in
            guard let self, let connection, self.connections[ObjectIdentifier(connection)] != nil else { return }
            self.finish(connection)
        }
        read(connection, parser: AudioHTTPParser())
    }
    private func read(_ connection: NWConnection, parser: AudioHTTPParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, self.connections[ObjectIdentifier(connection)] != nil else { return }
            var parser = parser
            do {
                if let data, let request = try parser.append(data, authorize: self.authorize) {
                    let response = self.route(request)
                    self.send(connection, code: response.0, object: response.1)
                } else if complete || error != nil { self.finish(connection) }
                else { self.read(connection, parser: parser) }
            } catch {
                let code = Int(error.localizedDescription) ?? 400
                self.send(connection, code: code, object: ["error": code == 401 ? "接続コードが一致しません。Macの現在のコードを入力してください。" : "リクエストの形式またはサイズが不正です。"])
            }
        }
    }
    private func authorize(_ authorization: String?) -> Bool {
        let expected = Array(SHA256.hash(data: Data(("Bearer " + token).utf8)))
        let actual = Array(SHA256.hash(data: Data((authorization ?? "").utf8)))
        return zip(expected,actual).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private func route(_ request: AudioHTTPRequest) -> (Int,[String:Any]) {
        expire()
        if request.method == "GET", request.path == "/health" {
            return (200,["status":"ok","schema_version":1,"transcription_ready":true])
        }
        if request.method == "POST", request.path == "/v1/sessions" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else { return (415,["error":"JSONで送信してください。"]) }
            do {
                let submission = try JSONDecoder().decode(HostSubmission.self,from: request.body)
                guard let uuid = UUID(uuidString: submission.id), let wav = Data(base64Encoded: submission.audio_base64) else { throw AudioHostError.invalid("録音IDまたは音声が不正です。") }
                let id = uuid.uuidString.lowercased()
                var hasher = SHA256(); hasher.update(data: wav)
                let fingerprintEncoder = JSONEncoder(); fingerprintEncoder.outputFormatting = .sortedKeys
                hasher.update(data: try fingerprintEncoder.encode(submission.slide_events))
                let fingerprint = Data(hasher.finalize())
                if let job = jobs[id] {
                    return job.fingerprint == fingerprint ? (202,["id":id]) : (409,["error":"同じ録音IDに異なる音声が送られました。"])
                }
                guard active == nil, jobs.count < 64 else { return (429,["error":"Macで分析中です。完了後に再送してください。"] ) }
                let recording = try PCMRecording(wav: wav)
                try AudioMetrics.validate(submission.slide_events,duration: recording.duration)
                let cancellation = AudioCancellation(), generation = self.generation
                active = cancellation
                jobs[id] = Job(fingerprint: fingerprint, created: Date(), status: "analyzing")
                onStatus?("音声を受信しました。話し方を分析中です。")
                worker.async {
                    let result = Result { try self.analyze(recording,submission.slide_events,cancellation) }
                    self.queue.async {
                        guard self.generation == generation else { return }
                        self.active = nil
                        guard self.jobs[id] != nil else { return }
                        switch result {
                        case .success(let report):
                            self.jobs[id]?.status = "complete"; self.jobs[id]?.report = report
                            self.onStatus?("分析が完了しました。iPhoneでも結果を確認できます。")
                            self.onReport?(id,report)
                        case .failure:
                            self.jobs[id]?.status = "failed"; self.jobs[id]?.error = "分析を完了できませんでした。受信を停止して再度試してください。"
                            self.onStatus?("分析を完了できませんでした。")
                        }
                    }
                }
                return (202,["id":id])
            } catch { return (400,["error":(error as? AudioHostError)?.localizedDescription ?? "音声データの形式が不正です。"]) }
        }
        let parts = request.path.split(separator:"/")
        if parts.count == 3, parts[0] == "v1", parts[1] == "sessions", let uuid = UUID(uuidString:String(parts[2])) {
            let id = uuid.uuidString.lowercased()
            guard let job = jobs[id] else { return (404,["error":"結果がありません。受信を再開した場合は録音を再送してください。"] ) }
            if request.method == "GET" {
                let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
                let report: Any = job.report.flatMap { try? encoder.encode($0) }.flatMap { try? JSONSerialization.jsonObject(with:$0) } ?? NSNull()
                return (200,["id":id,"status":job.status,"report":report,"error":job.error as Any? ?? NSNull()])
            }
            if request.method == "DELETE" {
                guard job.status != "analyzing" else { return (409,["error":"分析中です。停止するにはMacで受信を停止してください。"] ) }
                jobs.removeValue(forKey:id)
                return (200,["deleted":true])
            }
        }
        return (404,["error":"この操作はありません。"])
    }
    private func send(_ connection: NWConnection, code: Int, object: [String:Any]) {
        let data = (try? JSONSerialization.data(withJSONObject:object)) ?? Data("{}".utf8)
        var response = Data("HTTP/1.1 \(code) \(code < 300 ? "OK" : "Error")\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        response.append(data)
        connection.send(content:response,completion:.contentProcessed { [weak self] _ in self?.finish(connection) })
    }
    private func finish(_ connection: NWConnection) { connections.removeValue(forKey:ObjectIdentifier(connection)); connection.cancel() }
}
