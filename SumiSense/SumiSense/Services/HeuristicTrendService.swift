import Foundation

final class HeuristicTrendService: TrendInferenceService {
    func analyze(metrics: [WellnessMetricPoint], windowDays: Int) async throws -> TrendAssessment {
        let sorted = metrics.sorted { $0.date < $1.date }
        guard sorted.count >= 6 else {
            return TrendAssessment(
                windowDays: windowDays,
                stabilityScore: 0.62,
                trendDirection: .stable,
                plainLanguageSummary: "Not enough history yet. Keep journaling to improve trend clarity.",
                metricHighlights: ["Need at least 6 days of data"],
                baselineAverage: 0,
                recentAverage: 0,
                confidence: 0.3,
                source: .fallback
            )
        }

        let effectiveWindow = min(windowDays, sorted.count)
        let recent = Array(sorted.suffix(effectiveWindow))
        let baseline = Array(sorted.prefix(max(1, sorted.count - effectiveWindow)))

        let recentStability = recent.map(instabilityScore).average
        let baselineStability = baseline.map(instabilityScore).average
        let delta = recentStability - baselineStability

        let stabilityScore = max(0, min(1, 1 - recentStability / 10))
        let direction: TrendDirection
        if delta > 0.6 {
            direction = .worsening
        } else if delta > 0.2 {
            direction = .mixed
        } else if delta < -0.3 {
            direction = .improving
        } else {
            direction = .stable
        }

        let sleepDelta = recent.map(\.sleepHours).average - baseline.map(\.sleepHours).average
        let stressDelta = recent.map(\.stressScore).average - baseline.map(\.stressScore).average
        let cravingDelta = recent.map(\.cravingScore).average - baseline.map(\.cravingScore).average

        var highlights: [String] = []
        if sleepDelta < -0.4 { highlights.append("Sleep dipped below baseline") }
        if stressDelta > 0.5 { highlights.append("Stress language increased") }
        if cravingDelta > 0.4 { highlights.append("Craving score trended upward") }
        if highlights.isEmpty { highlights.append("Signals are near baseline") }

        let summary: String
        switch direction {
        case .worsening:
            summary = "Your last \(effectiveWindow) days look less stable than baseline, with lower sleep and higher stress signals."
        case .mixed:
            summary = "Recent signals are mixed. Some patterns improved, but routine stability remains uneven."
        case .improving:
            summary = "Your recent pattern looks steadier than earlier days, with softer stress and craving signals."
        case .stable:
            summary = "Recent patterns are close to your baseline without a strong stability shift."
        }

        return TrendAssessment(
            windowDays: effectiveWindow,
            stabilityScore: stabilityScore,
            trendDirection: direction,
            plainLanguageSummary: summary,
            metricHighlights: highlights,
            baselineAverage: baselineStability,
            recentAverage: recentStability,
            confidence: 0.68,
            source: .fallback
        )
    }

    private func instabilityScore(for point: WellnessMetricPoint) -> Double {
        let sleepPenalty = max(0, 7.5 - point.sleepHours) * 1.05
        let moodPenalty = max(0, 6.5 - point.moodScore) * 0.8
        let stressPenalty = point.stressScore * 0.95
        let cravingPenalty = point.cravingScore * 1.15
        let energyPenalty = max(0, 6.3 - point.energyScore) * 0.65

        return (sleepPenalty + moodPenalty + stressPenalty + cravingPenalty + energyPenalty) / 4.6
    }
}
