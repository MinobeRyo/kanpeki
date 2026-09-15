import SwiftUI
import KanpekiCamera

/// Observe even while the optional results sheet/menu is closed.
struct PresentationResultsObserver: ViewModifier {
    let snapshot: PresentationTimerSnapshot?
    let connected: Bool
    @ObservedObject var camera: CameraController
    @Binding var association: PresentationResultAssociation

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, _ in observe() }
            .onChange(of: connected) { _, _ in observe() }
            .onChange(of: camera.result) { _, _ in observe() }
    }

    private func observe() {
        let value = connected ? snapshot : nil
        association.observe(sessionID: value?.sessionID,
            phase: value.flatMap { PresentationResultAssociation.Phase(rawValue: $0.phase.rawValue) },
            elapsedSeconds: value?.elapsedSeconds ?? 0, camera: camera.result, liveSummary: camera.summary)
    }
}

struct PresentationResultsButton: View {
    let association: PresentationResultAssociation
    @ObservedObject var camera: CameraController
    @State private var presented = false
    @State private var confirmDelete = false
    @State private var deletingID: UUID?

    var body: some View {
        if association.elapsedSeconds != nil {
            Button { presented = true } label: { Label("発表の結果", systemImage: "checkmark.circle") }
                .sheet(isPresented: $presented) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Image("BrandMascot").resizable().scaledToFit().frame(width: 60, height: 60)
                                Text("おつかれさまでした").font(.title2.bold())
                            }
                            if let elapsed = association.elapsedSeconds {
                                Text("実測時間 \(PresentationTimerText.time(elapsed))").font(.title.bold()).monospacedDigit()
                                Text("Macの発表タイマーで計測。一時停止した時間は含みません。")
                                    .font(.footnote)
                            }
                            if let result = association.cameraResult(from: camera.result) {
                                Text("この端末のカメラ · \(result.subject.title)").font(.headline)
                                Text(result.status.message)
                                if result.status == .finalizing { ProgressView("カメラ結果を確定中") }
                                if result.summary.observableSeconds > 0 {
                                    Text("判別できた時間：約\(result.summary.observableSeconds)秒")
                                    if result.subject == .audience {
                                        Text("うなずき候補のあった時間：\(result.summary.nodCandidateSeconds)秒")
                                    }
                                } else { Text("判別できた区間はありません。未計測は0点として評価しません。") }
                                if result.summary.missingSeconds > 0 {
                                    Text("未計測・判別できない時間：約\(result.summary.missingSeconds)秒")
                                }
                                Text("この発表に紐付いた最後のカメラ計測のみ。発表開始をこの端末で確認する前の集計は除外しています。候補の秒数は動作回数・人数ではありません。")
                                    .font(.footnote)
                                if let id = result.id, result.status != .finalizing,
                                   result.status != .collecting, result.status != .preparing {
                                    Button("カメラ結果を削除", role: .destructive) { deletingID = id; confirmDelete = true }
                                }
                            } else {
                                Text("この端末のカメラ").font(.headline)
                                Text("この発表に紐付く結果はありません。分析OFF・削除済み・関連付け未確認の結果は集計しません。")
                            }
                            DisclosureGroup("話し方") {
                                Text("このサマリーへの音声統合は未接続です。iPhoneの「…」→発表の音声で録音・結果を確認できます。")
                            }
                            Text("カメラ結果は他端末と同期しません。画面確認モードのサンプルとは別の実測結果です。")
                                .font(.footnote)
                            Button("閉じる") { presented = false }.buttonStyle(.borderedProminent)
                        }.padding(24).frame(maxWidth: 560, alignment: .leading)
                    }
                    .background(Color(red: 249/255, green: 1, blue: 230/255))
                    .foregroundStyle(Color(red: 92/255, green: 102/255, blue: 115/255))
                    .tint(Color(red: 92/255, green: 102/255, blue: 115/255))
                    .preferredColorScheme(.light)
                    #if os(macOS)
                    .frame(width: 520, height: 620)
                    #endif
                    .confirmationDialog("このカメラ結果を削除しますか？ 元に戻せません。", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("結果を削除", role: .destructive) { if let id = deletingID { camera.deleteResult(id: id) } }
                        Button("残す", role: .cancel) {}
                    }
                }
        }
    }
}

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
                        if !canStart { Text("Macでスライドを共有").font(.caption) }
                        if snapshot.durationSeconds == nil { Text("時間を設定してください").font(.caption) }
                    case .running, .paused:
                        Button(snapshot.phase == .running ? "一時停止" : "再開") {
                            send(snapshot.phase == .running ? .pause : .resume, nil)
                        }.disabled(!fresh)
                        Divider()
                        Button("発表を終了", role: .destructive) { endingSession = snapshot.sessionID }.disabled(!fresh)
                        Text("時間後も操作できます").font(.caption)
                    case .ended:
                        Text("おつかれさまでした。経過時間 \(PresentationTimerText.time(snapshot.elapsedSeconds))")
                        Button("準備に戻る") { send(.reset, nil) }.disabled(!fresh)
                    }
                } else {
                    Text(connected ? "Macのタイマー情報を待っています。" : "Macに接続してください").font(.caption)
                }
                if snapshot?.isFinishing == true { Text("発表を終了しています…").font(.caption) }
                else if !fresh && snapshot != nil { Text("再接続を待っています").font(.caption) }
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
    @State private var minutes = "5"
    @State private var seconds = "0"
    @State private var reviewing = false
    @State private var rejected = false

    private var validSeconds: Double? {
        guard let minuteValue = Int(minutes), let secondValue = Int(seconds),
              (0...1440).contains(minuteValue), (0...59).contains(secondValue) else { return nil }
        let total = minuteValue * 60 + secondValue
        return (60...86400).contains(total) ? Double(total) : nil
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
                        Text("時間になると通知").font(.callout)
                    } else {
                        Text("発表時間").font(.title2.bold())
                        HStack {
                            TextField("例：5", text: $minutes).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("発表時間、分単位")
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            Text("分")
                            TextField("0", text: $seconds).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("発表時間、秒")
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            Text("秒")
                        }
                        if validSeconds == nil { Text("1分〜24時間で設定").font(.caption) }
                    }
                    if isSample { Text("サンプル").font(.caption) }
                    if rejected { Text("状態が変わりました。設定し直してください。").font(.callout) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
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
                    if !canApply() { Text("接続を確認してください").font(.caption) }
                }
            }
        }
        .padding(24)
        .background(Color(red: 249/255, green: 255/255, blue: 230/255))
        .foregroundStyle(Color(red: 92/255, green: 102/255, blue: 115/255))
        .tint(Color(red: 92/255, green: 102/255, blue: 115/255))
        .preferredColorScheme(.light)
        .onAppear {
            if let initialSeconds, initialSeconds.isFinite {
                let total = Int(min(86400, max(60, initialSeconds.rounded())))
                minutes = String(total / 60); seconds = String(total % 60)
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 440, minHeight: 460, idealHeight: 500)
        #endif
    }
}
