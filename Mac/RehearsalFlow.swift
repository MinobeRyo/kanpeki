import SwiftUI
import KanpekiAudioHost

struct RehearsalFlow: View {
    @ObservedObject var model: MacModel
    @ObservedObject var audio: AudioHostModel
    @ObservedObject var link: PeerLink
    var connect: () -> Void
    var feedback: () -> Void
    var audioDetails: () -> Void
    @State private var showTime = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("練習する").font(.largeTitle.bold())
            Text("準備 → iPhoneで録音 → Macで分析 → AIで振り返る").foregroundStyle(.secondary)
            Spacer()
            if model.state.timer?.phase == .ended {
                Text("録音を分析して、次の練習へ").font(.title.bold())
                Text(model.sharedAudioAvailable ? "音声の分析結果を受け取りました" : "iPhoneで「Macで分析する」を押してください")
                Text(model.practiceAnalysisStatus).font(.callout)
                Button("AIの振り返りを開く", action: feedback).buttonStyle(BrandPrimaryButtonStyle())
            } else if model.state.timer?.phase == .running || model.state.timer?.phase == .paused {
                Text("iPhoneで録音しながら話しましょう").font(.title.bold())
                Text("iPhoneの「録音を始める」を押すと、マイクの取得が始まります。")
                PresentationTimerStatus(snapshot: model.state.timer, receivedAt: model.timerReceivedAt, connected: true)
                Button("練習を終了") { model.timerAction(.end, duration: nil) }
                    .buttonStyle(BrandPrimaryButtonStyle()).disabled(model.timerFinishing)
            } else if !audio.modelReady {
                Text("はじめに、音声分析を準備").font(.title.bold())
                Text(audio.status)
                if audio.preparing { ProgressView(); Button("取得を中止") { audio.cancelPreparation() } }
                else { Button("分析モデルを取得（約142MB）") { audio.downloadModel() }.buttonStyle(BrandPrimaryButtonStyle()) }
            } else if !audio.receiving {
                Text("Macで音声を受け取る準備").font(.title.bold())
                Text(audio.status)
                Button(audio.starting ? "準備中…" : "音声の受信を開始") { audio.start() }
                    .buttonStyle(BrandPrimaryButtonStyle()).disabled(audio.starting)
            } else if link.connectedName == nil {
                Text("iPhoneをつなぎましょう").font(.title.bold())
                Text("同じWi-Fiで接続します。音声の接続コードは自動で渡します。")
                Button("接続用QRを表示", action: connect).buttonStyle(BrandPrimaryButtonStyle())
            } else {
                Text("声を出して練習しましょう").font(.title.bold())
                Text("目標時間 \(PresentationTimerText.time(model.state.timer?.durationSeconds ?? 300))")
                Text("開始後、iPhoneに録音ボタンが表示されます。資料なしでも練習できます。")
                Button("練習を開始") { model.beginPractice() }.buttonStyle(BrandPrimaryButtonStyle())
            }
            if let error = audio.error { Text(error).foregroundStyle(.red) }
            Menu("設定・その他") {
                Button("時間を調整") { showTime = true }.disabled(model.state.timer?.phase != .ready)
                Button("資料を選ぶ") { model.importDeck() }.disabled(!model.notesReady)
                Button("取得済みモデルを選ぶ") { audio.chooseModel() }.disabled(audio.receiving || audio.preparing)
                Button("音声の結果・接続設定", action: audioDetails)
                Button("ChatGPT共有を設定") { model.startMCP() }
                Button("AIの振り返り", action: feedback)
                if model.state.timer?.phase == .running || model.state.timer?.phase == .paused {
                    Button(model.state.timer?.phase == .running ? "一時停止" : "再開") {
                        model.timerAction(model.state.timer?.phase == .running ? .pause : .resume, duration: nil)
                    }
                }
                if model.state.timer?.phase == .ended {
                    Button("次の練習を準備") { model.timerAction(.reset, duration: nil) }.disabled(model.timerFinishing)
                }
            }.fixedSize()
            Spacer()
        }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColor.paper, in: RoundedRectangle(cornerRadius: 24))
            .sheet(isPresented: $showTime) {
                TimeAdjustmentFlow(initialSeconds: model.state.timer?.durationSeconds, canApply: {
                    model.state.timer?.phase == .ready && !model.timerFinishing
                }, apply: { seconds in
                    guard model.state.timer?.phase == .ready else { return false }
                    model.timerAction(.configure, duration: seconds); return true
                })
            }
    }
}
