import Foundation

struct RedactionResult: Identifiable, Codable, Hashable {
    let id: UUID
    let mode: ShareMode
    let sourceText: String
    let outputText: String
    let redactionsApplied: [String]
    let source: InferenceSource

    init(
        id: UUID = UUID(),
        mode: ShareMode,
        sourceText: String,
        outputText: String,
        redactionsApplied: [String],
        source: InferenceSource
    ) {
        self.id = id
        self.mode = mode
        self.sourceText = sourceText
        self.outputText = outputText
        self.redactionsApplied = redactionsApplied
        self.source = source
    }
}
