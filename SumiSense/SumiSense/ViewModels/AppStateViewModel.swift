import Foundation
import Combine
import SwiftUI

@MainActor
final class AppStateViewModel: ObservableObject {
    @Published var userPreferences: UserPreferences = .default
    @Published var demoState: DemoState = .default

    @Published var journalEntries: [JournalEntry] = []
    @Published var metrics: [WellnessMetricPoint] = []
    @Published var shareExamples: [ShareExample] = []

    @Published var latestAssessment: DailySignalAssessment?
    @Published var latestTrendAssessment: TrendAssessment?
    @Published var latestRedactionResult: RedactionResult?

    @Published var noteDraft: String = ""
    @Published var selectedTrendWindow: Int = 14
    @Published var selectedMetric: WellnessMetricType = .sleepHours
    @Published var selectedShareMode: ShareMode = .personal
    @Published var selectedShareSource: ShareSourceSelection = .selectedEntry
    @Published var selectedShareEntryID: UUID?

    @Published var isAnalyzing = false
    @Published var isRefreshingTrend = false
    @Published var isGeneratingShare = false
    @Published var isShareLongRunning = false
    @Published var isPrewarmingModels = false
    @Published var lastErrorMessage: String?

    @Published var lastJournalSource: InferenceSource = .fallback
    @Published var lastTrendSource: InferenceSource = .fallback
    @Published var lastRedactionSource: InferenceSource = .fallback
    @Published var journalRuntimeMessage: String?
    @Published var trendRuntimeMessage: String?
    @Published var redactionRuntimeMessage: String?
    @Published var journalMelangeEnabled = false
    @Published var isSwitchingJournalMelange = false
    @Published var isJournalModelReady = false
    @Published var isTrendModelReady = false
    @Published var isRedactionModelReady = false
    @Published var isRefreshingInferenceStatus = false

    let melangeConfig: MelangeConfig
    private let seedLoader: SeedDataLoader
    private let localStateStore: LocalAppStateStore
    private let serviceFactory: ServiceFactory
    private var coordinator: WellnessInsightCoordinator
    private var shareWatchdogTask: Task<Void, Never>?
    private var warmupTaskGeneration = UUID()
    private let journalMelangePreferenceKey = "sumisense.journalMelangeEnabled"

    init(
        seedLoader: SeedDataLoader? = nil,
        serviceFactory: ServiceFactory? = nil,
        localStateStore: LocalAppStateStore? = nil
    ) {
        let resolvedSeedLoader = seedLoader ?? SeedDataLoader()
        let resolvedFactory = serviceFactory ?? .liveReady()
        let resolvedLocalStore = localStateStore ?? LocalAppStateStore()

        self.seedLoader = resolvedSeedLoader
        self.localStateStore = resolvedLocalStore
        self.serviceFactory = resolvedFactory
        self.melangeConfig = resolvedFactory.config
        let initialJournalEnabled: Bool
        if let persisted = UserDefaults.standard.object(forKey: journalMelangePreferenceKey) as? Bool {
            initialJournalEnabled = persisted
        } else {
            initialJournalEnabled = resolvedFactory.defaultJournalMelangeEnabled()
        }
        self.journalMelangeEnabled = initialJournalEnabled
        self.coordinator = resolvedFactory.makeCoordinator(
            journalMelangeEnabledOverride: initialJournalEnabled
        )

        loadInitialData()
    }

    var latestEntry: JournalEntry? {
        journalEntries.sorted { $0.date > $1.date }.first
    }

    var selectedShareEntry: JournalEntry? {
        if let selectedShareEntryID,
           let selected = journalEntries.first(where: { $0.id == selectedShareEntryID }) {
            return selected
        }
        return latestEntry
    }

