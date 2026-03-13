import Foundation
import Combine

@MainActor
final class JournalViewModel: ObservableObject {
    @Published var manualTagsText: String = ""

    private(set) var appState: AppStateViewModel
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppStateViewModel) {
        self.appState = appState
        appState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var noteDraft: String {
        get { appState.noteDraft }
        set { appState.noteDraft = newValue }
    }

    var latestAssessment: DailySignalAssessment? { appState.latestAssessment }
    var recentEntries: [JournalEntry] { Array(appState.journalEntries.suffix(6)).reversed() }
    var isAnalyzing: Bool { appState.isAnalyzing }
    var isPrewarmingModels: Bool { appState.isPrewarmingModels }
    var runtimeMessage: String? { appState.journalRuntimeMessage }

    func analyzeNote() {
        let tags = manualTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        appState.analyzeDraft(manualTags: tags)
    }
}
