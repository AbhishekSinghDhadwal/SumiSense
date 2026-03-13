import Foundation

struct SeedDataBundle {
    let profile: UserPreferences
    let entries: [JournalEntry]
    let metrics: [WellnessMetricPoint]
    let shareExamples: [ShareExample]
}

enum SeedDataError: Error {
    case missingFile(String)
    case decodeFailure(String)
}

final class SeedDataLoader {
    private let decoder = JSONDecoder()

    init() {}

    func loadSeedData() throws -> SeedDataBundle {
        let profile = try loadProfile()
        let timelineAligned = alignSeedTimeline(entries: try loadEntries(), metrics: try loadMetrics())
        let entries = timelineAligned.entries
        let metrics = timelineAligned.metrics
        let shareExamples = try loadShareExamples()

        return SeedDataBundle(
            profile: profile,
            entries: entries.sorted { $0.date < $1.date },
            metrics: metrics.sorted { $0.date < $1.date },
            shareExamples: shareExamples
        )
    }

    private func alignSeedTimeline(
        entries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) -> (entries: [JournalEntry], metrics: [WellnessMetricPoint]) {
        let calendar = Calendar.current
        let latestEntryDate = entries.map(\.date).max()
        let latestMetricDate = metrics.map(\.date).max()
        let latestSeedDate = max(latestEntryDate ?? .distantPast, latestMetricDate ?? .distantPast)

        guard latestSeedDate > .distantPast else {
            return (entries, metrics)
        }

        let sourceLatestDay = calendar.startOfDay(for: latestSeedDate)
        let targetLatestDay = calendar.startOfDay(for: Date())
        let dayOffset = calendar.dateComponents([.day], from: sourceLatestDay, to: targetLatestDay).day ?? 0

        guard dayOffset != 0 else { return (entries, metrics) }

        let shiftedEntries = entries.map { entry in
            JournalEntry(
                id: entry.id,
                date: calendar.date(byAdding: .day, value: dayOffset, to: entry.date) ?? entry.date,
                rawText: entry.rawText,
                manualTags: entry.manualTags,
                detectedTags: entry.detectedTags,
                generatedSummary: entry.generatedSummary,
                generatedStatus: entry.generatedStatus,
                moodScore: entry.moodScore,
                stressScore: entry.stressScore,
                cravingScore: entry.cravingScore
            )
        }

        let shiftedMetrics = metrics.map { point in
            WellnessMetricPoint(
                id: point.id,
                date: calendar.date(byAdding: .day, value: dayOffset, to: point.date) ?? point.date,
                sleepHours: point.sleepHours,
                moodScore: point.moodScore,
                stressScore: point.stressScore,
                cravingScore: point.cravingScore,
                energyScore: point.energyScore,
                steps: point.steps,
                restingHeartRate: point.restingHeartRate
            )
        }

        return (shiftedEntries, shiftedMetrics)
    }

    private func loadProfile() throws -> UserPreferences {
        let raw: SeedProfile = try loadJSON(named: "demo_profile")
        return UserPreferences(
            id: UUID(),
            displayName: raw.displayName,
            baselineSensitivity: raw.baselineSensitivity,
            preferredTrendWindow: 14,
            demoModeEnabled: raw.demoModeEnabled
        )
    }

    private func loadEntries() throws -> [JournalEntry] {
        let raw: [SeedJournalEntry] = try loadJSON(named: "journal_entries")
        return raw.map { item in
            JournalEntry(
                id: UUID(uuidString: item.id) ?? UUID(),
                date: SumiDate.parseSeedDate(item.date),
                rawText: item.rawText,
                manualTags: item.manualTags
            )
        }
    }

    private func loadMetrics() throws -> [WellnessMetricPoint] {
        let raw: [SeedMetricPoint] = try loadJSON(named: "daily_metrics")
        return raw.map { item in
            WellnessMetricPoint(
                date: SumiDate.parseSeedDate(item.date),
                sleepHours: item.sleepHours,
                moodScore: item.moodScore,
                stressScore: item.stressScore,
                cravingScore: item.cravingScore,
                energyScore: item.energyScore,
                steps: item.steps,
                restingHeartRate: item.restingHeartRate
            )
        }
    }

    private func loadShareExamples() throws -> [ShareExample] {
        try loadJSON(named: "share_examples")
    }

    private func loadJSON<T: Decodable>(named name: String) throws -> T {
        let bundle = Bundle.main
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Resources/SeedData")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "SeedData")

        guard let url else {
            throw SeedDataError.missingFile(name)
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SeedDataError.decodeFailure("\(name): \(error.localizedDescription)")
        }
    }
}
