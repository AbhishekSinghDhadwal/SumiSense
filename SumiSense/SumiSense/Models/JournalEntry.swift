import Foundation

struct JournalEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var rawText: String
    var manualTags: [String]
    var detectedTags: [String]
    var generatedSummary: String?
    var generatedStatus: SignalState?
    var moodScore: Double?
    var stressScore: Double?
    var cravingScore: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        rawText: String,
        manualTags: [String] = [],
        detectedTags: [String] = [],
        generatedSummary: String? = nil,
        generatedStatus: SignalState? = nil,
        moodScore: Double? = nil,
        stressScore: Double? = nil,
        cravingScore: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.rawText = rawText
        self.manualTags = manualTags
        self.detectedTags = detectedTags
        self.generatedSummary = generatedSummary
        self.generatedStatus = generatedStatus
        self.moodScore = moodScore
        self.stressScore = stressScore
        self.cravingScore = cravingScore
    }
}
