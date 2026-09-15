import Foundation
import Testing
@testable import SlidePacer

struct SlidePacerTests {
    @Test func nativeMCPRejectsStaleIncompleteAndUnknownSelections() throws {
        let requestID = UUID()
        let request = MCPAnalysisRequest(schemaVersion: 1, requestID: requestID, status: "pending", updatedAt: 0, title: "Synthetic", totalSeconds: 60, goal: "", audience: "", instructions: "", pages: (1...3).map { index in
            MCPAnalysisRequest.Page(slideIndex: index, body: "Original", notes: "", roleHint: nil, points: [SourcePoint(id: "s\(index)b1", slideIndex: index, text: "Original")], comparisonIDs: nil)
        })
        let pages = (1...3).map { index in PageSelection(slideIndex: index, selection: ExtractiveSelection(coreIDs: ["s\(index)b1"], detailIDs: [], role: "evidence", priority: 4)) }
        let direction = DeckDirection(focusPages: [2], supportingPages: [3])
        try MCPAnalysisValidation.validate(MCPAnalysisResult(requestID: requestID, direction: direction, selections: pages), request: request)
        #expect(throws: (any Error).self) { try MCPAnalysisValidation.validate(MCPAnalysisResult(requestID: UUID(), direction: direction, selections: pages), request: request) }
        #expect(throws: (any Error).self) { try MCPAnalysisValidation.validate(MCPAnalysisResult(requestID: requestID, direction: direction, selections: Array(pages.dropLast())), request: request) }
        for ids in [["unknown"], ["s2b1"], ["s1b1", "s1b1"], Array(repeating: "s1b1", count: 33)] {
            var invalid = pages
            invalid[0] = PageSelection(slideIndex: 1, selection: ExtractiveSelection(coreIDs: ids, detailIDs: [], role: "evidence", priority: 4))
            #expect(throws: (any Error).self) { try MCPAnalysisValidation.validate(MCPAnalysisResult(requestID: requestID, direction: direction, selections: invalid), request: request) }
        }
    }

