import SwiftUI

struct PreparationNotesView: View {
    @ObservedObject var model: MacModel
    @State private var showingReview = false
    var body: some View {
        Button("原稿案を確認") { model.reviewPreparationNotes(); showingReview = true }
            .disabled(!model.notesReady)
            .sheet(isPresented: $showingReview, onDismiss: model.cancelPreparationNotes) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("本番で読む原稿を準備").font(.title2)
                    Text(model.preparationNotesStatus).font(.callout)
                    ScrollView {
                        if let pending = model.preparationNotes.pending {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(pending.pages, id: \.slideID) { page in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("ページ \(page.slideIndex)").font(.headline)
                                        Text("元の原稿").font(.caption.bold())
                                        Text(model.deck?.slides.first { $0.id == page.slideID }?.notes ?? "").textSelection(.enabled)
                                        Text("要点案（完成原稿・翻訳ではありません）").font(.caption.bold())
                                        Text(page.text).textSelection(.enabled)
                                    }
                                    Divider()
                                }
                            }
                        } else {
                            Text("Mac本体でPPTXと共有フォルダーを選ぶ → 準備アプリで「Mac本体の資料を読み込む」 → 目的・聴衆・時間を設定して分析 → この画面で原文と案を確認。採用後はiPhoneを接続し、同じページの原稿を確認してください。分析なしでも発表できます。")
                        }
                    }
                    HStack {
                        Button("閉じる") { showingReview = false }
                        Spacer()
                        Button("元の原稿に戻す") { model.restorePreparationNotes() }
                            .disabled(!model.notesReady || model.preparationNotes.accepted == nil)
                        Button("要点案を採用") { model.applyPreparationNotes() }
                            .disabled(!model.notesReady || model.preparationNotes.pending == nil)
                    }
                }.padding(24).frame(minWidth: 480, idealWidth: 580, minHeight: 420, idealHeight: 620)
            }
    }
}
