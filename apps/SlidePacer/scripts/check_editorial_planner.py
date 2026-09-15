"""Run production point mapping tests without starting the macOS app."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
s = (root / 'SlidePacer/ContentView.swift').read_text()
models = s[s.index('@Generable(description: "1枚'):s.index('enum OllamaClient')]
models = re.sub(r'@(?:Guide|Generable)(?:\([^\n]*\))?\n', '', models)
slide = s[s.index('struct SlideInput:'):s.index('// MARK: - JSON取り込み用モデル')]
mcp_source = (root / 'SlidePacer/MCPPreparation.swift').read_text()
mcp_models = mcp_source[mcp_source.index('struct MCPAnalysisRequest:'):mcp_source.index('@MainActor final class')]
tests = (root / 'SlidePacerTests/SlidePacerTests.swift').read_text()
tests = tests[tests.index('struct SlidePacerTests'):].replace('@Test ', '')
tests = tests.replace('#expect(throws: (any Error).self)', 'expectThrows').replace('#expect(', 'assert(')
helper = '''
func expectThrows(_ block: () throws -> Any) {
    do { _ = try block() } catch { return }
    fatalError("Expected an error")
}
'''
runner = '''
let tests = SlidePacerTests()
try tests.usesBudgetWithVariedDurationsAndPreservesPageMeaning()
try tests.shorterBudgetChangesContentAndKeepsImportanceForSkippedPages()
tests.rejectsInvalidOrMissingSummaries()
try tests.doesNotStretchSingleTitleToTenMinutes()
try tests.assemblyIsDeterministicAndSortsPages()
try tests.extractiveSummaryPreservesFactsAndUsesBodyAndNotes()
tests.rejectsUnknownSourceIDs()
tests.keepsTableLabelsAndValuesTogether()
try tests.restoresAntecedentWithoutCrossingSourceOrigin()
try tests.mergesRepeatedSourceIDsAndPrioritizesCore()
tests.recognizesVerifiedQwenSamplingProfiles()
try tests.deckRankingPrioritizesEvidenceOverSupplementaryDetails()
tests.rejectsIncompleteDeckRanking()
try tests.preservesQualificationInShortExplanation()
tests.distinguishesConclusionAndFutureFromThanks()
try tests.titleTopicAndEvidenceSurvivePoorGlobalSelection()
try tests.qualificationsAlsoWorkWithoutSpeakerNotes()
try tests.preservesNarrativeAndLimitationsWhenDetailsCompete()
try tests.globalSupportingVoteCannotEraseStoryPages()
try tests.punctuationDoesNotCapSubstantiveResults()
try tests.budgetChangesSelectionWithoutDroppingRetainedConditions()
try tests.bodyOnlyConditionsSurviveEvenWhenNotesExist()
try tests.protectingBodyCaveatDoesNotForceEntireTableIntoCore()
tests.nativeNumericTableRetainsMetricValuePairs()
tests.headerlessOrMergedTablesDoNotInventHeaders()
tests.tableEntitiesAndCellParagraphsArePreserved()
try tests.numericComparisonRequiresTwoDistinctRows()
tests.featureRanksAreNotTreatedAsModelComparison()
try tests.permissionConditionsSurviveShortSelection()
try tests.minimumDataRequirementSurvivesShortSelection()
tests.analysisPreflightRejectsEmptyPagesBeforeGeneration()
tests.importedBudgetIsValidatedWithoutSilentlyClampingIt()
try tests.ollamaURLHandlesWhitespaceTrailingSlashAndProxyPath()
try tests.strategyIncludesContentWithoutFocusRoles()
try tests.keepsQuotedQuestionsAndNestedBracketsInOneSourcePoint()
try tests.permitsCompleteEnumerationsAndRejectsExcessiveSelection()
try tests.numericComparisonAllowsAdditionalConditionSource()
try tests.nativeMCPRejectsStaleIncompleteAndUnknownSelections()
print("38 regression tests passed")
'''
build = root / '.build'
build.mkdir(exist_ok=True)
harness = build / 'check-point-planner.swift'
harness.write_text('import Foundation\nimport Compression\n' + slide + models + mcp_models + helper + tests + runner)
subprocess.run(['xcrun', 'swift', '-module-cache-path', str(build / 'module-cache'), str(harness)], check=True, cwd=root)
