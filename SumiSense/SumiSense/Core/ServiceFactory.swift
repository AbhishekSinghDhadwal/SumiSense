import Foundation

struct ServiceFactory {
    let config: MelangeConfig

    static func liveReady(config: MelangeConfig = .default) -> ServiceFactory {
        ServiceFactory(config: config)
    }

    func makeCoordinator(journalMelangeEnabledOverride: Bool? = nil) -> WellnessInsightCoordinator {
        let fallbackJournal = RuleBasedJournalService()
        let fallbackTrend = HeuristicTrendService()
        let fallbackRedaction = RegexRedactionService()

        let useMelangePrimary = MelangeAvailability.sdkAvailable && config.hasPersonalKey
        let enableJournalMelange = shouldEnableJournalMelange(
            useMelangePrimary: useMelangePrimary,
            override: journalMelangeEnabledOverride
        )
        let primaryJournal: JournalInferenceService? = (useMelangePrimary && enableJournalMelange)
            ? MelangeMedgemmaJournalService(config: config)
            : nil
        let primaryTrend: TrendInferenceService? = useMelangePrimary ? MelangeChronosTrendService(config: config) : nil
        let primaryRedaction: RedactionService? = useMelangePrimary ? MelangeAnonymizerRedactionService(config: config) : nil

        SumiInferenceLog.event(
            service: "Factory",
            action: "Service wiring complete",
            metadata: [
                "melangeSDK": "\(MelangeAvailability.sdkAvailable)",
                "hasKey": "\(config.hasPersonalKey)",
                "journalPrimary": "\(primaryJournal != nil)",
                "trendPrimary": "\(primaryTrend != nil)",
                "redactionPrimary": "\(primaryRedaction != nil)"
            ]
        )

        return WellnessInsightCoordinator(
            primaryJournalService: primaryJournal,
            fallbackJournalService: fallbackJournal,
            primaryTrendService: primaryTrend,
            fallbackTrendService: fallbackTrend,
            primaryRedactionService: primaryRedaction,
            fallbackRedactionService: fallbackRedaction
        )
    }

    func defaultJournalMelangeEnabled() -> Bool {
        let useMelangePrimary = MelangeAvailability.sdkAvailable && config.hasPersonalKey
        return shouldEnableJournalMelange(useMelangePrimary: useMelangePrimary, override: nil)
    }

    private func shouldEnableJournalMelange(useMelangePrimary: Bool, override: Bool?) -> Bool {
        guard useMelangePrimary else { return false }
        if let override {
            return override
        }
        let env = ProcessInfo.processInfo.environment
        let raw = env["ZETIC_ENABLE_JOURNAL_MELANGE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if raw.isEmpty {
            // Disabled by default because Medgemma constructor has shown runtime EXC_BAD_ACCESS
            // on some devices; enable explicitly once verified on target hardware.
            return false
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }
}
