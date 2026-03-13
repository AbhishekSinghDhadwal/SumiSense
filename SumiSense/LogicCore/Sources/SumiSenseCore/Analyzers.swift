import Foundation

public enum RuleBasedAnalyzer {
    public static func assess(_ note: String) -> (SignalState, [String]) {
        let normalized = note.lowercased()

        var score = 0.0
        var tags: [String] = []

        if normalized.contains("barely slept") || normalized.contains("didn't sleep") {
            score += 1.2
            tags.append("sleep disruption")
        }
        if normalized.contains("anxious") || normalized.contains("overwhelmed") {
            score += 1.0
            tags.append("high stress")
        }
        if normalized.contains("thought about using") || normalized.contains("craving") {
            score += 1.5
            tags.append("craving language")
        }
        if normalized.contains("reached out") || normalized.contains("asked for help") {
            score -= 0.7
            tags.append("support seeking")
        }

        let state: SignalState
        if score >= 2.3 {
            state = .elevated
        } else if score >= 1.0 {
            state = .watch
        } else {
            state = .stable
        }

        return (state, tags)
    }
}

public enum TrendHeuristicAnalyzer {
    public static func analyze(metrics: [WellnessMetricPoint], windowDays: Int) -> TrendResult {
        let sorted = metrics.sorted { $0.date < $1.date }
        guard sorted.count >= 6 else {
            return TrendResult(direction: .stable, summary: "Need more data")
        }

        let window = min(windowDays, sorted.count)
        let recent = Array(sorted.suffix(window))
        let baseline = Array(sorted.prefix(max(1, sorted.count - window)))

        let recentScore = recent.map(instability).average
        let baselineScore = baseline.map(instability).average
        let delta = recentScore - baselineScore

        let direction: TrendDirection
        if delta > 0.6 {
            direction = .worsening
        } else if delta < -0.3 {
            direction = .improving
        } else if abs(delta) > 0.2 {
            direction = .mixed
        } else {
            direction = .stable
        }

        return TrendResult(
            direction: direction,
            summary: "delta=\(String(format: "%.2f", delta))"
        )
    }

    private static func instability(_ point: WellnessMetricPoint) -> Double {
        let sleepPenalty = max(0, 7.5 - point.sleepHours) * 1.05
        let moodPenalty = max(0, 6.5 - point.moodScore) * 0.8
        let stressPenalty = point.stressScore * 0.95
        let cravingPenalty = point.cravingScore * 1.15
        let energyPenalty = max(0, 6.3 - point.energyScore) * 0.65
        return (sleepPenalty + moodPenalty + stressPenalty + cravingPenalty + energyPenalty) / 4.6
    }
}

public enum RegexRedactor {
    public static func redact(_ text: String, mode: ShareMode) -> RedactionOutput {
        var output = text
        var tags: [String] = []

        output = replace(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", in: output, replacement: "[Email]", tags: &tags, tag: "email")
        output = replace(pattern: "(?<!\\d)(?:\\+1[-.\\s]?)?(?:\\(?\\d{3}\\)?[-.\\s]?)\\d{3}[-.\\s]?\\d{4}(?!\\d)", in: output, replacement: "[Phone]", tags: &tags, tag: "phone")

        if mode != .personal {
            output = replace(pattern: "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b", in: output, replacement: "[Date]", tags: &tags, tag: "date")
        }

        if mode == .researchSafe {
            output = replace(pattern: "\\b(?:Maya|Alex|Tempe|Phoenix)\\b", in: output, replacement: "[Sensitive]", tags: &tags, tag: "identity")
        }

        return RedactionOutput(transformed: output, tags: Array(Set(tags)))
    }

    private static func replace(
        pattern: String,
        in text: String,
        replacement: String,
        tags: inout [String],
        tag: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard !regex.matches(in: text, options: [], range: range).isEmpty else { return text }

        tags.append(tag)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

private extension Collection where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
