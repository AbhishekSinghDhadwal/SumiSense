import Foundation

protocol JournalInferenceService {
    func analyze(
        note: String,
        manualTags: [String],
        contextEntries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) async throws -> DailySignalAssessment

    func warmUp() async throws
}

extension JournalInferenceService {
    func warmUp() async throws {}
}
