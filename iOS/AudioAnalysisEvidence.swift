import Foundation

extension AudioReport {
    func analysisFacts(recordingID: UUID) throws -> [PracticeFact] {
        try validate()
        var facts: [PracticeFact] = []
        let prefix = "audio.\(recordingID.uuidString.lowercased())"
        func add(_ id: String, _ text: String, start: Double? = nil, end: Double? = nil) {
            let range: PracticeAudioRange?
            if let start, let end, start < end {
                range = PracticeAudioRange(recordingID: recordingID, startSeconds: start, endSeconds: end)
            } else { range = nil }
            facts.append(PracticeFact(id: "\(prefix).\(id)", kind: "audio", text: text, audioRange: range))
        }
        add("status", "文字起こし状態: \(transcriptionStatus)。録音時間: \(duration)秒。以下の時刻は録音開始からの秒数です。発表タイマー・カメラ時刻との同期は未実施です。")
        add("pace", "認識文字数/録音分（音響上の話速ではない）: \(averageCharactersPerMinute.map { String($0) } ?? "未計測")")
        add("quiet", "低音量区間の合計: \(quietSeconds)秒。沈黙や失敗とは断定できません。")
        add("fillers", "フィラー候補数: \(fillerCandidates.map { String($0.count) } ?? "未計測")。確定回数ではありません。")
        if transcript == nil || transcript?.isEmpty == true { add("transcript", "文字起こし本文は未取得です。発話なしとは断定できません。") }
        for (i, s) in (transcript ?? []).enumerated() { add("transcript.\(i)", "録音 \(s.start)〜\(s.end)秒: \(s.text)", start: s.start, end: s.end) }
        for (i, s) in (pace ?? []).enumerated() { add("pace.\(i)", "録音 \(s.start)〜\(s.end)秒: 認識文字数/分の推定値 \(s.charactersPerMinute)", start: s.start, end: s.end) }
        for (i, s) in quietIntervals.enumerated() { add("quiet.\(i)", "録音 \(s.start)〜\(s.end)秒: 低音量 \(s.duration)秒", start: s.start, end: s.end) }
        for (i, s) in (fillerCandidates ?? []).enumerated() {
            add("filler.\(i)", "候補「\(s.text)」、文脈「\(s.context)」、録音 \(s.start)〜\(s.end)秒（認識文の区間）。ページ: \(s.slide.map { String($0) } ?? "不明")", start: s.start, end: s.end)
        }
        if slides.isEmpty { add("slides", "音声とスライド履歴の同期は未計測です。文字起こしからページ時刻を推定しないでください。") }
        for (i, s) in slides.enumerated() { add("slide.\(i)", "録音 \(s.start)〜\(s.end)秒: ページ\(s.slide)、\(s.duration)秒", start: s.start, end: s.end) }
        for (i, warning) in warnings.enumerated() { add("warning.\(i)", warning) }
        return facts
    }
}