    var sevenDayEntries: [JournalEntry] {
        let sorted = journalEntries.sorted { $0.date < $1.date }
        guard let anchor = sorted.last?.date else { return [] }
        let calendar = Calendar.current
        let anchorDay = calendar.startOfDay(for: anchor)
        let start = calendar.date(byAdding: .day, value: -6, to: anchorDay) ?? anchorDay
        return sorted.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= anchorDay
        }
    }

    var sevenDayMetrics: [WellnessMetricPoint] {
        let sorted = metrics.sorted { $0.date < $1.date }
        guard let anchor = sorted.last?.date else { return [] }
        let calendar = Calendar.current
        let anchorDay = calendar.startOfDay(for: anchor)
        let start = calendar.date(byAdding: .day, value: -6, to: anchorDay) ?? anchorDay
        return sorted.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= anchorDay
        }
    }

    var shareSourcePreviewText: String {
        buildSharePayload()?.sourcePreviewText ?? ""
    }

    var modelReadinessText: String {
        #if targetEnvironment(simulator)
        return "This run is on iOS Simulator. Live Melange execution depends on simulator framework support; fallback may activate automatically."
        #else
        if !MelangeAvailability.sdkAvailable {
            return "Melange SDK unavailable in this build. Fallback services are active."
        }
        if !melangeConfig.hasPersonalKey {
            return "Set ZETIC_PERSONAL_KEY (or ZETIC_ACCESS_TOKEN) in the Run scheme. Current key source: \(melangeConfig.personalKeySource)."
        }
        let journalStatus = journalMelangeEnabled
            ? "Journal live model is enabled."
            : "Journal live model is disabled by default for stability; enable it from About."
        return "Melange configured from \(melangeConfig.personalKeySource). \(journalStatus) Live model calls run first, then deterministic fallback is used only on errors."
        #endif
    }

    func analyzeDraft(manualTags: [String]) {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastErrorMessage = "Please enter a short note before analysis."
            return
        }

        isAnalyzing = true
        lastErrorMessage = nil
        journalRuntimeMessage = "Journal analysis started on-device. First run can take longer while model files initialize."

        Task {
            let outcome = await coordinator.analyzeNewEntry(
                rawText: trimmed,
                manualTags: manualTags,
                existingEntries: journalEntries,
                metrics: metrics,
                windowDays: selectedTrendWindow
            )
            let safeAssessment = UserFacingTextSanitizer.sanitizeAssessment(outcome.assessment)
            var safeEntry = outcome.entry
            safeEntry.generatedSummary = safeAssessment.summary

            withAnimation(SumiMotion.spring) {
                journalEntries.append(safeEntry)
                journalEntries.sort { $0.date < $1.date }
                metrics = outcome.updatedMetrics

                latestAssessment = safeAssessment
                latestTrendAssessment = outcome.trendAssessment
                selectedShareEntryID = safeEntry.id

                lastJournalSource = safeAssessment.source
                isJournalModelReady = safeAssessment.source == .melange
                lastTrendSource = outcome.trendAssessment.source
                isTrendModelReady = outcome.trendAssessment.source == .melange
                journalRuntimeMessage = outcome.journalRuntimeMessage
                    ?? (safeAssessment.source == .melange ? "On-device journal model active (Melange)." : nil)
                trendRuntimeMessage = outcome.trendRuntimeMessage
                    ?? (outcome.trendAssessment.source == .melange ? "Chronos trend model active (Melange)." : nil)

                noteDraft = ""
                isAnalyzing = false
            }
            persistLocalState()
        }
    }

    func refreshTrend() {
        isRefreshingTrend = true

        Task {
            let result = await coordinator.refreshTrendWithDiagnostics(metrics: metrics, windowDays: selectedTrendWindow)
            withAnimation(SumiMotion.gentleSpring) {
                latestTrendAssessment = result.assessment
                lastTrendSource = result.assessment.source
                isTrendModelReady = result.assessment.source == .melange
                trendRuntimeMessage = result.runtimeMessage
                    ?? (result.assessment.source == .melange ? "Chronos trend model active (Melange)." : nil)
                isRefreshingTrend = false
            }
        }
    }

    func generateShareOutput() {
        guard let payload = buildSharePayload() else {
            lastErrorMessage = selectedShareSource == .selectedEntry
                ? "Pick a note before generating a share-safe summary."
                : "Need at least one recent entry for a 7-day export."
            return
        }
        SumiInferenceLog.event(
            service: "Share",
            action: "Generate tapped",
            metadata: [
                "mode": selectedShareMode.rawValue,
                "source": selectedShareSource.rawValue,
                "redactionInputChars": "\(payload.redactionInputText.count)",
                "previewChars": "\(payload.sourcePreviewText.count)",
                "hasMetricsContext": "\(payload.metricsContextText != nil)"
            ]
        )

        isGeneratingShare = true
        isShareLongRunning = false
        lastErrorMessage = nil
        redactionRuntimeMessage = "Starting on-device redaction..."

        shareWatchdogTask?.cancel()
        shareWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isGeneratingShare else { return }
                self.isShareLongRunning = true
                self.redactionRuntimeMessage = "Redaction still running on-device. Initial compilation or model warmup may take up to a minute."
            }
        }

        Task {
            let result = await coordinator.generateShareSafeWithDiagnostics(
                mode: selectedShareMode,
                sourceText: payload.redactionInputText
            )
            let merged = mergeShareResult(result.result, payload: payload)
            let baseRuntimeMessage = result.runtimeMessage
                ?? (merged.source == .melange ? "On-device redaction model active." : nil)
            let metricsNote = payload.metricsContextText == nil
                ? nil
                : "Metrics context is appended locally (not sent through the redaction model) to keep exports responsive."
            withAnimation(SumiMotion.spring) {
                latestRedactionResult = merged
                lastRedactionSource = merged.source
                isRedactionModelReady = merged.source == .melange
                if let baseRuntimeMessage, let metricsNote {
                    redactionRuntimeMessage = "\(baseRuntimeMessage) \(metricsNote)"
                } else {
                    redactionRuntimeMessage = baseRuntimeMessage ?? metricsNote
                }
                isGeneratingShare = false
                isShareLongRunning = false
            }
            shareWatchdogTask?.cancel()
            shareWatchdogTask = nil
        }
    }

    func resetToSeedData() {
        do {
            try localStateStore.clear()
        } catch {
            lastErrorMessage = "Could not clear local data: \(error.localizedDescription)"
        }
        loadInitialData()
    }

    func setJournalMelangeEnabled(_ enabled: Bool) {
        guard MelangeAvailability.sdkAvailable, melangeConfig.hasPersonalKey else {
            journalMelangeEnabled = false
            UserDefaults.standard.set(false, forKey: journalMelangePreferenceKey)
            journalRuntimeMessage = "Journal live model requires Melange SDK and valid credentials."
            return
        }
        guard journalMelangeEnabled != enabled else { return }

        journalMelangeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: journalMelangePreferenceKey)
        isSwitchingJournalMelange = true
        isJournalModelReady = false
        let generation = UUID()
        warmupTaskGeneration = generation
        journalRuntimeMessage = enabled
            ? "Activating Journal Melange model..."
            : "Journal live model disabled. Rule-based local fallback active."
        rebuildCoordinatorForCurrentToggle()

        Task {
            if enabled {
                let journalWarmMessage = await coordinator.prewarmJournalOnly()
                await MainActor.run {
                    guard self.warmupTaskGeneration == generation else { return }
                    self.journalRuntimeMessage = journalWarmMessage
                        ?? "Journal live model activation finished. Analyze a new note to verify output."
                    if journalWarmMessage == nil {
                        self.lastJournalSource = .melange
                        self.isJournalModelReady = true
                    }
                    self.isSwitchingJournalMelange = false
                }
            } else {
                await MainActor.run {
                    guard self.warmupTaskGeneration == generation else { return }
                    self.lastJournalSource = .fallback
                    self.isJournalModelReady = false
                    self.isSwitchingJournalMelange = false
                }
            }
        }
    }

    func refreshInferenceStatus() {
        guard MelangeAvailability.sdkAvailable, melangeConfig.hasPersonalKey else {
            journalRuntimeMessage = "Status refresh unavailable: Melange SDK or credentials missing."
            trendRuntimeMessage = "Status refresh unavailable: Melange SDK or credentials missing."
            redactionRuntimeMessage = "Status refresh unavailable: Melange SDK or credentials missing."
            isJournalModelReady = false
            isTrendModelReady = false
            isRedactionModelReady = false
            return
        }
        guard !isRefreshingInferenceStatus else { return }

        isRefreshingInferenceStatus = true
        let generation = UUID()
        warmupTaskGeneration = generation

        if journalMelangeEnabled {
            if !isJournalModelReady {
                journalRuntimeMessage = "Journal model initializing..."
            } else {
                journalRuntimeMessage = "Re-checking Journal model readiness..."
            }
        } else {
            journalRuntimeMessage = "Journal live model is disabled."
            isJournalModelReady = false
        }
        trendRuntimeMessage = isTrendModelReady
            ? "Re-checking Chronos model readiness..."
            : "Chronos model initializing..."
        redactionRuntimeMessage = isRedactionModelReady
            ? "Re-checking redaction model readiness..."
            : "Redaction model initializing..."

        Task {
            let warmup = await coordinator.prewarmModels()
            await MainActor.run {
                guard self.warmupTaskGeneration == generation else { return }

                if self.journalMelangeEnabled {
                    self.journalRuntimeMessage = warmup.journalRuntimeMessage
                        ?? "Journal model is warm and ready."
                    self.isJournalModelReady = warmup.journalRuntimeMessage == nil
                    if warmup.journalRuntimeMessage == nil {
                        self.lastJournalSource = .melange
                    }
                } else {
                    self.isJournalModelReady = false
                }

                self.trendRuntimeMessage = warmup.trendRuntimeMessage
                    ?? "Chronos model is warm and ready."
                self.isTrendModelReady = warmup.trendRuntimeMessage == nil
                if warmup.trendRuntimeMessage == nil {
                    self.lastTrendSource = .melange
                }

                self.redactionRuntimeMessage = warmup.redactionRuntimeMessage
                    ?? "Redaction model is warm and ready."
                self.isRedactionModelReady = warmup.redactionRuntimeMessage == nil
                if warmup.redactionRuntimeMessage == nil {
                    self.lastRedactionSource = .melange
                }

                self.isRefreshingInferenceStatus = false
            }
        }
    }

    private func rebuildCoordinatorForCurrentToggle() {
        coordinator = serviceFactory.makeCoordinator(journalMelangeEnabledOverride: journalMelangeEnabled)
        SumiInferenceLog.event(
            service: "AppState",
            action: "Rebuilt coordinator for journal toggle",
            metadata: ["journalMelangeEnabled": "\(journalMelangeEnabled)"]
        )
    }

    private func loadInitialData() {
        do {
            let seed = try seedLoader.loadSeedData()
            let localSnapshot = try? localStateStore.load()

            userPreferences = seed.profile
            if let localSnapshot, !localSnapshot.entries.isEmpty {
                journalEntries = localSnapshot.entries
                    .map { entry in
                        var copy = entry
                        if let summary = copy.generatedSummary, let status = copy.generatedStatus {
                            copy.generatedSummary = UserFacingTextSanitizer.sanitizeJournalSummary(summary, status: status)
                        }
                        return copy
                    }
                    .sorted { $0.date < $1.date }
                metrics = localSnapshot.metrics.sorted { $0.date < $1.date }
            } else {
                journalEntries = seed.entries
                    .map { entry in
                        var copy = entry
                        if let summary = copy.generatedSummary, let status = copy.generatedStatus {
                            copy.generatedSummary = UserFacingTextSanitizer.sanitizeJournalSummary(summary, status: status)
                        }
                        return copy
                    }
                metrics = seed.metrics
            }
            shareExamples = seed.shareExamples
            selectedShareEntryID = journalEntries.last?.id
            noteDraft = ""
            selectedShareSource = .selectedEntry
            demoState = DemoState(hasLoadedSeedData: true, isDemoMode: true, seedVersion: 1)
            journalRuntimeMessage = nil
            trendRuntimeMessage = nil
            redactionRuntimeMessage = nil
            isShareLongRunning = false
            let prewarmEnabled = shouldPrewarmModels
            isPrewarmingModels = prewarmEnabled && MelangeAvailability.sdkAvailable && melangeConfig.hasPersonalKey
            let generation = UUID()
            warmupTaskGeneration = generation

            let metricsSnapshot = metrics
            let windowSnapshot = selectedTrendWindow
            Task {
                if prewarmEnabled && MelangeAvailability.sdkAvailable && melangeConfig.hasPersonalKey {
                    let warmup = await coordinator.prewarmModels()
                    let initialTrend = await coordinator.refreshTrendWithDiagnostics(
                        metrics: metricsSnapshot,
                        windowDays: windowSnapshot,
                        preferPrimary: true
                    )

                    await MainActor.run {
                        guard self.warmupTaskGeneration == generation else { return }
                        self.latestTrendAssessment = initialTrend.assessment
                        self.lastTrendSource = initialTrend.assessment.source

                        self.journalRuntimeMessage = warmup.journalRuntimeMessage
                        if self.journalMelangeEnabled && warmup.journalRuntimeMessage == nil {
                            self.lastJournalSource = .melange
                            self.isJournalModelReady = true
                        } else if self.journalMelangeEnabled {
                            self.isJournalModelReady = false
                        }
                        self.isTrendModelReady = warmup.trendRuntimeMessage == nil
                        self.isRedactionModelReady = warmup.redactionRuntimeMessage == nil
                        self.redactionRuntimeMessage = warmup.redactionRuntimeMessage
                        self.trendRuntimeMessage = warmup.trendRuntimeMessage
                            ?? initialTrend.runtimeMessage
                            ?? (initialTrend.assessment.source == .melange ? "Chronos trend model active (Melange)." : nil)
                        self.isPrewarmingModels = false
                    }
                } else {
                    let initialTrend = await coordinator.refreshTrendWithDiagnostics(
                        metrics: metricsSnapshot,
                        windowDays: windowSnapshot,
                        preferPrimary: false
                    )
                    await MainActor.run {
                        guard self.warmupTaskGeneration == generation else { return }
                        self.latestTrendAssessment = initialTrend.assessment
                        self.lastTrendSource = initialTrend.assessment.source
                        self.isTrendModelReady = initialTrend.assessment.source == .melange
                        self.isRedactionModelReady = false
                        self.isJournalModelReady = false
                        self.trendRuntimeMessage = "Baseline trend preview active. Tap Refresh in Trends to run Chronos."
                        self.isPrewarmingModels = false
                    }
                }
            }
            persistLocalState()
        } catch {
            lastErrorMessage = "Failed to load seed data: \(error.localizedDescription)"
        }
    }

    private var shouldPrewarmModels: Bool {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["ZETIC_PREWARM_MODELS"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        let normalized = raw.lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
    }

    private func persistLocalState() {
        do {
            try localStateStore.save(entries: journalEntries, metrics: metrics)
        } catch {
            print("[SumiSense][Storage] Save failed: \(error.localizedDescription)")
        }
    }

    private func buildSharePayload() -> SharePayload? {
        switch selectedShareSource {
        case .selectedEntry:
            guard let entry = selectedShareEntry else { return nil }
            let metric = metricPoint(onSameDayAs: entry.date)
            return composeSingleEntryPayload(entry: entry, metric: metric)
        case .lastSevenDays:
            let entries = sevenDayEntries
            guard !entries.isEmpty else { return nil }
            return composeSevenDayPayload(entries: entries, metrics: sevenDayMetrics)
        }
    }

    private func metricPoint(onSameDayAs date: Date) -> WellnessMetricPoint? {
        let calendar = Calendar.current
        return metrics.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
    }

    private func composeSingleEntryPayload(entry: JournalEntry, metric: WellnessMetricPoint?) -> SharePayload {
        var noteSections: [String] = []
        noteSections.append("Entry date: \(SumiDate.display(entry.date))")
        noteSections.append("Journal note: \(entry.generatedSummary ?? entry.rawText)")

        if !entry.manualTags.isEmpty {
            noteSections.append("Manual tags: \(entry.manualTags.joined(separator: ", "))")
        }
        if !entry.detectedTags.isEmpty {
            noteSections.append("Detected tags: \(entry.detectedTags.joined(separator: ", "))")
        }

        let noteText = noteSections.joined(separator: "\n")
        let metricText: String
        if let metric {
            metricText = metricBlock(from: [metric], title: "Associated wellness metrics")
        } else {
            metricText = "Associated wellness metrics: unavailable for this date."
        }
        return SharePayload(
            redactionInputText: noteText,
            sourcePreviewText: [noteText, metricText].joined(separator: "\n\n"),
            metricsContextText: metricText
        )
    }

    private func composeSevenDayPayload(entries: [JournalEntry], metrics: [WellnessMetricPoint]) -> SharePayload {
        let sortedEntries = entries.sorted { $0.date < $1.date }
        let entryLines = sortedEntries.map {
            "- \(SumiDate.short($0.date)): \(($0.generatedSummary ?? $0.rawText).trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let notesSection = [
            "7-day export window (\(SumiDate.short(sortedEntries.first?.date ?? Date())) - \(SumiDate.short(sortedEntries.last?.date ?? Date()))):",
            "Notes:\n" + entryLines.joined(separator: "\n")
        ].joined(separator: "\n")
        let metricsSection = metricBlock(from: metrics, title: "Wellness metrics for this 7-day window")
        return SharePayload(
            redactionInputText: notesSection,
            sourcePreviewText: [notesSection, metricsSection].joined(separator: "\n\n"),
            metricsContextText: metricsSection
        )
    }

    private func metricBlock(from metrics: [WellnessMetricPoint], title: String) -> String {
        guard !metrics.isEmpty else { return "\(title): unavailable." }

        let sleep = metrics.map(\.sleepHours)
        let mood = metrics.map(\.moodScore)
        let stress = metrics.map(\.stressScore)
        let craving = metrics.map(\.cravingScore)
        let energy = metrics.map(\.energyScore)
        let steps = metrics.compactMap(\.steps).map(Double.init)

        var lines: [String] = [
            title + ":",
            "- Sleep avg \(format(sleep.average)) h",
            "- Mood avg \(format(mood.average))/10",
            "- Stress avg \(format(stress.average))/10",
            "- Craving avg \(format(craving.average))/10",
            "- Energy avg \(format(energy.average))/10"
        ]
        if !steps.isEmpty {
            lines.append("- Steps avg \(Int(steps.average.rounded()))")
        }
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func mergeShareResult(_ result: RedactionResult, payload: SharePayload) -> RedactionResult {
        guard let metricsContext = payload.metricsContextText else {
            return RedactionResult(
                mode: result.mode,
                sourceText: payload.sourcePreviewText,
                outputText: result.outputText,
                redactionsApplied: result.redactionsApplied,
                source: result.source
            )
        }
        return RedactionResult(
            mode: result.mode,
            sourceText: payload.sourcePreviewText,
            outputText: [result.outputText, metricsContext].joined(separator: "\n\n"),
            redactionsApplied: result.redactionsApplied,
            source: result.source
        )
    }
}

private struct SharePayload {
    let redactionInputText: String
    let sourcePreviewText: String
    let metricsContextText: String?
}
