import Foundation

final class RuleBasedJournalService: JournalInferenceService {
    private struct PhraseBucket {
        let tag: String
        let phrases: [String]
        let weight: Double
    }

    private let riskBuckets: [PhraseBucket] = [
        PhraseBucket(tag: "sleep disruption", phrases: ["barely slept", "didn't sleep", "awake all night", "restless", "wired"], weight: 1.2),
        PhraseBucket(tag: "high stress", phrases: ["anxious", "overwhelmed", "stressed", "burned out", "panicked"], weight: 1.0),
        PhraseBucket(tag: "craving language", phrases: ["thought about using", "craving", "urge", "wanted to use"], weight: 1.5),
        PhraseBucket(tag: "social isolation", phrases: ["didn't tell anyone", "isolated", "kept it to myself", "alone"], weight: 0.9),
        PhraseBucket(tag: "emotional fatigue", phrases: ["drained", "numb", "empty", "exhausted"], weight: 0.7)
    ]

    private let supportBuckets: [PhraseBucket] = [
        PhraseBucket(tag: "support seeking", phrases: ["reached out", "asked for help", "talked to", "called my sponsor"], weight: -0.7),
        PhraseBucket(tag: "recovery-positive", phrases: ["stayed on schedule", "went for a walk", "kept routine", "slept okay"], weight: -0.4)
    ]

    func analyze(
        note: String,
        manualTags: [String],
        contextEntries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) async throws -> DailySignalAssessment {
        let normalized = note.lowercased()

        var score = 0.0
        var tags: [String] = []

        for bucket in riskBuckets {
            if bucket.phrases.contains(where: normalized.contains) {
                score += bucket.weight
                tags.append(bucket.tag)
            }
        }

        for bucket in supportBuckets {
            if bucket.phrases.contains(where: normalized.contains) {
                score += bucket.weight
                tags.append(bucket.tag)
            }
        }

        tags.append(contentsOf: manualTags)
        tags = Array(NSOrderedSet(array: tags).compactMap { $0 as? String })

        let state: SignalState
        if score >= 2.3 {
            state = .elevated
        } else if score >= 1.0 {
            state = .watch
        } else {
            state = .stable
        }

        let summary = summaryText(for: state, tags: tags)
        let explanation = explanationText(for: state, score: score, tags: tags)
        let confidence = min(0.95, max(0.55, 0.62 + abs(score) * 0.08))

        return DailySignalAssessment(
            date: Date(),
            status: state,
            summary: summary,
            explanation: explanation,
            signalTags: tags,
            confidence: confidence,
            source: .fallback
        )
    }

    private func summaryText(for state: SignalState, tags: [String]) -> String {
        let topTags = Array(tags.prefix(2)).joined(separator: " and ")

        switch state {
        case .stable:
            return topTags.isEmpty
                ? "Today looks close to your baseline with no major stability shift."
                : "Today looks mostly stable, with mild signals around \(topTags)."
        case .watch:
            return "This entry shows a pattern change with elevated signals in \(topTags.isEmpty ? "stress language" : topTags)."
        case .elevated:
            return "This note contains elevated signals suggesting a meaningful stability shift."
        }
    }

    private func explanationText(for state: SignalState, score: Double, tags: [String]) -> String {
        switch state {
        case .stable:
            return "Language stayed close to your usual baseline. Continue your routine and monitor for pattern changes."
        case .watch:
            return "Your note includes moderate stress or disruption language. This may be less stable than your recent baseline."
        case .elevated:
            let tagSnippet = tags.prefix(3).joined(separator: ", ")
            return "Signals such as \(tagSnippet) appeared together. Consider preparing a privacy-safe summary if you want support."
        }
    }
}
