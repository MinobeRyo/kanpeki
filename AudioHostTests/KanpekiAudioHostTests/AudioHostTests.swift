import XCTest
import SwiftUI
@testable import KanpekiAudioHost

final class AudioHostTests: XCTestCase {
    func wav(seconds: Double = 2, value: Int16 = 0) -> Data {
        let samples = Int(seconds*16000), bytes = samples*2
        func le(_ n: Int,_ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded:n >> ($0*8)) } }
        var data = Data("RIFF".utf8); data.append(contentsOf:le(36+bytes,4)); data.append(Data("WAVEfmt ".utf8))
        for (n,c) in [(16,4),(1,2),(1,2),(16000,4),(32000,4),(2,2),(16,2)] { data.append(contentsOf:le(n,c)) }
        data.append(Data("data".utf8)); data.append(contentsOf:le(bytes,4))
        for _ in 0..<samples { data.append(contentsOf:le(Int(value),2)) }
        return data
    }
    func testPCMValidationAndQuietIntervals() throws {
        let input = try PCMRecording(wav:wav())
        XCTAssertEqual(input.duration,2)
        let report = AudioMetrics.report(input,events:[],segments:[])
        XCTAssertEqual(report.quietSeconds,2,accuracy:0.001)
        XCTAssertNil(report.averageCharactersPerMinute)
        XCTAssertNil(report.fillerCandidates)
        XCTAssertEqual(report.transcriptionStatus,"no_speech_recognized")
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("ゼロ信号") }))
        var corrupt = wav(); corrupt[22] = 2
        XCTAssertThrowsError(try PCMRecording(wav:corrupt))
        XCTAssertThrowsError(try PCMRecording(wav:Data(wav().dropLast())))
        XCTAssertThrowsError(try PCMRecording(wav:wav(seconds:0.05)))
        var huge = wav(); huge.replaceSubrange(40..<44,with:[255,255,255,255])
        XCTAssertThrowsError(try PCMRecording(wav:huge))
    }
    func testPaceFillersAndRepeatedSlides() throws {
        let input = try PCMRecording(wav:wav(seconds:30,value:5000))
        let events = [AudioSlideEvent(at:0,slide:1),.init(at:10,slide:2),.init(at:20,slide:1)]
        try AudioMetrics.validate(events,duration:30)
        let segments = [AudioSegment(start:0,end:10,text:"あの資料です"),.init(start:20,end:25,text:"えっと次です")]
        let report = AudioMetrics.report(input,events:events,segments:segments)
        XCTAssertEqual(report.fillerCandidates?.count,2)
        XCTAssertEqual(report.fillerCandidates?.last?.slide,1)
        XCTAssertEqual(report.slides.map(\.slide),[1,2,1])
        XCTAssertEqual(report.slides.map(\.duration),[10,10,10])
        XCTAssertEqual(report.pace?.count,2)
        XCTAssertEqual(report.quietSeconds,0)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(report)) as? [String:Any])
        XCTAssertNotNil(json["transcription_status"])
        XCTAssertNotNil(json["average_characters_per_minute"])
        XCTAssertThrowsError(try AudioMetrics.validate([.init(at:20,slide:1),.init(at:10,slide:2)],duration:30))
        XCTAssertThrowsError(try AudioMetrics.validate([.init(at:Double.nan,slide:1)],duration:30))
    }
    func testHTTPFragmentationAndEarlyAuthentication() throws {
        var parser = AudioHTTPParser()
        XCTAssertNil(try parser.append(Data("POST /v1/sessions HTTP/1.1\r\nAuthorization: Bear".utf8),authorize:{ $0 == "Bearer correct" }))
        XCTAssertNil(try parser.append(Data("er correct\r\nContent-Length: 2\r\n\r\n{".utf8),authorize:{ $0 == "Bearer correct" }))
        let request = try XCTUnwrap(parser.append(Data("}".utf8),authorize:{ $0 == "Bearer correct" }))
        XCTAssertEqual(request.body,Data("{}".utf8))
        XCTAssertEqual(request.path,"/v1/sessions")
        for headers in ["Content-Length: 999999999", "Content-Length: 2\r\nContent-Length: 3", "Transfer-Encoding: chunked", "Content-Length: -1"] {
            var rejected = AudioHTTPParser()
            XCTAssertThrowsError(try rejected.append(Data("POST /v1/sessions HTTP/1.1\r\n\(headers)\r\n\r\n".utf8),authorize:{ _ in true }))
        }
        var unauthenticated = AudioHTTPParser()
        XCTAssertThrowsError(try unauthenticated.append(Data("POST /v1/sessions HTTP/1.1\r\nContent-Length: 20000000\r\n\r\n".utf8),authorize:{ _ in false })) { XCTAssertEqual($0.localizedDescription,"401") }
    }
    func testHTTPJobLifecycleAndIdempotence() async throws {
        let started = expectation(description:"listener")
        var port: UInt16 = 0
        let server = AudioHTTPServer { input,events,_ in AudioMetrics.report(input,events:events,segments:[.init(start:0,end:1,text:"テストです")]) }
        server.onReady = { port = $0; started.fulfill() }; server.start(); defer { server.stop() }
        await fulfillment(of:[started],timeout:10)
        let url = URL(string:"http://127.0.0.1:\(port)")!
        func request(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil) async throws -> (Int,[String:Any]) {
            var req = URLRequest(url:url.appendingPathComponent(path)); req.httpMethod = method; req.httpBody = body
            req.setValue("Bearer " + (token ?? server.token),forHTTPHeaderField:"Authorization")
            req.setValue("application/json",forHTTPHeaderField:"Content-Type")
            let (data,response) = try await URLSession.shared.data(for:req)
            return ((response as! HTTPURLResponse).statusCode,try JSONSerialization.jsonObject(with:data) as! [String:Any])
        }
        let denied = try await request("health",token:"incorrect"); XCTAssertEqual(denied.0,401)
        let health = try await request("health"); XCTAssertEqual(health.1["transcription_ready"] as? Bool,true)
        let id = UUID().uuidString.lowercased()
        let body = try JSONSerialization.data(withJSONObject:["id":id,"audio_base64":wav().base64EncodedString(),"slide_events":[["at":0,"slide":1]]])
        let accepted = try await request("v1/sessions",method:"POST",body:body); XCTAssertEqual(accepted.0,202)
        let retry = try await request("v1/sessions",method:"POST",body:body); XCTAssertEqual(retry.0,202)
        let different = try JSONSerialization.data(withJSONObject:["id":id,"audio_base64":wav(value:100).base64EncodedString(),"slide_events":[["at":0,"slide":1]]])
        let conflict = try await request("v1/sessions",method:"POST",body:different); XCTAssertEqual(conflict.0,409)
        var result: [String:Any] = [:]
        for _ in 0..<20 {
            result = try await request("v1/sessions/"+id).1
            if result["status"] as? String == "complete" { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertEqual(result["id"] as? String,id)
        XCTAssertEqual(result["status"] as? String,"complete")
        XCTAssertNotNil((result["report"] as? [String:Any])?["transcript"])
        let removed = try await request("v1/sessions/"+id,method:"DELETE"); XCTAssertEqual(removed.0,200)
        let missing = try await request("v1/sessions/"+id); XCTAssertEqual(missing.0,404)
    }
    func testBusyResponseAndStopSuppressLateResult() async throws {
        let ready = expectation(description: "ready"), began = expectation(description: "analysis began")
        let late = expectation(description: "late result must not be published"); late.isInverted = true
        let cancelled = expectation(description: "analysis cancelled")
        var port: UInt16 = 0
        let server = AudioHTTPServer { input, events, cancellation in
            began.fulfill()
            let deadline = Date().addingTimeInterval(5)
            while !cancellation.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if cancellation.isCancelled { cancelled.fulfill() }
            return AudioMetrics.report(input, events: events, segments: [])
        }
        server.onReady = { port = $0; ready.fulfill() }
        server.onReport = { _,_ in late.fulfill() }
        server.start(); defer { server.stop() }
        await fulfillment(of: [ready], timeout: 10)
        func submit() async throws -> Int {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/sessions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer " + server.token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "audio_base64": wav().base64EncodedString(), "slide_events": []])
            return (try await URLSession.shared.data(for: request).1 as! HTTPURLResponse).statusCode
        }
        let first = try await submit(); XCTAssertEqual(first, 202)
        await fulfillment(of: [began], timeout: 5)
        let busy = try await submit(); XCTAssertEqual(busy, 429)
        server.stop()
        await fulfillment(of: [cancelled], timeout: 5)
        await fulfillment(of: [late], timeout: 0.2)
    }
    @MainActor func testWhisperOnSyntheticAudioWhenExplicitlyConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["KANPEKI_TEST_MODEL"], let wav = env["KANPEKI_TEST_WAV"] else {
            throw XCTSkip("実モデル検証は合成WAVとモデルを明示して実行する")
        }
        func snapshot(_ model: AudioHostModel, name: String) throws {
            guard let directory = env["KANPEKI_TEST_SNAPSHOTS"] else { return }
            let view = NSHostingView(rootView: AudioHostPanel(model: model))
            view.frame = NSRect(x: 0, y: 0, width: 760, height: 1000)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(name + ".png"))
        }
        let unprepared = AudioHostModel(modelURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try snapshot(unprepared, name: "prepare")
        let url = URL(fileURLWithPath:path)
        let model = AudioHostModel(modelURL: url)
        for _ in 0..<100 {
            if !model.preparing { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.modelReady)
        model.start(); defer { model.stop() }
        for _ in 0..<100 {
            if model.receiving || model.error != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.receiving, model.error ?? "listener not ready")
        try snapshot(model, name: "receiving")
        let address = try XCTUnwrap(model.addresses.first)
        let id = UUID().uuidString.lowercased()
        var request = URLRequest(url: URL(string: address + "/v1/sessions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + model.code, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try Data(contentsOf: URL(fileURLWithPath: wav))
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "audio_base64": data.base64EncodedString(), "slide_events": []])
        let accepted = try await URLSession.shared.data(for: request)
        XCTAssertEqual((accepted.1 as! HTTPURLResponse).statusCode, 202)
        for _ in 0..<1200 {
            if model.report != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.reportID, id)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(report.transcriptionStatus, "complete")
        XCTAssertFalse(try XCTUnwrap(report.transcript).isEmpty)
        try snapshot(model, name: "result")
        var resultRequest = URLRequest(url: URL(string: address + "/v1/sessions/" + id)!)
        resultRequest.setValue("Bearer " + model.code, forHTTPHeaderField: "Authorization")
        let resultData = try await URLSession.shared.data(for: resultRequest).0
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        XCTAssertEqual(result["id"] as? String, id)
        XCTAssertEqual((result["report"] as? [String: Any])?["transcription_status"] as? String, "complete")
        let cancelled = AudioCancellation(); cancelled.cancel()
        let recording = try PCMRecording(wav: data)
        XCTAssertThrowsError(try WhisperEngine().transcribe(recording.samples, model: url, cancellation: cancelled))
        model.stop()
        XCTAssertTrue(model.code.isEmpty)
        XCTAssertNil(model.report)
    }
}
