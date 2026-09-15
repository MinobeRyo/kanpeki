import SwiftUI

struct MacPreparationDraft: Identifiable {
    let id = UUID()
    let timer: PresentationTimerSnapshot
    let connectionID: UUID
}

struct MacWindowSelectionFlow: View {
    let windows: [CaptureWindow]
    let currentID: UInt32?
    let canApply: () -> Bool
    let apply: (UInt32) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UInt32?
    @State private var showAllWindows = false
    @State private var reviewing = false
    @State private var rejected = false

    private var selected: CaptureWindow? { windows.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(reviewing ? "この画面を共有しますか？" : "どの画面を共有しますか？").font(.title2.bold())
            if reviewing {
                Text(selected?.label ?? "選択した画面が見つかりません")
                Text("観客に見せるスライド画面か確認してください。発表者ビューの原稿も共有するとiPhoneへ送られます。")
                if selected?.isPowerPoint == false { Text("PowerPoint以外は表示のみです。") }
            } else {
                Picker("共有画面", selection: $selection) {
                    Text("選択してください").tag(nil as UInt32?)
                    ForEach(windows.filter { showAllWindows || $0.isPowerPoint }) { window in
                        Text(window.label).tag(Optional(window.id))
                    }
                }.labelsHidden()
                Toggle("PowerPoint以外も表示", isOn: $showAllWindows)
                if windows.isEmpty { Text("画面がありません。閉じて一覧を更新してください。") }
            }
            if rejected || !canApply() { Text("準備状態が変わりました。閉じて選び直してください。").foregroundStyle(BrandColor.warning) }
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if reviewing {
                    Button("戻る") { reviewing = false; rejected = false }
                    Button("この画面を使う") {
                        guard let selection, canApply(), apply(selection) else { rejected = true; return }
                        dismiss()
                    }.buttonStyle(.borderedProminent).disabled(selected == nil || !canApply())
                } else {
                    Button("確認へ") { reviewing = true }.buttonStyle(.borderedProminent)
                        .disabled(selected == nil || !canApply())
                }
            }
        }.padding(24).frame(width: 520).background(BrandColor.paper).foregroundStyle(BrandColor.ink)
            .tint(BrandColor.ink).preferredColorScheme(.light)
            .onAppear { selection = currentID; showAllWindows = windows.first { $0.id == currentID }?.isPowerPoint == false }
    }
}

struct MacConnectionSetupFlow: View {
    let initialMacOnly: Bool
    let canApply: () -> Bool
    let apply: (Bool) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var macOnly = false
    @State private var reviewing = false
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(reviewing ? "この接続方法で準備しますか？" : "iPhoneを使いますか？").font(.title2.bold())
            if reviewing {
                Text(macOnly ? "Macだけで始める" : "iPhoneを接続して始める")
                Text(macOnly ? "iPhoneの接続を待たずに、Macの画面で発表できます。" : "適用後に接続待機を始めます。近くのiPhoneでこのMacを選び、Mac側で接続を許可してください。")
            } else {
                Picker("接続方法", selection: $macOnly) {
                    Text("iPhoneを接続して始める").tag(false)
                    Text("Macだけで始める").tag(true)
                }.pickerStyle(.radioGroup)
            }
            if rejected || !canApply() { Text("接続または準備状態が変わりました。閉じて選び直してください。").foregroundStyle(BrandColor.warning) }
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if reviewing {
                    Button("戻る") { reviewing = false; rejected = false }
                    Button("適用") {
                        guard canApply(), apply(macOnly) else { rejected = true; return }
                        dismiss()
                    }.buttonStyle(.borderedProminent).disabled(!canApply())
                } else {
                    Button("確認へ") { reviewing = true }.buttonStyle(.borderedProminent).disabled(!canApply())
                }
            }
        }.padding(24).frame(width: 520).background(BrandColor.paper).foregroundStyle(BrandColor.ink)
            .tint(BrandColor.ink).preferredColorScheme(.light).onAppear { macOnly = initialMacOnly }
    }
}
