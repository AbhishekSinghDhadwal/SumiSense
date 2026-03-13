import Foundation

struct AnalyzeEntryOutcome {
    let entry: JournalEntry
    let assessment: DailySignalAssessment
    let trendAssessment: TrendAssessment
    let updatedMetrics: [WellnessMetricPoint]
    let journalRuntimeMessage: String?
    let trendRuntimeMessage: String?
}

struct TrendRefreshOutcome {
    let assessment: TrendAssessment
    let runtimeMessage: String?
}

struct ShareGenerationOutcome {
    let result: RedactionResult
    let runtimeMessage: String?
}

struct ModelWarmupOutcome {
    let journalRuntimeMessage: String?
    let trendRuntimeMessage: String?
    let redactionRuntimeMessage: String?
}

final class WellnessInsightCoordinator {
    private var trendPrimaryTimeoutSeconds: TimeInterval {
        resolveTimeout(envKey: "ZETIC_COORDINATOR_TREND_TIMEOUT_SEC", defaultSeconds: 40)
    }
    private var redactionPrimaryTimeoutSeconds: TimeInterval {
        resolveTimeout(envKey: "ZETIC_COORDINATOR_REDACTION_TIMEOUT_SEC", defaultSeconds: 40)
    }

    private let primaryJournalService: JournalInferenceService?
    private let fallbackJournalService: JournalInferenceService

    private let primaryTrendService: TrendInferenceService?
    private let fallbackTrendService: TrendInferenceService

    private let primaryRedactionService: RedactionService?
    private let fallbackRedactionService: RedactionService

    private var journalPrimarySuppressed = false

    init(
        primaryJournalService: JournalInferenceService?,
        fallbackJournalService: JournalInferenceService,
        primaryTrendService: TrendInferenceService?,
        fallbackTrendService: TrendInferenceService,
        primaryRedactionService: RedactionService?,
        fallbackRedactionService: RedactionService
    ) {
        self.primaryJournalService = primaryJournalService
        self.fallbackJournalService = fallbackJournalService
        self.primaryTrendService = primaryTrendService
        self.fallbackTrendService = fallbackTrendService
        self.primaryRedactionService = primaryRedactionService
        self.fallbackRedactionService = fallbackRedactionService
    }

    func analyzeNewEntry(
        rawText: String,
        manualTags: [String],
        existingEntries: [JournalEntry],
        metrics: [WellnessMetricPoint],
        windowDays: Int
    ) async -> AnalyzeEntryOutcome {
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Analyze flow start",
            metadata: [
                "callID": String(callID),
                "noteChars": "\(rawText.count)",
                "manualTags": "\(manualTags.count)",
                "existingEntries": "\(existingEntries.count)",
                "metricPoints": "\(metrics.count)",
                "windowDays": "\(windowDays)"
            ]
        )
        let journalExecution = await runJournalInference(
            note: rawText,
            manualTags: manualTags,
            contextEntries: existingEntries,
            metrics: metrics
        )
        let assessment = journalExecution.value

        let entry = JournalEntry(
            date: Date(),
            rawText: rawText,
            manualTags: manualTags,
            detectedTags: assessment.signalTags,
            generatedSummary: assessment.summary,
            generatedStatus: assessment.status
        )

        let updatedMetrics = mergeTodayMetric(
            generatedFrom: assessment,
            into: metrics
        )

        let trendExecution = await refreshTrendWithDiagnostics(
            metrics: updatedMetrics,
            windowDays: windowDays
        )
        let trend = trendExecution.assessment
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Analyze flow complete",
            metadata: [
                "callID": String(callID),
                "journalSource": assessment.source.rawValue,
                "trendSource": trend.source.rawValue,
                "status": assessment.status.rawValue,
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )

