import Foundation

struct DailySignalAssessment: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let status: SignalState
    let summary: String
    let explanation: String
    let signalTags: [String]
    let confidence: Double
    let source: InferenceSource

    init(
        id: UUID = UUID(),
        date: Date,
        status: SignalState,
        summary: String,
        explanation: String,
        signalTags: [String],
        confidence: Double,
        source: InferenceSource
    ) {
        self.id = id
        self.date = date
        self.status = status
        self.summary = summary
        self.explanation = explanation
        self.signalTags = signalTags
        self.confidence = confidence
        self.source = source
    }
}
