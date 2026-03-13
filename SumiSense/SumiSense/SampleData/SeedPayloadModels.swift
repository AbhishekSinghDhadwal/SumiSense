import Foundation

struct SeedProfile: Codable {
    let id: String
    let displayName: String
    let baselineSensitivity: Double
    let demoModeEnabled: Bool
}

struct SeedJournalEntry: Codable {
    let id: String
    let date: String
    let rawText: String
    let manualTags: [String]
}

struct SeedMetricPoint: Codable {
    let date: String
    let sleepHours: Double
    let moodScore: Double
    let stressScore: Double
    let cravingScore: Double
    let energyScore: Double
    let steps: Int?
    let restingHeartRate: Double?
}
