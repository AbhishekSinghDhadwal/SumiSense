import Foundation

struct TrendAssessment: Identifiable, Codable, Hashable {
    let id: UUID
    let windowDays: Int
    let stabilityScore: Double
    let trendDirection: TrendDirection
    let plainLanguageSummary: String
    let metricHighlights: [String]
    let baselineAverage: Double
    let recentAverage: Double
    let confidence: Double
    let source: InferenceSource

    init(
        id: UUID = UUID(),
        windowDays: Int,
        stabilityScore: Double,
        trendDirection: TrendDirection,
        plainLanguageSummary: String,
        metricHighlights: [String],
        baselineAverage: Double,
        recentAverage: Double,
        confidence: Double,
        source: InferenceSource
    ) {
        self.id = id
        self.windowDays = windowDays
        self.stabilityScore = stabilityScore
        self.trendDirection = trendDirection
        self.plainLanguageSummary = plainLanguageSummary
        self.metricHighlights = metricHighlights
        self.baselineAverage = baselineAverage
        self.recentAverage = recentAverage
        self.confidence = confidence
        self.source = source
    }
}
