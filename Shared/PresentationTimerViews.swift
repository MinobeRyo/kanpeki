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
    @State private var adjustment: TimerAdjustmentDraft?
    @State private var endingSession: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let fresh = connected && receivedAt.map { TimerClock.now - $0 < 3 } == true && snapshot?.isFinishing != true
            VStack(alignment: .leading, spacing: 12) {
                PresentationTimerStatus(snapshot: snapshot, receivedAt: receivedAt, connected: connected)
                if let snapshot {
                    switch snapshot.phase {
                    case .ready:
                        Button("時間を調整", systemImage: "timer") {
                            adjustment = TimerAdjustmentDraft(snapshot: snapshot)
                        }.disabled(!fresh)
                        Button("発表開始") { send(.start, nil) }
                            .disabled(!fresh || !canStart || snapshot.durationSeconds == nil)
                        if !canStart { Text("Macでスライド共有を開始してください。").font(.caption) }
                        if snapshot.durationSeconds == nil { Text("時間を調整すると開始できます。").font(.caption) }
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
        .sheet(item: $adjustment) { draft in
            TimeAdjustmentFlow(initialSeconds: draft.snapshot.durationSeconds,
                canApply: { canApply(draft) }, apply: { seconds in
                    guard canApply(draft) else { return false }
                    send(.configure, seconds)
                    return true
                })
        }
        .confirmationDialog("発表を終了しますか？", isPresented: Binding(get: { endingSession != nil }, set: { if !$0 { endingSession = nil } }), titleVisibility: .visible) {
            Button("終了", role: .destructive) {
                if snapshot?.sessionID == endingSession { send(.end, nil) }
                endingSession = nil
            }
            Button("続ける", role: .cancel) { endingSession = nil }
        } message: { Text("確認画面を開いている間も時間は進みます。") }
    }

    private func canApply(_ draft: TimerAdjustmentDraft) -> Bool {
        connected && receivedAt.map { TimerClock.now - $0 < 3 } == true &&
        snapshot?.phase == .ready && snapshot?.isFinishing != true &&
        snapshot?.sessionID == draft.snapshot.sessionID && snapshot?.revision == draft.snapshot.revision
    }
}

private struct TimerAdjustmentDraft: Identifiable {
    let id = UUID()
    let snapshot: PresentationTimerSnapshot
}

/// Local draft only: no timer command is sent until the final explicit action.
struct TimeAdjustmentFlow: View {
    let initialSeconds: Double?
    var isSample = false
    var canApply: () -> Bool = { true }
    let apply: (Double) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = ""
    @State private var reviewing = false
    @State private var rejected = false

    private var validSeconds: Double? {
        guard let value = Double(minutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, (1...1440).contains(value) else { return nil }
        return value * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("時間を調整").font(.headline)
                Spacer()
                Button("キャンセル") { dismiss() }
            }
            Text(reviewing ? "2 / 2  確認" : "1 / 2  入力").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if reviewing {
                        Text("この時間でよいですか？").font(.title2.bold())
                        if let seconds = validSeconds {
                            Text(PresentationTimerText.time(seconds)).font(.largeTitle.bold()).monospacedDigit()
                        }
                        Text("時間切れを通知します。スライドは手動で進めます。").font(.callout)
                    } else {
                        Text("発表は何分ですか？").font(.title2.bold())
                        HStack {
                            TextField("例：5", text: $minutes).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("発表時間、分単位")
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("分")
                        }
                        HStack {
                            ForEach([3, 5, 10], id: \.self) { value in
                                Button("\(value)分") { minutes = String(value) }.frame(minHeight: 44)
                            }
                        }
                        Text("1〜1440分。小数も入力できます。").font(.caption).foregroundStyle(.secondary)
                    }
                    if isSample { Text("画面確認用。実際のタイマーには反映しません。").font(.caption) }
                    if rejected { Text("設定の状態が変わりました。閉じて、もう一度調整してください。").font(.callout) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text(reviewing ? "よければ適用してね" : "まずは時間を決めよう").font(.callout)
            }
            HStack {
                if reviewing { Button("戻る") { reviewing = false; rejected = false }.frame(minHeight: 44) }
                Spacer()
                if reviewing {
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        Button(isSample ? "見本に適用" : "適用") {
                            guard let seconds = validSeconds, canApply(), apply(seconds) else {
                                rejected = true; return
                            }
                            dismiss()
                        }.buttonStyle(BrandPrimaryButtonStyle()).disabled(validSeconds == nil || !canApply())
                    }
                } else {
                    Button("次へ") { reviewing = true }.buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(validSeconds == nil)
                }
            }
            if reviewing {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    if !canApply() { Text("設定を確認できません。接続状態を確認し、閉じてやり直してください。").font(.caption) }
                }
            }
        }
        .padding(24)
        .background(Color(red: 249/255, green: 255/255, blue: 230/255))
        .foregroundStyle(Color(red: 92/255, green: 102/255, blue: 115/255))
        .tint(Color(red: 92/255, green: 102/255, blue: 115/255))
        .preferredColorScheme(.light)
        .onAppear { if let initialSeconds { minutes = String(format: "%g", initialSeconds / 60) } }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 440, minHeight: 460, idealHeight: 500)
        #endif
    }
}
