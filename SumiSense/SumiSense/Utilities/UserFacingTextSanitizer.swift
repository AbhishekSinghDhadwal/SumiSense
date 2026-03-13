import Foundation

enum UserFacingTextSanitizer {
    static func sanitizeJournalSummary(_ text: String, status: SignalState) -> String {
        let cleaned = sanitizeReasoningLeak(text)
        guard !cleaned.isEmpty else { return defaultSummary(for: status) }
        guard !looksLikeReasoningLeak(cleaned) else { return defaultSummary(for: status) }

        let sentence = cleaned
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !looksLikeReasoningLeak($0) })

        let selected = sentence.map { "\($0)." } ?? cleaned
        return String(selected.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeJournalExplanation(_ text: String, status: SignalState, tags: [String]) -> String {
        let cleaned = sanitizeReasoningLeak(text)
        guard !cleaned.isEmpty else { return defaultExplanation(for: status, tags: tags) }
        guard !looksLikeReasoningLeak(cleaned) else { return defaultExplanation(for: status, tags: tags) }
        return String(cleaned.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeAssessment(_ assessment: DailySignalAssessment) -> DailySignalAssessment {
        DailySignalAssessment(
            date: assessment.date,
            status: assessment.status,
            summary: sanitizeJournalSummary(assessment.summary, status: assessment.status),
            explanation: sanitizeJournalExplanation(
                assessment.explanation,
                status: assessment.status,
                tags: assessment.signalTags
            ),
            signalTags: assessment.signalTags,
            confidence: assessment.confidence,
            source: assessment.source
        )
    }

    private static func sanitizeReasoningLeak(_ input: String) -> String {
        var text = input

        text = text.replacingOccurrences(
            of: "(?is)<think>.*?</think>",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?im)^\\s*<think>.*$",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?is)```(?:json)?",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "```", with: " ")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        let blockedPhrases = [
            "the user wants",
            "strict json",
            "provided guidelines",
            "first, i need to",
            "let's tackle this",
            "parse all the",
            "my response should",
            "i should output"
        ]

        let filteredLines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let normalized = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return false }
                return !blockedPhrases.contains(where: { normalized.contains($0) })
            }

        return filteredLines
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeReasoningLeak(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = [
            "<think>",
            "the user wants",
            "strict json",
            "provided guidelines",
            "first, i need to",
            "let's tackle this",
            "parse all the",
            "my response should",
            "i should output",
            "the status can be stable",
            "stable, watch, or elevated",
            "status: stable|watch|elevated",
            "\"status\":\"stable|watch|elevated\"",
            "return strict json",
            "json output"
        ]
        return markers.contains(where: { normalized.contains($0) })
    }

    private static func defaultSummary(for status: SignalState) -> String {
        switch status {
        case .stable:
            return "Your note reflects a mostly stable pattern today."
        case .watch:
            return "Your note suggests a mild stability shift."
        case .elevated:
            return "Your note shows elevated signals relative to baseline."
        }
    }

    private static func defaultExplanation(for status: SignalState, tags: [String]) -> String {
        let tagText = tags.isEmpty ? "language pattern shifts" : tags.joined(separator: ", ")
        switch status {
        case .stable:
            return "Current note and recent metrics appear near your baseline with limited instability."
        case .watch:
            return "Signals suggest a pattern change (\(tagText)). Consider a lower-load day and check-in support."
        case .elevated:
            return "Elevated signals detected (\(tagText)) compared with baseline. Prioritize supportive routines."
        }
    }
}
