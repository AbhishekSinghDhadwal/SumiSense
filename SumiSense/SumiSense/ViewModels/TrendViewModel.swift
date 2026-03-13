import Foundation
import Combine

@MainActor
final class TrendViewModel: ObservableObject {
    private(set) var appState: AppStateViewModel
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppStateViewModel) {
        self.appState = appState
        appState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var selectedMetric: WellnessMetricType {
        get { appState.selectedMetric }
        set { appState.selectedMetric = newValue }
    }

    var selectedWindow: Int {
        get { appState.selectedTrendWindow }
        set {
            appState.selectedTrendWindow = newValue
            appState.refreshTrend()
        }
    }

    var metrics: [WellnessMetricPoint] { appState.metrics.sorted { $0.date < $1.date } }
    var latestTrendAssessment: TrendAssessment? { appState.latestTrendAssessment }
    var isRefreshing: Bool { appState.isRefreshingTrend }
    var isPrewarmingModels: Bool { appState.isPrewarmingModels }
    var runtimeMessage: String? { appState.trendRuntimeMessage }
    var chronosDescriptor: String {
        "\(appState.melangeConfig.chronosModelID) @ v\(appState.melangeConfig.chronosModelVersion)"
    }

    var trendEngineStatusText: String {
        guard let latestTrendAssessment else {
            return "Awaiting trend inference."
        }
        return latestTrendAssessment.source == .melange
            ? "Chronos active on-device (\(chronosDescriptor))."
            : "Fallback trend heuristic active."
    }

    func refresh() {
        appState.refreshTrend()
    }
}