    @Test func numericComparisonAllowsAdditionalConditionSource() throws {
        let points = [SourcePoint(id: "s1b1", slideIndex: 1, text: "表1｜モデル=A｜精度=90｜時間=12"), SourcePoint(id: "s1b2", slideIndex: 1, text: "表1｜モデル=B｜精度=85｜時間=8"), SourcePoint(id: "s1n1", slideIndex: 1, text: "同じ条件で測定しました。")]
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: points.map(\.id), detailIDs: [], role: "evidence", priority: 5), points: points, roleHint: "evidence")
        #expect(points.allSatisfy { brief.core.contains($0.text) })
    }

    @Test func permitsCompleteEnumerationsAndRejectsExcessiveSelection() throws {
        let slide = SlideInput(body: "", notes: "理由は3つあります。第一は量です。第二は関係です。第三は鮮度です。")
        let points = SourceExtractor.points(slide, index: 1)
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: points.map(\.id), detailIDs: [], role: "problem", priority: 4), points: points, roleHint: nil)
        #expect(points.allSatisfy { brief.core.contains($0.text) })
        let many = (1...33).map { SourcePoint(id: "s1n\($0)", slideIndex: 1, text: "原文\($0)。") }
        #expect(throws: (any Error).self) { try SourceExtractor.brief(ExtractiveSelection(coreIDs: many.map(\.id), detailIDs: [], role: "problem", priority: 4), points: many, roleHint: nil) }
    }

    @Test func keepsQuotedQuestionsAndNestedBracketsInOneSourcePoint() throws {
        let slide = SlideInput(body: "", notes: "聞かれるのは「最新版はどれ？」です。次は『担当者が「誰に聞く？」と言う』例です。確認（条件は何？）が必要です。")
        let points = SourceExtractor.points(slide, index: 2)
        #expect(points.map(\.text) == ["聞かれるのは「最新版はどれ？」です。", "次は『担当者が「誰に聞く？」と言う』例です。", "確認（条件は何？）が必要です。"])
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s2n1"], detailIDs: [], role: "problem", priority: 3), points: points, roleHint: nil)
        #expect(brief.core == "聞かれるのは「最新版はどれ？」です。")
    }

    @Test func strategyIncludesContentWithoutFocusRoles() throws {
        let page = PageBrief(slideIndex: 1, brief: EditorialBrief(core: "読む順番が分からない", detail: "", omit: "", role: "problem", priority: 3))
        let plan = try EditorialPlanner.assemble([page], slideCount: 1, budget: 150)
        #expect(plan.overallStrategy.contains("読む順番が分からない"))
    }

    private func pages() -> [PageBrief] {
        let roles = ["title", "problem", "problem", "problem", "mechanism", "overview", "solution", "mechanism", "solution", "mechanism", "solution", "solution", "value", "value", "closing"]
        return roles.enumerated().map { index, role in
            PageBrief(slideIndex: index + 1, brief: EditorialBrief(core: "ページ\(index + 1)の主張", detail: "ページ\(index + 1)の追加根拠", omit: "細かい閾値", role: role, priority: ["title", "closing"].contains(role) ? 2 : 4))
        }
    }
    @Test func usesBudgetWithVariedDurationsAndPreservesPageMeaning() throws {
        let plan = try EditorialPlanner.assemble(pages(), slideCount: 15, budget: 600)
        #expect(plan.slides.reduce(0) { $0 + $1.recommendedSeconds } == 600)
        #expect(Set(plan.slides.map(\.recommendedSeconds)).count > 2)
        #expect(plan.slides[0].recommendedSeconds <= 25)
        #expect(plan.slides[14].recommendedSeconds <= 15)
        for slide in plan.slides where slide.recommendedSeconds > 0 {
            #expect(slide.talkingPoints.contains("ページ\(slide.slideIndex)の主張"))
            if slide.treatment == "詳しく" {
                #expect(slide.talkingPoints.contains("ページ\(slide.slideIndex)の追加根拠"))
            }
        }
    }
    @Test func shorterBudgetChangesContentAndKeepsImportanceForSkippedPages() throws {
        let short = try EditorialPlanner.assemble(pages(), slideCount: 15, budget: 120)
        #expect(short.slides.reduce(0) { $0 + $1.recommendedSeconds } <= 120)
        #expect(short.slides.contains { $0.treatment == "省略" && $0.importanceScore > 0 })
        #expect(short.slides.allSatisfy { $0.treatment != "省略" || $0.talkingPoints.isEmpty })
    }
    @Test func preservesNarrativeAndLimitationsWhenDetailsCompete() throws {
        let roles = ["title", "problem", "solution", "mechanism", "evidence", "limitation", "conclusion", "supporting", "closing"]
        let pages = roles.enumerated().map { i, role in
            PageBrief(slideIndex: i + 1, brief: EditorialBrief(core: role == "limitation" ? "実データでは未検証です。" : "このページの主張です。", detail: "追加の説明と根拠です。", omit: "", role: role, priority: ["mechanism", "evidence"].contains(role) ? 5 : 2))
        }
        let plan = try EditorialPlanner.assemble(pages, slideCount: pages.count, budget: 240)
        #expect(plan.slides.reduce(0) { $0 + $1.recommendedSeconds } == 240)
        for index in [1, 4, 5, 6] { #expect(plan.slides[index].recommendedSeconds > 0) }
        #expect(plan.slides[5].talkingPoints.contains("実データでは未検証"))
        #expect(plan.slides[4].recommendedSeconds > plan.slides[7].recommendedSeconds)
    }
    @Test func rejectsInvalidOrMissingSummaries() {
        #expect(throws: (any Error).self) { try EditorialPlanner.assemble(Array(pages().dropLast()), slideCount: 15, budget: 600) }
        #expect(throws: (any Error).self) { try EditorialPlanner.validate(EditorialBrief(core: "", detail: "", omit: "", role: "solution", priority: 4)) }
        #expect(throws: (any Error).self) { try EditorialPlanner.validate(EditorialBrief(core: "主張", detail: "", omit: "", role: "unknown", priority: 4)) }
    }
    @Test func doesNotStretchSingleTitleToTenMinutes() throws {
        let page = PageBrief(slideIndex: 1, brief: EditorialBrief(core: "タイトル", detail: "", omit: "", role: "title", priority: 5))
        let plan = try EditorialPlanner.assemble([page], slideCount: 1, budget: 600)
        #expect(plan.slides[0].recommendedSeconds <= 25)
    }
    @Test func assemblyIsDeterministicAndSortsPages() throws {
        let a = try EditorialPlanner.assemble(pages(), slideCount: 15, budget: 600)
        let b = try EditorialPlanner.assemble(Array(pages().reversed()), slideCount: 15, budget: 600)
        #expect(a.slides.map(\.recommendedSeconds) == b.slides.map(\.recommendedSeconds))
        #expect(a.slides.map(\.talkingPoints) == b.slides.map(\.talkingPoints))
    }
    @Test func extractiveSummaryPreservesFactsAndUsesBodyAndNotes() throws {
        let slide = SlideInput(body: "送信は人が行う。", notes: "開始位置を変えます。読む順番は変えません。\n2:50\n1")
        let points = SourceExtractor.points(slide, index: 1)
        #expect(points.contains { $0.id.contains("b") && $0.text.contains("送信は人") })
        #expect(!points.contains { $0.text.contains("2:50") })
        let choice = ExtractiveSelection(coreIDs: ["s1n1", "s1n2"], detailIDs: ["s1b1"], role: "mechanism", priority: 4)
        let brief = try SourceExtractor.brief(choice, points: points, roleHint: nil)
        #expect(brief.core.contains("開始位置を変えます。"))
        #expect(brief.core.contains("読む順番は変えません。"))
        #expect(brief.detail == "送信は人が行う。")
        #expect(points[0].text == "開始位置を変えます。")
        #expect(points[1].text == "読む順番は変えません。")
    }
    @Test func rejectsUnknownSourceIDs() {
        let points = [SourcePoint(id: "s1n1", slideIndex: 1, text: "根拠")]
        #expect(throws: (any Error).self) {
            try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s2n1"], detailIDs: [], role: "solution", priority: 4), points: points, roleHint: nil)
        }
    }

    @Test func keepsTableLabelsAndValuesTogether() {
        let body = String(repeating: "参照の強さを分類する見出し", count: 6) + "\n供給\n1.0\n自動反映\n依存\n1.0\n読み直し"
        let points = SourceExtractor.points(SlideInput(body: body, notes: ""), index: 10)
        #expect(points.count == 1)
        #expect(points[0].text.contains("供給\n1.0\n自動反映"))
        #expect(points[0].text.contains("依存\n1.0\n読み直し"))
    }

    @Test func restoresAntecedentWithoutCrossingSourceOrigin() throws {
        let points = [
            SourcePoint(id: "s8n1", slideIndex: 8, text: "ノートの別の説明。"),
            SourcePoint(id: "s8b1", slideIndex: 8, text: "読む順番を人ごとに変えない。"),
            SourcePoint(id: "s8b2", slideIndex: 8, text: "変えると共通の会話が壊れる。")
        ]
        let selection = ExtractiveSelection(coreIDs: ["s8b2"], detailIDs: [], role: "mechanism", priority: 4)
        let brief = try SourceExtractor.brief(selection, points: points, roleHint: nil)
        #expect(brief.core.contains("読む順番を人ごとに変えない。"))
        #expect(brief.core.contains("変えると共通の会話が壊れる。"))
        #expect(!brief.core.contains("ノートの別の説明。"))
    }

    @Test func mergesRepeatedSourceIDsAndPrioritizesCore() throws {
        let points = [SourcePoint(id: "s1n1", slideIndex: 1, text: "主張。"), SourcePoint(id: "s1n2", slideIndex: 1, text: "根拠。")]
        let repeated = ExtractiveSelection(coreIDs: ["s1n1", "s1n1"], detailIDs: ["s1n2", "s1n2"], role: "solution", priority: 4)
        let brief = try SourceExtractor.brief(repeated, points: points, roleHint: nil)
        #expect(brief.core == "主張。")
        #expect(brief.detail == "根拠。")
        let overlap = ExtractiveSelection(coreIDs: ["s1n1"], detailIDs: ["s1n1", "s1n2"], role: "solution", priority: 4)
        let merged = try SourceExtractor.brief(overlap, points: points, roleHint: nil)
        #expect(merged.core == "主張。")
        #expect(merged.detail == "根拠。")
        #expect(merged.omit.isEmpty)
    }

    @Test func recognizesVerifiedQwenSamplingProfiles() {
        #expect(OllamaModelProfile.usesNonThinkingSampling("qwen3.5:9b"))
        #expect(OllamaModelProfile.usesNonThinkingSampling("Qwen3.8:27b"))
        #expect(OllamaModelProfile.usesNonThinkingSampling("hf.co/author/Qwen3.8-27B-GGUF:Q2_K"))
        #expect(!OllamaModelProfile.usesNonThinkingSampling("qwen3:8b"))
        #expect(!OllamaModelProfile.usesNonThinkingSampling("qwen3.80:27b"))
        #expect(!OllamaModelProfile.usesNonThinkingSampling("other-model"))
        #expect(OllamaModelProfile.supportsThinkingSwitch("hf.co/author/Qwen3.8-27B-GGUF:Q2_K"))
    }

    @Test func deckRankingPrioritizesEvidenceOverSupplementaryDetails() throws {
        let direction = DeckDirection(focusPages: [2], supportingPages: [4])
        try DeckDirector.validate(direction, count: 4)
        #expect(DeckDirector.priority(2, direction: direction) > DeckDirector.priority(4, direction: direction))
        let source = EditorialBrief(core: "結果", detail: "測定の詳細", omit: "", role: "evidence", priority: 4)
        let evidence = DeckDirector.apply(source, page: 2, direction: direction)
        #expect(evidence.role == "evidence")
        let pages = [PageBrief(slideIndex: 1, brief: evidence), PageBrief(slideIndex: 2, brief: EditorialBrief(core: "API一覧", detail: "実装の細部", omit: "", role: "supporting", priority: 1))]
        let plan = try EditorialPlanner.assemble(pages, slideCount: 2, budget: 60)
        #expect(plan.slides[0].recommendedSeconds > plan.slides[1].recommendedSeconds)
        #expect(plan.slides[0].talkingPoints.contains("測定の詳細"))
    }
    @Test func rejectsIncompleteDeckRanking() {
        #expect(throws: (any Error).self) { try DeckDirector.validate(DeckDirection(focusPages: [1], supportingPages: [1]), count: 2) }
        #expect(throws: (any Error).self) { try DeckDirector.validate(DeckDirection(focusPages: [3], supportingPages: []), count: 2) }
    }
    @Test func preservesQualificationInShortExplanation() throws {
        let slide = SlideInput(body: "予備評価", notes: "予測誤差は改善しました。ただし、ダミーデータによる予備評価であり、実データでの検証が必要です。")
        let points = [SourcePoint(id: "s1n1", slideIndex: 1, text: "予測誤差は改善しました。"), SourcePoint(id: "s1n2", slideIndex: 1, text: "ただし、ダミーデータによる予備評価であり、実データでの検証が必要です。")]
        let selection = ExtractiveSelection(coreIDs: ["s1n1"], detailIDs: [], role: "evidence", priority: 5)
        let brief = try SourceExtractor.brief(selection, points: points, roleHint: nil, source: slide)
        let plan = try EditorialPlanner.assemble([PageBrief(slideIndex: 1, brief: brief)], slideCount: 1, budget: 30)
        #expect(plan.slides[0].talkingPoints.contains("ダミーデータ"))
        #expect(plan.slides[0].talkingPoints.contains("実データでの検証が必要"))
        #expect(!plan.slides[0].omittedContent.contains("ダミーデータ"))
    }

    @Test func distinguishesConclusionAndFutureFromThanks() {
        #expect(SourceExtractor.roleHint(SlideInput(body: "結論", notes: "研究課題への回答"), index: 24, count: 25) == "conclusion")
        #expect(SourceExtractor.roleHint(SlideInput(body: "今後の展望", notes: "今後の計画"), index: 23, count: 25) == "future")
        #expect(SourceExtractor.roleHint(SlideInput(body: "まとめ", notes: "ご清聴ありがとうございました。"), index: 25, count: 25) == "closing")
        #expect(SourceExtractor.roleHint(SlideInput(body: "予備実験結果", notes: ""), index: 19, count: 25) == "evidence")
        #expect(SourceExtractor.roleHint(SlideInput(body: "背景と問題設定", notes: "提案します。"), index: 2, count: 25) == "problem")
        #expect(SourceExtractor.roleHint(SlideInput(body: "特徴量設計", notes: "説明します。"), index: 10, count: 25) == "mechanism")
    }

    @Test func titleTopicAndEvidenceSurvivePoorGlobalSelection() throws {
        let slides = [SlideInput(body: "特徴量選択を用いたシステム", notes: ""), SlideInput(body: "適応的特徴量選択", notes: ""), SlideInput(body: "実験結果", notes: "")]
        let direction = DeckDirection(focusPages: [1], supportingPages: [2])
        let method = EditorialBrief(core: "個人ごとの選択", detail: "根拠", omit: "", role: "mechanism", priority: 2)
        #expect(DeckDirector.apply(method, page: 2, direction: direction, slides: slides).priority == 5)
        let evidence = EditorialBrief(core: "予備結果", detail: "比較", omit: "", role: "evidence", priority: 1)
        #expect(DeckDirector.apply(evidence, page: 3, direction: direction, slides: slides).priority == 5)
    }
    @Test func qualificationsAlsoWorkWithoutSpeakerNotes() throws {
        let slide = SlideInput(body: "結果は改善。ただし、実データでの検証が必要です。", notes: "")
        let points = [SourcePoint(id: "s1b1", slideIndex: 1, text: "結果は改善。")]
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1b1"], detailIDs: [], role: "evidence", priority: 5), points: points, roleHint: nil, source: slide)
        #expect(brief.core.contains("ただし、実データでの検証が必要です。"))
    }

    @Test func globalSupportingVoteCannotEraseStoryPages() throws {
        let roles = ["title", "problem", "overview", "solution", "mechanism", "evidence", "limitation", "conclusion", "supporting", "closing"]
        let direction = DeckDirection(focusPages: [5], supportingPages: [2, 3, 4, 6, 9])
        try DeckDirector.validate(direction, count: roles.count)
        let pages = roles.enumerated().map { i, role in
            let brief = EditorialBrief(core: "ページ固有の主張とその前提条件を説明します。", detail: "具体的な根拠や利用例を説明します。", omit: "補助的な情報", role: role, priority: 4)
            return PageBrief(slideIndex: i + 1, brief: DeckDirector.apply(brief, page: i + 1, direction: direction))
        }
        let plan = try EditorialPlanner.assemble(pages, slideCount: pages.count, budget: 300)
        #expect(plan.slides.reduce(0) { $0 + $1.recommendedSeconds } == 300)
        for index in [1, 2, 3, 5] { #expect(plan.slides[index].recommendedSeconds > 0) }
        #expect(plan.slides[8].recommendedSeconds == 0)
        #expect(plan.slides[4].recommendedSeconds < plan.slides[3].recommendedSeconds * 2)
    }

    @Test func punctuationDoesNotCapSubstantiveResults() throws {
        let content = String(repeating: "モデル比較の結果と測定条件を示す十分な説明", count: 6)
        let brief = EditorialBrief(core: content, detail: "", omit: "", role: "evidence", priority: 5)
        let plan = try EditorialPlanner.assemble([PageBrief(slideIndex: 1, brief: brief)], slideCount: 1, budget: 75)
        #expect(plan.slides[0].recommendedSeconds == 75)
        #expect(plan.slides[0].talkingPoints == content)
    }

    @Test func budgetChangesSelectionWithoutDroppingRetainedConditions() throws {
        let p = pages()
        let short = try EditorialPlanner.assemble(p, slideCount: p.count, budget: 183)
        let long = try EditorialPlanner.assemble(p, slideCount: p.count, budget: 603)
        #expect(short.slides.reduce(0) { $0 + $1.recommendedSeconds } == 183)
        #expect(long.slides.reduce(0) { $0 + $1.recommendedSeconds } == 603)
        #expect(short.slides.filter { $0.recommendedSeconds > 0 }.count < long.slides.filter { $0.recommendedSeconds > 0 }.count)
        for item in long.slides where item.recommendedSeconds > 0 {
            #expect(item.talkingPoints.contains(p[item.slideIndex - 1].brief.core))
        }
    }

    @Test func bodyOnlyConditionsSurviveEvenWhenNotesExist() throws {
        let slide = SlideInput(body: "連絡文を作る。送信はしない — 最後に送るのは人間。走査できていない資料は未走査と表示する。影響なしとは断定しない。", notes: "担当者を期限順に提示します。")
        let points = SourceExtractor.points(slide, index: 1)
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1n1"], detailIDs: [], role: "solution", priority: 4), points: points, roleHint: nil, source: slide)
        let plan = try EditorialPlanner.assemble([PageBrief(slideIndex: 1, brief: brief)], slideCount: 1, budget: 20)
        #expect(plan.slides[0].talkingPoints.contains("送信はしない"))
        #expect(plan.slides[0].talkingPoints.contains("未走査"))
        #expect(plan.slides[0].talkingPoints.contains("断定しない"))
        #expect(!plan.slides[0].omittedContent.contains("送信はしない"))
    }

    @Test func protectingBodyCaveatDoesNotForceEntireTableIntoCore() throws {
        let slide = SlideInput(body: "比較結果\n表の補助列\n補足値123\n※ ダミーデータによる予備評価。", notes: "予測誤差を比較しました。")
        let points = SourceExtractor.points(slide, index: 1)
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1n1"], detailIDs: [], role: "evidence", priority: 5), points: points, roleHint: nil, source: slide)
        #expect(brief.core.contains("ダミーデータによる予備評価"))
        #expect(!brief.core.contains("補足値123"))
        #expect(brief.omit.contains("補足値123"))
    }

    private func tableXML(_ rows: [[String]], properties: String = "", cellAttributes: String = "") -> String {
        "<a:tbl><a:tblPr \(properties)/>" + rows.map { row in
            "<a:tr>" + row.map { "<a:tc \(cellAttributes)><a:txBody><a:p><a:r><a:t>\($0)</a:t></a:r></a:p></a:txBody></a:tc>" }.joined() + "</a:tr>"
        }.joined() + "</a:tbl>"
    }

    @Test func nativeNumericTableRetainsMetricValuePairs() {
        let xml = tableXML([["", "MAE", "RMSE"], ["改善法", "0.12", "0.20"], ["基準法", "0.35", "0.40"]])
        let body = PPTXReader.extractText(fromSlideXML: xml)
        #expect(body.contains("表1｜改善法｜MAE=0.12｜RMSE=0.20"))
        #expect(body.contains("表1｜基準法｜MAE=0.35｜RMSE=0.40"))
        let points = SourceExtractor.points(SlideInput(body: body, notes: ""), index: 3)
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.text.contains("MAE=") && $0.text.contains("RMSE=") })
        #expect(SourceExtractor.comparisonIDs(points, roleHint: "evidence") == ["s3b1", "s3b2"])
        #expect(SourceExtractor.comparisonIDs(points, roleHint: "mechanism") == nil)
    }

    @Test func headerlessOrMergedTablesDoNotInventHeaders() {
        let rows = [["機種A", "12", "20"], ["機種B", "13", "25"]]
        let plain = PPTXReader.extractText(fromSlideXML: tableXML(rows, properties: "firstRow=\"0\""))
        #expect(plain.contains("列1=機種A｜列2=12｜列3=20"))
        #expect(!plain.contains("機種A=機種B"))
        let ambiguous = PPTXReader.extractText(fromSlideXML: tableXML([["手法", "説明"], ["処理A", "文章の説明"]]))
        #expect(!ambiguous.contains("表1｜"))
        #expect(ambiguous.contains("処理A") && ambiguous.contains("文章の説明"))
        let merged = PPTXReader.extractText(fromSlideXML: tableXML(rows, cellAttributes: "gridSpan=\"2\""))
        #expect(!merged.contains("表1｜"))
        #expect(merged.contains("機種A") && merged.contains("25"))
    }

    @Test func tableEntitiesAndCellParagraphsArePreserved() {
        let xml = tableXML([["手法", "誤差", "差分"], ["A &amp; B", "0.01", "-0.2"], ["C", "0.03", "-0.1"]], properties: "firstRow=\"1\"")
        let body = PPTXReader.extractText(fromSlideXML: xml)
        #expect(body.contains("手法=A & B｜誤差=0.01｜差分=-0.2"))
        #expect(!body.contains("&amp;"))
    }

    @Test func numericComparisonRequiresTwoDistinctRows() throws {
        let points = [SourcePoint(id: "s1b1", slideIndex: 1, text: "表1｜改善法｜誤差=0.1｜分散=0.2"), SourcePoint(id: "s1b2", slideIndex: 1, text: "表1｜基準法｜誤差=0.3｜分散=0.4")]
        #expect(throws: (any Error).self) {
            try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1b1", "s1b1"], detailIDs: [], role: "evidence", priority: 5), points: points, roleHint: "evidence")
        }
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1b1", "s1b2"], detailIDs: [], role: "evidence", priority: 5), points: points, roleHint: "evidence")
        #expect(brief.core.contains("改善法｜誤差=0.1"))
        #expect(brief.core.contains("基準法｜誤差=0.3"))
    }

    @Test func featureRanksAreNotTreatedAsModelComparison() {
        let points = [SourcePoint(id: "s1b1", slideIndex: 1, text: "表1｜#=1｜特徴量=温度｜寄与=0.3"), SourcePoint(id: "s1b2", slideIndex: 1, text: "表1｜#=2｜特徴量=湿度｜寄与=0.2")]
        #expect(SourceExtractor.comparisonIDs(points, roleHint: "evidence") == nil)
    }

    @Test func permissionConditionsSurviveShortSelection() throws {
        let source = SlideInput(body: "AI連携", notes: "AIがツールを呼び出します。組織でアクセスが許可されていないと利用できません。")
        let points = SourceExtractor.points(source, index: 1)
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1n1"], detailIDs: [], role: "solution", priority: 4), points: points, roleHint: nil, source: source)
        #expect(brief.core.contains("許可されていないと利用できません"))
    }

    @Test func minimumDataRequirementSurvivesShortSelection() throws {
        let source = SlideInput(body: "予測モデル", notes: "決定木を使います。30件以上の測定値でモデルに切り替えます。")
        let points = SourceExtractor.points(source, index: 1)
        let brief = try SourceExtractor.brief(ExtractiveSelection(coreIDs: ["s1n1"], detailIDs: [], role: "mechanism", priority: 4), points: points, roleHint: nil, source: source)
        #expect(brief.core.contains("30件以上の測定値"))
    }

    @Test func analysisPreflightRejectsEmptyPagesBeforeGeneration() {
        let pages = [SlideInput(body: "主張", notes: ""), SlideInput(body: "  ", notes: "\n2\n")]
        #expect(AnalysisInputValidation.problem(slides: pages, minutes: 10)?.contains("スライド2") == true)
        #expect(AnalysisInputValidation.problem(slides: pages, minutes: 10, requireContent: false) == nil)
        #expect(AnalysisInputValidation.problem(slides: [], minutes: 10) != nil)
    }

    @Test func importedBudgetIsValidatedWithoutSilentlyClampingIt() {
        let slides = [SlideInput(body: "主張", notes: "")]
        #expect(AnalysisInputValidation.problem(slides: slides, minutes: 2.5) == nil)
        #expect(AnalysisInputValidation.problem(slides: slides, minutes: 0) != nil)
        #expect(AnalysisInputValidation.problem(slides: slides, minutes: 100) != nil)
        #expect(AnalysisInputValidation.problem(slides: slides, minutes: .infinity) != nil)
        #expect(AnalysisInputValidation.problem(slides: slides, minutes: .nan) != nil)
    }

    @Test func ollamaURLHandlesWhitespaceTrailingSlashAndProxyPath() throws {
        let local = try AnalysisInputValidation.ollamaEndpoint(" http://127.0.0.1:11434/ ")
        #expect(local.absoluteString == "http://127.0.0.1:11434/api/generate")
        let proxy = try AnalysisInputValidation.ollamaEndpoint("https://localhost/proxy/")
        #expect(proxy.absoluteString == "https://localhost/proxy/api/generate")
        #expect(throws: (any Error).self) { try AnalysisInputValidation.ollamaEndpoint("localhost:11434") }
        #expect(throws: (any Error).self) { try AnalysisInputValidation.ollamaEndpoint("http://localhost/?a=1") }
    }

}
