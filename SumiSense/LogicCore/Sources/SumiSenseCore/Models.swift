import Foundation

public enum SignalState: String {
    case stable
    case watch
    case elevated
}

public enum TrendDirection: String {
    case improving
    case stable
    case worsening
    case mixed
}

public enum ShareMode: String {
    case personal
    case clinician
    case researchSafe
}

public struct WellnessMetricPoint {
    public let date: Date
    public let sleepHours: Double
    public let moodScore: Double
    public let stressScore: Double
    public let cravingScore: Double
    public let energyScore: Double

    public init(
        date: Date,
        sleepHours: Double,
        moodScore: Double,
        stressScore: Double,
        cravingScore: Double,
        energyScore: Double
    ) {
        self.date = date
        self.sleepHours = sleepHours
        self.moodScore = moodScore
        self.stressScore = stressScore
        self.cravingScore = cravingScore
        self.energyScore = energyScore
    }
}

public struct TrendResult {
    public let direction: TrendDirection
    public let summary: String
}

public struct RedactionOutput {
    public let transformed: String
    public let tags: [String]
}
