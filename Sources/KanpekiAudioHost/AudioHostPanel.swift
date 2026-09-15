import SwiftUI
import AppKit
import Charts

public struct AudioHostPanel: View {
    @ObservedObject var model: AudioHostModel
    @State private var confirmStop = false
    @State private var showNotices = false
    private let ink = Color(red:92/255,green:102/255,blue:115/255)
    private let mint = Color(red:217/255,green:235/255,blue:213/255)
    private let paper = Color(red:249/255,green:255/255,blue:230/255)
    public init(model: AudioHostModel) { self.model = model }
    public var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Label("音声分析",systemImage:"waveform").font(.title.bold())
                Text("iPhoneで録音した声を、このMacで振り返ります。")
                if model.preparing {
                    ProgressView().frame(maxWidth:.infinity)
                    Text(model.status)
                    Button("取得を中止") { model.cancelPreparation() }
                } else if !model.modelReady {
                    VStack(alignment:.leading,spacing:16) {
                        Text("分析モデルを準備しますか？").font(.title2.bold())
                        Text("初回約142MB。音声はMac内で分析します。")
                        Button("モデルを取得") { model.downloadModel() }.buttonStyle(.borderedProminent)
                        Button("取得済みのモデルを選ぶ") { model.chooseModel() }
                    }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(paper,in:RoundedRectangle(cornerRadius:20))
                } else if !model.receiving {
                    VStack(alignment:.leading,spacing:16) {
                        Label("分析モデルの準備ができました",systemImage:"checkmark.circle.fill")
                        Text("iPhoneからの受信を開始しますか？").font(.title2.bold())
                        Text("同じWi-FiのiPhoneに入力するURLとコードを表示します。")
                        Button(model.starting ? "開始しています…" : "受信を開始") { model.start() }
                            .buttonStyle(.borderedProminent).disabled(model.starting)
                    }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(paper,in:RoundedRectangle(cornerRadius:20))
                } else {
                    VStack(alignment:.leading,spacing:16) {
                        Text("iPhoneの「Macとつなぐ」に入力").font(.title2.bold())
                        ForEach(model.addresses,id:\.self) { address in
                            HStack {
                                VStack(alignment:.leading) { Text("MacのURL").font(.caption); Text(address).font(.title3.monospaced()).textSelection(.enabled) }
                            }
                        }
                        HStack {
                            VStack(alignment:.leading) { Text("接続コード").font(.caption); Text(model.code).font(.title3.monospaced()).textSelection(.enabled) }
                        }
                        Text("iPhoneで接続・録音後、「Macで分析する」。")
                        Text("信頼できる同じWi-Fi内でHTTP接続します。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(paper,in:RoundedRectangle(cornerRadius:20))
                    Label(model.status,systemImage:"waveform")
                    Menu("接続の操作") {
                        Button("URLをコピー") { copy(model.addresses.first ?? "") }
                        Button("コードをコピー") { copy(model.code) }
                        Menu("その他") {
                            Button("使用ライブラリ") { showNotices = true }
                            Button("受信を停止して結果を削除") { confirmStop = true }
                        }
                    }

                }
                if let error = model.error { Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.red) }
                if let report = model.report { result(report) }
                if !model.receiving {
                    Button("使用ライブラリ") { showNotices = true }
                }
            }.padding(28).frame(maxWidth:.infinity,alignment:.leading)
        }.background(mint).foregroundStyle(ink).tint(ink)
            .sheet(isPresented: $showNotices) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("使用ライブラリ").font(.title2.bold())
                    ScrollView { Text(notices).font(.caption).textSelection(.enabled) }
                    Button("閉じる") { showNotices = false }
                }.padding(24).frame(width: 560, height: 500)
            }
            .alert("受信を停止しますか？",isPresented:$confirmStop) {
                Button("停止して削除",role:.destructive) { model.stop() }
                Button("戻る",role:.cancel) {}
            } message: { Text("分析中の処理を中止し、Macの結果を削除します。再開すると接続コードが変わります。iPhoneの録音は残ります。") }
    }
    private var notices: String {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let text = try? String(contentsOf: url) else { return "whisper.cpp / ggml — MIT License" }
        return text
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string) }
    private func clock(_ seconds: Double) -> String { String(format:"%02d:%02d",Int(seconds)/60,Int(seconds)%60) }
    private func result(_ report: HostAudioReport) -> some View {
        VStack(alignment:.leading,spacing:18) {
            Text("話し方の振り返り").font(.title2.bold())
            Text("録音 \(clock(report.duration))").font(.headline)
            HStack(spacing:32) {
                VStack(alignment:.leading) { Text("話速の目安"); Text(report.averageCharactersPerMinute.map { String(format:"%.0f 文字/分",$0) } ?? "未計測").font(.title2.bold()) }
                VStack(alignment:.leading) { Text("フィラー候補"); Text(report.fillerCandidates.map { "\($0.count) 回" } ?? "未計測").font(.title2.bold()) }
            }
            if let pace = report.pace {
                Chart(Array(pace.enumerated()),id:\.offset) { _,item in
                    BarMark(xStart:.value("開始",item.start),xEnd:.value("終了",item.end),y:.value("文字/分",item.charactersPerMinute))
                }.frame(height:150).chartXScale(domain:0...report.duration).chartXAxisLabel("開始からの秒数")
            }
            Text("低音量が続いた時間：\(report.quietSeconds,specifier:"%.1f")秒")
            ForEach(Array(report.quietIntervals.enumerated()),id:\.offset) { _,item in Text("\(clock(item.start))〜\(clock(item.end))") }
            if let fillers = report.fillerCandidates, !fillers.isEmpty {
                Text("フィラー候補の場所").font(.headline)
                ForEach(Array(fillers.enumerated()),id:\.offset) { _,item in Text("\(clock(item.start))〜\(clock(item.end)) 「\(item.text)」\n\(item.context)") }
            }
            if let transcript = report.transcript {
                DisclosureGroup("文字起こし") {
                    ForEach(Array(transcript.enumerated()),id:\.offset) { _,item in
                        Text("\(clock(item.start))  \(item.text)").frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).padding(.vertical,4)
                    }
                }
            }
            DisclosureGroup("結果の読み方") { ForEach(report.warnings,id:\.self) { Text($0).font(.caption).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,4) } }
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(paper,in:RoundedRectangle(cornerRadius:20))
    }
}
