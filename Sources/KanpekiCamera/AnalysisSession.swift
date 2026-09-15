import Foundation
import JavaScriptCore

public enum CameraSubject: String, CaseIterable, Identifiable {
    case audience, presenter
    public var id: String { rawValue }
    public var title: String { self == .audience ? "観客" : "発表者" }
}

public enum CameraPhase: Equatable {
    case stopped, preparing, running, interrupted, failed(String)
}

public struct CameraSummary: Equatable {
    public var sampledSeconds = 0
    public var observableSeconds = 0
    public var missingSeconds = 0
    // Seconds containing at least one candidate, not a count of people or gestures.
    public var nodCandidateSeconds = 0
    public var faceCount: Int?
    public var gazeTarget: String?
    public var calibrated: [String] = []
    public var calibrating: String?
    public var calibrationRemaining = 0.0
    public var warning = ""
    public var currentQuality = "準備中"
    public init() {}
}

enum CameraError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Used only on the capture queue. Raw frames, face geometry and JS objects stay there.
final class AnalysisSession {
    private let context: JSContext
    private let engine: JSValue
    private(set) var summary = CameraSummary()
    private var lastTime = -1.0
    private var lastCountedSecond = 0

    init(subject: CameraSubject) throws {
        guard let context = JSContext(),
              let url = Bundle.module.url(forResource: "analysis", withExtension: "js") else {
            throw CameraError.message("解析エンジンを読み込めません")
        }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        let options: [String: Any] = ["sessionId": UUID().uuidString, "mode": subject.rawValue,
                                      "device": "Apple", "testBuild": false]
        context.setObject(options, forKeyedSubscript: "options" as NSString)
        guard let engine = context.evaluateScript("new AnalysisKit.Engine(options)"),
              context.exception == nil, !engine.isUndefined else {
            throw CameraError.message("解析エンジンを開始できません")
        }
        self.context = context
        self.engine = engine
        engine.invokeMethod("setRole", withArguments: [subject == .audience ? "speakerSide" : "audienceSide", 0])
    }

    func calibrate(_ target: String, at time: Double) throws {
        guard ["audience", "notes", "screen"].contains(target) else { return }
        context.exception = nil
        engine.invokeMethod("beginCalibration", withArguments: [target, time])
        try checkException()
    }

    @discardableResult
    func process(faces: [[String: Any]], at time: Double, missing: Bool = false,
                 moving: Bool = false) throws -> CameraSummary {
        guard time.isFinite, time > lastTime else { return summary }
        lastTime = time
        context.exception = nil
        guard let result = engine.invokeMethod("process", withArguments: [[
            "t": time, "faces": faces, "missing": missing, "cameraMoving": moving
        ]])?.toDictionary() else { throw CameraError.message("解析結果を取得できません") }
        try checkException()
        summary.faceCount = missing ? nil : faces.count
        summary.gazeTarget = missing ? nil : result["gaze"] as? String
        summary.calibrated = result["calibrated"] as? [String] ?? []
        summary.calibrating = result["calibrating"] as? String
        let began = engine.forProperty("calibration")?.forProperty("started")?.toDouble() ?? time
        summary.calibrationRemaining = summary.calibrating == nil ? 0 : max(0, 3 - (time - began) / 1000)
        summary.warning = result["warning"] as? String ?? ""
        let observable = !missing && !moving && faces.contains {
            ($0["yaw"] as? Double)?.isFinite == true && ($0["pitch"] as? Double)?.isFinite == true
        }
        summary.currentQuality = missing ? "入力が途切れています" : moving ? "端末の動きを検出" : observable ? "解析中" : "顔を確認できません"
        let second = Int(time / 1000)
        if second > lastCountedSecond {
            // Gaps are unobserved, never fabricated as successful samples.
            let gap = second - lastCountedSecond
            summary.sampledSeconds += gap
            summary.missingSeconds += gap - (observable ? 1 : 0)
            summary.observableSeconds += observable ? 1 : 0
            lastCountedSecond = second
        }
        if observable, let rows = result["rows"] as? [[String: Any]] {
            for row in rows where row["type"] as? String == "sample" {
                if (row["nod"] as? Int ?? 0) > 0 { summary.nodCandidateSeconds += 1 }
            }
        }
        return summary
    }

    private func checkException() throws {
        if let exception = context.exception {
            throw CameraError.message(exception.toString() ?? "解析エラー")
        }
    }
}