        return AnalyzeEntryOutcome(
            entry: entry,
            assessment: assessment,
            trendAssessment: trend,
            updatedMetrics: updatedMetrics,
            journalRuntimeMessage: journalExecution.runtimeMessage,
            trendRuntimeMessage: trendExecution.runtimeMessage
        )
    }

    func refreshTrend(metrics: [WellnessMetricPoint], windowDays: Int) async -> TrendAssessment {
        await refreshTrendWithDiagnostics(metrics: metrics, windowDays: windowDays, preferPrimary: true).assessment
    }

    func prewarmModels() async -> ModelWarmupOutcome {
        // Warm journal first (largest model), then warm trend + redaction concurrently.
        // This reduces first-analysis latency without loading all heavyweight models at once.
        let journal = await warmUpJournal()
        async let trend = warmUpTrend()
        async let redaction = warmUpRedaction()
        return ModelWarmupOutcome(
            journalRuntimeMessage: journal,
            trendRuntimeMessage: await trend,
            redactionRuntimeMessage: await redaction
        )
    }

    func prewarmJournalOnly() async -> String? {
        await warmUpJournal()
    }

    func refreshTrendWithDiagnostics(
        metrics: [WellnessMetricPoint],
        windowDays: Int,
        preferPrimary: Bool = true
    ) async -> TrendRefreshOutcome {
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Trend refresh requested",
            metadata: [
                "callID": String(callID),
                "metricPoints": "\(metrics.count)",
                "windowDays": "\(windowDays)",
                "hasPrimary": "\(primaryTrendService != nil)",
                "preferPrimary": "\(preferPrimary)"
            ]
        )
        if preferPrimary, let primaryTrendService {
            do {
                let primary = try await runPrimaryWithTimeout(seconds: trendPrimaryTimeoutSeconds) {
                    try await primaryTrendService.analyze(metrics: metrics, windowDays: windowDays)
                }
                SumiInferenceLog.event(
                    service: "Coordinator",
                    action: "Trend refresh used primary",
                    metadata: [
                        "callID": String(callID),
                        "source": primary.source.rawValue,
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                return TrendRefreshOutcome(assessment: primary, runtimeMessage: nil)
            } catch {
                let fallback = (try? await fallbackTrendService.analyze(metrics: metrics, windowDays: windowDays))
                    ?? fallbackTrendPlaceholder(windowDays: windowDays)
                SumiInferenceLog.event(
                    service: "Coordinator",
                    action: "Trend refresh fell back",
                    level: .warning,
                    metadata: [
                        "callID": String(callID),
                        "error": SumiInferenceLog.truncate(error.localizedDescription, limit: 220),
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                return TrendRefreshOutcome(
                    assessment: fallback,
                    runtimeMessage: fallbackRuntimeMessage(service: "Trend", error: error)
                )
            }
        }

        let fallback = (try? await fallbackTrendService.analyze(metrics: metrics, windowDays: windowDays))
            ?? fallbackTrendPlaceholder(windowDays: windowDays)
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Trend refresh used fallback only",
            level: .warning,
            metadata: ["callID": String(callID), "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"]
        )
        return TrendRefreshOutcome(
            assessment: fallback,
            runtimeMessage: preferPrimary ? "Trend fallback active: Melange service unavailable in this runtime." : nil
        )
    }

    func generateShareSafe(mode: ShareMode, from entry: JournalEntry) async -> RedactionResult {
        let source = entry.generatedSummary ?? entry.rawText
        return await generateShareSafeWithDiagnostics(mode: mode, sourceText: source).result
    }

    func generateShareSafeWithDiagnostics(mode: ShareMode, from entry: JournalEntry) async -> ShareGenerationOutcome {
        let source = entry.generatedSummary ?? entry.rawText
        return await generateShareSafeWithDiagnostics(mode: mode, sourceText: source)
    }

    func generateShareSafeWithDiagnostics(mode: ShareMode, sourceText: String) async -> ShareGenerationOutcome {
        let source = sourceText
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Share generation requested",
            metadata: [
                "callID": String(callID),
                "mode": mode.rawValue,
                "inputChars": "\(source.count)",
                "hasPrimary": "\(primaryRedactionService != nil)"
            ]
        )

        if let primaryRedactionService {
            do {
                let primary = try await runPrimaryWithTimeout(seconds: redactionPrimaryTimeoutSeconds) {
                    try await primaryRedactionService.redact(text: source, mode: mode)
                }
                SumiInferenceLog.event(
                    service: "Coordinator",
                    action: "Share generation used primary",
                    metadata: [
                        "callID": String(callID),
                        "source": primary.source.rawValue,
                        "outputChars": "\(primary.outputText.count)",
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                return ShareGenerationOutcome(result: primary, runtimeMessage: nil)
            } catch {
                let fallback = (try? await fallbackRedactionService.redact(text: source, mode: mode))
                    ?? fallbackRedactionPlaceholder(source: source, mode: mode)
                SumiInferenceLog.event(
                    service: "Coordinator",
                    action: "Share generation fell back",
                    level: .warning,
                    metadata: [
                        "callID": String(callID),
                        "error": SumiInferenceLog.truncate(error.localizedDescription, limit: 220),
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                return ShareGenerationOutcome(
                    result: fallback,
                    runtimeMessage: fallbackRuntimeMessage(service: "Redaction", error: error)
                )
            }
        }

        let fallback = (try? await fallbackRedactionService.redact(text: source, mode: mode))
            ?? fallbackRedactionPlaceholder(source: source, mode: mode)
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Share generation used fallback only",
            level: .warning,
            metadata: ["callID": String(callID), "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"]
        )
        return ShareGenerationOutcome(
            result: fallback,
            runtimeMessage: "Redaction fallback active: Melange service unavailable in this runtime."
        )
    }

    private func runJournalInference(
        note: String,
        manualTags: [String],
        contextEntries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) async -> InferenceExecution<DailySignalAssessment> {
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Journal inference requested",
            metadata: [
                "callID": String(callID),
                "noteChars": "\(note.count)",
                "hasPrimary": "\(primaryJournalService != nil)",
                "primarySuppressed": "\(journalPrimarySuppressed)"
            ]
        )
        if let primaryJournalService, !journalPrimarySuppressed {
            do {
                // Journal service already has its own timeout strategy (cold/warm paths).
                // Avoid a second coordinator-level timeout that can fire early and cause
                // contradictory UX (fallback shown while journal task still finishes in background).
                let primary = try await primaryJournalService.analyze(
                    note: note,
                    manualTags: manualTags,
                    contextEntries: contextEntries,
                    metrics: metrics
                )
                SumiInferenceLog.event(
                    service: "Coordinator",
                    action: "Journal inference used primary",
                    metadata: [
                        "callID": String(callID),
                        "source": primary.source.rawValue,
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                return InferenceExecution(value: primary, runtimeMessage: nil)
            } catch {
                if shouldSuppressPrimaryAfterFailure(error) {
                    journalPrimarySuppressed = true
                }
                let fallback = (try? await fallbackJournalService.analyze(
                    note: note,
                    manualTags: manualTags,
                    contextEntries: contextEntries,
                    metrics: metrics
                )) ?? fallbackJournalPlaceholder()
                SumiInferenceLog.event(
                    service: "Coordinator",
                    action: "Journal inference fell back",
                    level: .warning,
                    metadata: [
                        "callID": String(callID),
                        "error": SumiInferenceLog.truncate(error.localizedDescription, limit: 220),
                        "suppressedNow": "\(journalPrimarySuppressed)",
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                return InferenceExecution(
                    value: fallback,
                    runtimeMessage: fallbackRuntimeMessage(service: "Journal", error: error)
                )
            }
        }

        let fallback = (try? await fallbackJournalService.analyze(
            note: note,
            manualTags: manualTags,
            contextEntries: contextEntries,
            metrics: metrics
        )) ?? fallbackJournalPlaceholder()
        SumiInferenceLog.event(
            service: "Coordinator",
            action: "Journal inference used fallback only",
            level: .warning,
            metadata: [
                "callID": String(callID),
                "suppressed": "\(journalPrimarySuppressed)",
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )
        return InferenceExecution(
            value: fallback,
            runtimeMessage: journalPrimarySuppressed
                ? "Journal fallback active: Melange journal model was disabled for this run after timeout or access failure."
                : "Journal fallback active: Melange service unavailable in this runtime."
        )
    }

    private func mergeTodayMetric(
        generatedFrom assessment: DailySignalAssessment,
        into metrics: [WellnessMetricPoint]
    ) -> [WellnessMetricPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var copied = metrics
        let baseline = metrics.last ?? WellnessMetricPoint(
            date: today,
            sleepHours: 7.0,
            moodScore: 6.0,
            stressScore: 4.0,
            cravingScore: 2.0,
            energyScore: 5.8,
            steps: 6300,
            restingHeartRate: 69
        )

        let adjusted = adjustedMetric(from: baseline, status: assessment.status)

        if let index = copied.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            copied[index] = adjusted
        } else {
            copied.append(adjusted)
        }

        return copied.sorted { $0.date < $1.date }
    }

    private func adjustedMetric(from baseline: WellnessMetricPoint, status: SignalState) -> WellnessMetricPoint {
        let today = Calendar.current.startOfDay(for: Date())

        switch status {
        case .stable:
            return WellnessMetricPoint(
                date: today,
                sleepHours: max(5.8, baseline.sleepHours - 0.1),
                moodScore: min(8.5, baseline.moodScore + 0.2),
                stressScore: max(1.8, baseline.stressScore - 0.25),
                cravingScore: max(0.5, baseline.cravingScore - 0.2),
                energyScore: min(8.2, baseline.energyScore + 0.2),
                steps: baseline.steps,
                restingHeartRate: baseline.restingHeartRate
            )
        case .watch:
            return WellnessMetricPoint(
                date: today,
                sleepHours: max(4.8, baseline.sleepHours - 0.6),
                moodScore: max(2.0, baseline.moodScore - 0.5),
                stressScore: min(9.4, baseline.stressScore + 0.7),
                cravingScore: min(8.2, baseline.cravingScore + 0.4),
                energyScore: max(1.5, baseline.energyScore - 0.45),
                steps: baseline.steps,
                restingHeartRate: baseline.restingHeartRate.map { min(95, $0 + 1.8) }
            )
        case .elevated:
            return WellnessMetricPoint(
                date: today,
                sleepHours: max(3.8, baseline.sleepHours - 1.0),
                moodScore: max(1.2, baseline.moodScore - 0.9),
                stressScore: min(9.8, baseline.stressScore + 1.0),
                cravingScore: min(9.6, baseline.cravingScore + 0.8),
                energyScore: max(1.0, baseline.energyScore - 0.8),
                steps: baseline.steps,
                restingHeartRate: baseline.restingHeartRate.map { min(105, $0 + 2.6) }
            )
        }
    }

    private func fallbackJournalPlaceholder() -> DailySignalAssessment {
        DailySignalAssessment(
            date: Date(),
            status: .watch,
            summary: "Your note suggests a mild stability shift.",
            explanation: "Fallback interpretation was used to keep analysis local and immediate.",
            signalTags: ["pattern change"],
            confidence: 0.5,
            source: .fallback
        )
    }

    private func fallbackTrendPlaceholder(windowDays: Int) -> TrendAssessment {
        TrendAssessment(
            windowDays: windowDays,
            stabilityScore: 0.58,
            trendDirection: .mixed,
            plainLanguageSummary: "Trend service was unavailable, so a local baseline comparison summary is shown.",
            metricHighlights: ["Fallback trend active"],
            baselineAverage: 0,
            recentAverage: 0,
            confidence: 0.45,
            source: .fallback
        )
    }

    private func fallbackRedactionPlaceholder(source: String, mode: ShareMode) -> RedactionResult {
        RedactionResult(
            mode: mode,
            sourceText: source,
            outputText: source,
            redactionsApplied: ["fallback"],
            source: .fallback
        )
    }

    private func fallbackRuntimeMessage(service: String, error: Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowerDetail = detail.lowercased()
        if lowerDetail.contains("403") || lowerDetail.contains("permission denied") {
            let message = "\(service) fallback active: Melange returned 403 (model access denied). Verify model ID/version access for this key in Melange dashboard."
            SumiInferenceLog.event(service: "Coordinator", action: message, level: .warning)
            return message
        }
        if lowerDetail.contains("timed out") {
            let message = "\(service) fallback active: on-device model call timed out. The model may still be downloading or initializing."
            SumiInferenceLog.event(service: "Coordinator", action: message, level: .warning)
            return message
        }
        let message = "\(service) fallback active: \(detail)"
        SumiInferenceLog.event(service: "Coordinator", action: message, level: .warning)
        return message
    }

    private func warmUpJournal() async -> String? {
        guard let primaryJournalService else { return nil }
        do {
            try await primaryJournalService.warmUp()
            return nil
        } catch {
            if shouldSuppressPrimaryAfterFailure(error) {
                journalPrimarySuppressed = true
            }
            return fallbackRuntimeMessage(service: "Journal", error: error)
        }
    }

    private func warmUpTrend() async -> String? {
        guard let primaryTrendService else { return nil }
        do {
            try await primaryTrendService.warmUp()
            return nil
        } catch {
            return fallbackRuntimeMessage(service: "Trend", error: error)
        }
    }

    private func warmUpRedaction() async -> String? {
        guard let primaryRedactionService else { return nil }
        do {
            try await primaryRedactionService.warmUp()
            return nil
        } catch {
            return fallbackRuntimeMessage(service: "Redaction", error: error)
        }
    }

    private func runPrimaryWithTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                let nanos = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw MelangeRuntimeError.inferenceTimeout
            }

            guard let firstCompleted = try await group.next() else {
                throw MelangeRuntimeError.inferenceTimeout
            }
            group.cancelAll()
            return firstCompleted
        }
    }

    private func shouldSuppressPrimaryAfterFailure(_ error: Error) -> Bool {
        let detail = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        return detail.contains("timed out")
            || detail.contains("403")
            || detail.contains("permission denied")
            || detail.contains("access failed")
            || detail.contains("unsupported runtime")
            || detail.contains("below recommended")
            || detail.contains("journal model skipped")
    }

    private func resolveTimeout(envKey: String, defaultSeconds: TimeInterval) -> TimeInterval {
        let raw = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let value = Double(raw), value > 1 else {
            return defaultSeconds
        }
        return value
    }
}

private struct InferenceExecution<T> {
    let value: T
    let runtimeMessage: String?
}
