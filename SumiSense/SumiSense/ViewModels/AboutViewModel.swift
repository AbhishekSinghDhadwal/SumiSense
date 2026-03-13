import Foundation
import Combine

@MainActor
final class AboutViewModel: ObservableObject {
    private(set) var appState: AppStateViewModel
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppStateViewModel) {
        self.appState = appState
        appState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var modelReadinessText: String { appState.modelReadinessText }
    var melangeConfigured: Bool { appState.melangeConfig.hasPersonalKey }
    var melangeAvailable: Bool { MelangeAvailability.sdkAvailable }
    var personalKeySource: String { appState.melangeConfig.personalKeySource }

    var journalSource: InferenceSource { appState.lastJournalSource }
    var trendSource: InferenceSource { appState.lastTrendSource }
    var redactionSource: InferenceSource { appState.lastRedactionSource }

    var journalRuntimeMessage: String? { appState.journalRuntimeMessage }
    var trendRuntimeMessage: String? { appState.trendRuntimeMessage }
    var redactionRuntimeMessage: String? { appState.redactionRuntimeMessage }
    var journalMelangeEnabled: Bool {
        get { appState.journalMelangeEnabled }
        set { appState.setJournalMelangeEnabled(newValue) }
    }
    var isSwitchingJournalMelange: Bool { appState.isSwitchingJournalMelange }
    var isJournalModelReady: Bool { appState.isJournalModelReady }
    var isTrendModelReady: Bool { appState.isTrendModelReady }
    var isRedactionModelReady: Bool { appState.isRedactionModelReady }
    var isRefreshingInferenceStatus: Bool { appState.isRefreshingInferenceStatus }

    var chronosModelDescriptor: String {
        "\(appState.melangeConfig.chronosModelID) @ v\(appState.melangeConfig.chronosModelVersion)"
    }

    var redactionModelDescriptor: String {
        "\(appState.melangeConfig.redactionModelID) @ v\(appState.melangeConfig.redactionModelVersion)"
    }

    var journalModelDescriptor: String {
        if let version = appState.melangeConfig.journalModelVersion {
            return "\(appState.melangeConfig.journalModelID) @ v\(version)"
        }
        return "\(appState.melangeConfig.journalModelID) @ default"
    }

    func resetDemoData() {
        appState.resetToSeedData()
    }

    func refreshInferenceStatus() {
        appState.refreshInferenceStatus()
    }
}
