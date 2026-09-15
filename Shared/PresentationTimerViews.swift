import SwiftUI

struct PresentationTimerStatus: View {
    let snapshot: PresentationTimerSnapshot?
    let receivedAt: TimeInterval?
    let connected: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            if let snapshot, let receivedAt {
                let fresh = connected && TimerClock.now - receivedAt < 3
                let elapsed = snapshot.elapsed(at: TimerClock.now, receivedAt: receivedAt)
                let remaining = snapshot.durationSeconds.map { max(0, $0 - elapsed) }
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    if snapshot.phase == .ended {
                        Text("終了 · \(PresentationTimerText.time(snapshot.elapsedSeconds))")
                    } else if let remaining {
                        Text(PresentationTimerText.time(remaining)).monospacedDigit()
                        if remaining == 0 { Text("時間です") }
                        else if snapshot.phase == .paused { Text("一時停止") }
                    } else { Text("時間未設定") }
                    if !fresh { Text("再同期待ち") }
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }
    }
}

/// Embedded in the existing auxiliary menu; does not add controls below the slide.
struct PresentationTimerPanel: View {
    let snapshot: PresentationTimerSnapshot?
    let receivedAt: TimeInterval?
    let connected: Bool
    let canStart: Bool
    let send: (PresentationTimerAction, Double?) -> Void
    @State private var minutes = ""
    @State private var endingSession: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let fresh = connected && receivedAt.map { TimerClock.now - $0 < 3 } == true && snapshot?.isFinishing != true
            VStack(alignment: .leading, spacing: 12) {
                PresentationTimerStatus(snapshot: snapshot, receivedAt: receivedAt, connected: connected)
                if let snapshot {
                    switch snapshot.phase {
                    case .ready:
                        HStack {
                            TextField("発表時間（分）", text: $minutes).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("発表時間、分単位")
                            Button("設定") { if let value = validMinutes { send(.configure, value * 60) } }
                                .disabled(!fresh || validMinutes == nil)
                        }
                        Button("発表開始") { send(.start, nil) }
                            .disabled(!fresh || !canStart || snapshot.durationSeconds == nil)
                        if !canStart { Text("Macでスライド共有を開始してください。").font(.caption) }
                        if snapshot.durationSeconds == nil { Text("時間を設定すると開始できます（1〜1440分）。").font(.caption) }
                    case .running, .paused:
                        Button(snapshot.phase == .running ? "一時停止" : "再開") {
                            send(snapshot.phase == .running ? .pause : .resume, nil)
                        }.disabled(!fresh)
                        Divider()
                        Button("発表を終了", role: .destructive) { endingSession = snapshot.sessionID }.disabled(!fresh)
                        Text("時間が過ぎてもスライド操作は続けられます。").font(.caption)
                    case .ended:
                        Text("おつかれさまでした。経過時間 \(PresentationTimerText.time(snapshot.elapsedSeconds))")
                        Button("準備に戻る") { send(.reset, nil) }.disabled(!fresh)
                    }
                } else {
                    Text(connected ? "Macのタイマー情報を待っています。" : "Macに接続すると時間を設定できます。").font(.caption)
                }
                if snapshot?.isFinishing == true { Text("発表を終了しています…").font(.caption) }
                else if !fresh && snapshot != nil { Text("Macの最新状態を確認するまで時間操作はできません。").font(.caption) }
            }
        }
        .confirmationDialog("発表を終了しますか？", isPresented: Binding(get: { endingSession != nil }, set: { if !$0 { endingSession = nil } }), titleVisibility: .visible) {
            Button("終了", role: .destructive) {
                if snapshot?.sessionID == endingSession { send(.end, nil) }
                endingSession = nil
            }
            Button("続ける", role: .cancel) { endingSession = nil }
        } message: { Text("確認画面を開いている間も時間は進みます。") }
    }

    private var validMinutes: Double? {
        guard let value = Double(minutes), value.isFinite, (1...1440).contains(value) else { return nil }
        return value
    }
}
