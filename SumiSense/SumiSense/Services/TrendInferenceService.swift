import Foundation

protocol TrendInferenceService {
    func analyze(metrics: [WellnessMetricPoint], windowDays: Int) async throws -> TrendAssessment

    func warmUp() async throws
}

extension TrendInferenceService {
    func warmUp() async throws {}
}
