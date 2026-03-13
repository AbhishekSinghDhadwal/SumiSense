import Foundation

enum WellnessMetricType: String, Codable, CaseIterable, Identifiable {
    case sleepHours
    case moodScore
    case stressScore
    case cravingScore
    case energyScore
    case steps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepHours:
            return "Sleep"
        case .moodScore:
            return "Mood"
        case .stressScore:
            return "Stress"
        case .cravingScore:
            return "Craving"
        case .energyScore:
            return "Energy"
        case .steps:
            return "Activity"
        }
    }

    var unit: String {
        switch self {
        case .sleepHours:
            return "h"
        case .steps:
            return "steps"
        default:
            return "/10"
        }
    }

    var lowerIsBetter: Bool {
        switch self {
        case .stressScore, .cravingScore:
            return true
        case .sleepHours, .moodScore, .energyScore, .steps:
            return false
        }
    }
}
