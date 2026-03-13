import Foundation

struct WellnessMetricPoint: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var sleepHours: Double
    var moodScore: Double
    var stressScore: Double
    var cravingScore: Double
    var energyScore: Double
    var steps: Int?
    var restingHeartRate: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        sleepHours: Double,
        moodScore: Double,
        stressScore: Double,
        cravingScore: Double,
        energyScore: Double,
        steps: Int? = nil,
        restingHeartRate: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.sleepHours = sleepHours
        self.moodScore = moodScore
        self.stressScore = stressScore
        self.cravingScore = cravingScore
        self.energyScore = energyScore
        self.steps = steps
        self.restingHeartRate = restingHeartRate
    }

    func value(for metric: WellnessMetricType) -> Double {
        switch metric {
        case .sleepHours:
            return sleepHours
        case .moodScore:
            return moodScore
        case .stressScore:
            return stressScore
        case .cravingScore:
            return cravingScore
        case .energyScore:
            return energyScore
        case .steps:
            return Double(steps ?? 0)
        }
    }
}
