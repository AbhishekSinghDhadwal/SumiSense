import Foundation
import Combine

@MainActor
final class ShareViewModel: ObservableObject {
    private(set) var appState: AppStateViewModel
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppStateViewModel) {
        self.appState = appState
        appState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var entries: [JournalEntry] {
        appState.journalEntries.sorted { $0.date > $1.date }
    }

    var selectedEntryID: UUID? {
        get { appState.selectedShareEntryID }
        set { appState.selectedShareEntryID = newValue }
    }

    var selectedMode: ShareMode {
        get { appState.selectedShareMode }
        set { appState.selectedShareMode = newValue }
    }

    var selectedSource: ShareSourceSelection {
        get { appState.selectedShareSource }
        set { appState.selectedShareSource = newValue }
    }

    var sourceHelperText: String { selectedSource.helperText }
    var sourcePreviewText: String { appState.shareSourcePreviewText }
    var sevenDayEntryCount: Int { appState.sevenDayEntries.count }

    var latestResult: RedactionResult? { appState.latestRedactionResult }
    var isGenerating: Bool { appState.isGeneratingShare }
    var isLongRunning: Bool { appState.isShareLongRunning }
    var isPrewarmingModels: Bool { appState.isPrewarmingModels }
    var runtimeMessage: String? { appState.redactionRuntimeMessage }

    func generate() {
        appState.generateShareOutput()
    }
}
