import Foundation

public struct AudioSegment: Codable, Equatable { public let start, end: Double; public let text: String }
public struct AudioSlideEvent: Codable, Equatable { public let at: Double; public let slide: Int }
public struct AudioInterval: Codable { public let start, end, duration: Double }
public struct AudioPace: Codable { public let start, end, charactersPerMinute: Double }
public struct AudioFiller: Codable { public let text, context: String; public let start, end: Double; public let slide: Int? }
public struct AudioSlideInterval: Codable { public let slide: Int; public let start, end, duration: Double }
public struct HostAudioReport: Codable {
    public let schemaVersion: Int
    public let duration: Double
    public let transcriptionStatus: String
    public let transcript: [AudioSegment]?
    public let pace: [AudioPace]?
    public let averageCharactersPerMinute: Double?
    public let fillerCandidates: [AudioFiller]?
    public let quietIntervals: [AudioInterval]
    public let quietSeconds: Double
    public let slides: [AudioSlideInterval]
    public let warnings: [String]
}

enum AudioHostError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

struct PCMRecording {
    let samples: [Float]
    var duration: Double { Double(samples.count) / 16000 }
    init(wav: Data) throws {
        func invalid() -> AudioHostError { .invalid("16kHz・モノラル・16bit PCMのWAV（0.1秒〜15分）を送信してください。") }
        guard wav.count >= 44, wav.count <= 30 * 1024 * 1024,
              wav.prefix(4) == Data("RIFF".utf8), wav[8..<12] == Data("WAVE".utf8) else { throw invalid() }
        func u16(_ i: Int) -> Int { Int(wav[i]) | Int(wav[i+1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i+2) << 16 }
        guard u32(4) + 8 == wav.count else { throw invalid() }
        var offset = 12, formatOK = false, audio: Range<Int>?
        while offset + 8 <= wav.count {
            let length = u32(offset + 4), start = offset + 8
            guard length <= wav.count - start else { throw invalid() }
            let name = wav[offset..<offset+4]
            if name == Data("fmt ".utf8) {
                guard length >= 16, u16(start) == 1, u16(start+2) == 1, u32(start+4) == 16000,
                      u32(start+8) == 32000, u16(start+12) == 2, u16(start+14) == 16 else { throw invalid() }
                formatOK = true
            } else if name == Data("data".utf8) {
                guard audio == nil else { throw invalid() }
                audio = start..<start+length
            }
            offset = start + length + length % 2
        }
        guard formatOK, let audio, audio.count % 2 == 0, (3200...28_800_000).contains(audio.count) else { throw invalid() }
        samples = stride(from: audio.lowerBound, to: audio.upperBound, by: 2).map { Float(Int16(bitPattern: UInt16(u16($0)))) / 32768 }
    }
}

struct AudioMetrics {
    static func validate(_ events: [AudioSlideEvent], duration: Double) throws {
        guard events.count <= 500 else { throw AudioHostError.invalid("スライド履歴は500件以内です。") }
        var previous = -1.0
        for e in events {
            guard e.at.isFinite, e.at >= 0, e.at <= duration, e.at > previous, (1...10000).contains(e.slide) else {
                throw AudioHostError.invalid("スライド履歴の時刻または番号が不正です。")
            }
            previous = e.at
        }
    }
    static func report(_ recording: PCMRecording, events: [AudioSlideEvent], segments: [AudioSegment]?, failed: Bool = false) -> HostAudioReport {
        let duration = recording.duration
        var quiet: [AudioInterval] = [], beginning: Double?
        for offset in stride(from: 0, to: recording.samples.count, by: 320) {
            let frame = recording.samples[offset..<min(offset + 320, recording.samples.count)]
            let rms = sqrt(frame.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(frame.count))
            let low = 20 * log10(max(rms, 1e-12)) < -40
            if low && beginning == nil { beginning = Double(offset)/16000 }
            if !low, let start = beginning {
                let end = Double(offset)/16000
                if end-start >= 1-1e-9 { quiet.append(.init(start: start, end: end, duration: end-start)) }
                beginning = nil
            }
        }
        if let start = beginning, duration-start >= 1-1e-9 { quiet.append(.init(start: start, end: duration, duration: duration-start)) }
        let clean = segments?.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end <= duration && $0.end > $0.start && !$0.text.isEmpty }.sorted { $0.start < $1.start }
        func count(_ text: String) -> Double { Double(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count) }
        var pace: [AudioPace]?, fillers: [AudioFiller]?, average: Double?
        if let clean, !clean.isEmpty {
            average = clean.reduce(0) { $0 + count($1.text) } * 60 / duration
            pace = stride(from: 0.0, to: duration, by: 15).map { start in
                let end = min(start+15, duration)
                let characters = clean.reduce(0.0) { $0 + count($1.text) * max(0, min(end,$1.end)-max(start,$1.start)) / ($1.end-$1.start) }
                return .init(start: start, end: end, charactersPerMinute: characters*60/(end-start))
            }
            let regex = try! NSRegularExpression(pattern: "え[ーぇ]+|あの[ーう]?|えっと|ええと|その[ーう]")
            fillers = clean.flatMap { s in
                regex.matches(in: s.text, range: NSRange(s.text.startIndex..., in: s.text)).map { match in
                    AudioFiller(text: (s.text as NSString).substring(with: match.range), context: s.text, start: s.start, end: s.end,
                                slide: events.last(where: { $0.at <= s.start })?.slide)
                }
            }
        }
        let slides = events.enumerated().map { index, event in
            let end = index+1 < events.count ? events[index+1].at : duration
            return AudioSlideInterval(slide: event.slide, start: event.at, end: end, duration: end-event.at)
        }
        var warnings = ["低音量区間は−40dBFS未満が1秒以上続いた区間です。沈黙や失敗とは断定しません。",
                        "話速は認識文字数/分の推定値です。フィラーは候補で、位置は認識文の時間範囲です。"]
        if events.isEmpty { warnings.append("スライド履歴がないため、スライド別時間は未計測です。") }
        if clean?.isEmpty != false { warnings.append("文字起こしを取得できなかったため、話速とフィラーは未計測です。") }
        if !recording.samples.contains(where: { $0 != 0 }) { warnings.append("音声全体がゼロ信号です。マイクや入力経路を確認してください。") }
        return .init(schemaVersion: 1, duration: duration, transcriptionStatus: failed ? "failed" : (clean?.isEmpty == false ? "complete" : "no_speech_recognized"), transcript: clean, pace: pace,
                     averageCharactersPerMinute: average, fillerCandidates: fillers, quietIntervals: quiet,
                     quietSeconds: quiet.reduce(0) { $0 + $1.duration }, slides: slides, warnings: warnings)
    }
}
