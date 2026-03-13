import Foundation

#if canImport(ZeticMLange)
import ZeticMLange
#endif

final class MelangeMedgemmaJournalService: JournalInferenceService {
    private let config: MelangeConfig
    private let inferenceTimeoutSeconds: TimeInterval = 300
    private let coldStartInferenceTimeoutSeconds: TimeInterval = 300
    private let tokenLimit = 128

    #if canImport(ZeticMLange)
    private var model: ZeticMLangeLLMModel?
    private var selectedModelDescriptor: String?
    private var selectedModelModeDescriptor: String?
    private var hasLoggedModelReady = false
    private let modelLock = NSLock()
    private let inferenceQueue = DispatchQueue(label: "com.sumisense.melange.medgemma.inference", qos: .userInitiated)
    #endif

    init(config: MelangeConfig = .default) {
        self.config = config
        let versionText = config.journalModelVersion.map(String.init) ?? "latest"
        SumiInferenceLog.event(
            service: "Journal",
            action: "Initialized MelangeMedgemmaJournalService",
            metadata: [
                "model": "\(config.journalModelID)@v\(versionText)",
                "mode": journalModeDescriptor,
                "keySource": config.personalKeySource,
                "hasKey": "\(config.hasPersonalKey)"
            ]
        )
    }

    func analyze(
        note: String,
        manualTags: [String],
        contextEntries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) async throws -> DailySignalAssessment {
        #if canImport(ZeticMLange)
        guard config.hasPersonalKey else { throw MelangeRuntimeError.missingCredentials }
        try ensureRuntimeEligibility(phase: "analyze")
        let timeout = model == nil ? coldStartInferenceTimeoutSeconds : inferenceTimeoutSeconds
        let callID = UUID().uuidString.prefix(8)
        SumiInferenceLog.event(
            service: "Journal",
            action: "Analyze requested",
            metadata: [
                "callID": String(callID),
                "noteChars": "\(note.count)",
                "manualTags": "\(manualTags.count)",
                "contextEntries": "\(contextEntries.count)",
                "metrics": "\(metrics.count)",
                "timeoutSec": "\(Int(timeout))"
            ]
        )
        let start = CFAbsoluteTimeGetCurrent()
        let assessment = try await runInferenceWithTimeout(seconds: timeout) { [self] in
            try analyzeSynchronously(
                note: note,
                manualTags: manualTags,
                contextEntries: contextEntries,
                metrics: metrics
            )
        }
        SumiInferenceLog.event(
            service: "Journal",
            action: "Analyze completed",
            metadata: [
                "callID": String(callID),
                "status": assessment.status.rawValue,
                "tags": "\(assessment.signalTags.count)",
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )
        return assessment
        #else
        throw MelangeRuntimeError.sdkUnavailable
        #endif
    }

    func warmUp() async throws {
        #if canImport(ZeticMLange)
        guard config.hasPersonalKey else { throw MelangeRuntimeError.missingCredentials }
        if !shouldPrewarmJournalModel {
            SumiInferenceLog.event(service: "Journal", action: "Warmup skipped", metadata: ["reason": "prewarm disabled by configuration", "hint": "Set ZETIC_PREWARM_JOURNAL=1 to enable"])
            return
        }
        try ensureRuntimeEligibility(phase: "warmup")
        let timeout = model == nil ? coldStartInferenceTimeoutSeconds : inferenceTimeoutSeconds
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Journal",
            action: "Warmup start",
            metadata: ["callID": String(callID), "timeoutSec": "\(Int(timeout))"]
        )
        _ = try await runInferenceWithTimeout(seconds: timeout) { [self] in
            try loadIfNeeded()
            return true
        }
        SumiInferenceLog.event(
            service: "Journal",
            action: "Warmup complete",
            metadata: ["callID": String(callID), "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"]
        )
        #else
        throw MelangeRuntimeError.sdkUnavailable
        #endif
    }

    #if canImport(ZeticMLange)
    private func analyzeSynchronously(
        note: String,
        manualTags: [String],
        contextEntries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) throws -> DailySignalAssessment {
        let start = CFAbsoluteTimeGetCurrent()
        try loadIfNeeded()
        guard let model = currentModel() else { throw MelangeRuntimeError.modelNotInitialized }
        logUsingModel(action: "Journal analyze")

        let prompt = makePrompt(
            note: note,
            manualTags: manualTags,
            contextEntries: contextEntries,
            metrics: metrics
        )

        let rawResponse: String
        do {
            rawResponse = try runLLM(prompt: prompt, with: model)
        } catch {
            SumiInferenceLog.event(
                service: "Journal",
                action: "LLM generation degraded; using deterministic local interpretation",
                level: .warning,
                metadata: ["error": SumiInferenceLog.truncate(error.localizedDescription, limit: 180)]
            )
            let parsed = lenientParseResponse(
                "",
                note: note,
                manualTags: manualTags,
                metrics: metrics
            )
            return makeAssessment(
                parsed: parsed,
                manualTags: manualTags,
                source: .melange
            )
        }
        let parsed: ParsedJournalOutput
        do {
            parsed = try parseResponse(rawResponse)
        } catch {
            SumiInferenceLog.event(
                service: "Journal",
                action: "Strict JSON parse failed; applying lenient parse",
                level: .warning,
                metadata: ["error": SumiInferenceLog.truncate(error.localizedDescription, limit: 180)]
            )
            parsed = lenientParseResponse(
                rawResponse,
                note: note,
                manualTags: manualTags,
                metrics: metrics
            )
        }

        let assessment = makeAssessment(
            parsed: parsed,
            manualTags: manualTags,
            source: .melange
        )
        SumiInferenceLog.event(
            service: "Journal",
            action: "Synchronous analyze pass complete",
            metadata: [
                "promptChars": "\(prompt.count)",
                "responseChars": "\(rawResponse.count)",
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )
        return assessment
    }

    private func makeAssessment(
        parsed: ParsedJournalOutput,
        manualTags: [String],
        source: InferenceSource
    ) -> DailySignalAssessment {
        var tags = parsed.tags.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        tags.append(contentsOf: manualTags.map { $0.lowercased() })
        tags = Array(NSOrderedSet(array: tags.filter { !$0.isEmpty }).compactMap { $0 as? String })

        let rawSummary = parsed.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawExplanation = parsed.explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        let sanitizedSummary = sanitizeUserFacingSummary(rawSummary, status: parsed.status)
        let sanitizedExplanation = sanitizeUserFacingExplanation(rawExplanation, status: parsed.status, tags: tags)

        return DailySignalAssessment(
            date: Date(),
            status: parsed.status,
            summary: sanitizedSummary,
            explanation: sanitizedExplanation,
            signalTags: Array(tags.prefix(6)),
            confidence: confidence(for: parsed.status),
            source: source
        )
    }

    private func loadIfNeeded() throws {
        if currentModel() != nil {
            SumiInferenceLog.event(service: "Journal", action: "Model cache hit", metadata: ["model": selectedModelDescriptor ?? modelDescriptorFallback])
            return
        }

        let candidates = medgemmaCandidates()
        var lastError: Error?
        SumiInferenceLog.event(
            service: "Journal",
            action: "Model load started",
            metadata: [
                "candidateCount": "\(candidates.count)",
                "candidates": candidates.map(\.descriptor).joined(separator: "|")
            ]
        )

        for candidate in candidates {
            for mode in journalModelModesToTry {
                do {
                    let loadStart = CFAbsoluteTimeGetCurrent()
                    let modeDescriptor = descriptor(for: mode)
                    SumiInferenceLog.event(
                        service: "Journal",
                        action: "Trying model candidate",
                        metadata: [
                            "candidate": candidate.descriptor,
                            "mode": modeDescriptor
                        ]
                    )
                    let constructorStart = CFAbsoluteTimeGetCurrent()
                    let stallTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                    stallTimer.schedule(deadline: .now() + 15, repeating: 15)
                    stallTimer.setEventHandler {
                        SumiInferenceLog.event(
                            service: "Journal",
                            action: "Model constructor still running",
                            level: .warning,
                            metadata: [
                                "candidate": candidate.descriptor,
                                "mode": modeDescriptor,
                                "waitMs": "\(SumiInferenceLog.elapsedMilliseconds(since: constructorStart))"
                            ]
                        )
                    }
                    stallTimer.resume()
                    let progressLock = NSLock()
                    var lastProgressBucket = -1
                    let loadedModel = try ZeticMLangeLLMModel(
                        personalKey: config.personalKey,
                        name: candidate.id,
                        version: candidate.version,
                        modelMode: mode,
                        onDownload: { progress in
                            let bucket = max(0, min(100, Int((progress * 100).rounded())))
                            let bucket10 = (bucket / 10) * 10
                            progressLock.lock()
                            defer { progressLock.unlock() }
                            guard bucket10 != lastProgressBucket else { return }
                            lastProgressBucket = bucket10
                            SumiInferenceLog.event(
                                service: "Journal",
                                action: "Model download progress",
                                metadata: [
                                    "candidate": candidate.descriptor,
                                    "mode": modeDescriptor,
                                    "progressPct": "\(bucket10)"
                                ]
                            )
                        }
                    )
                    stallTimer.cancel()
                    SumiInferenceLog.event(
                        service: "Journal",
                        action: "Model constructor returned",
                        metadata: [
                            "candidate": candidate.descriptor,
                            "mode": modeDescriptor,
                            "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: constructorStart))"
                        ]
                    )
                    setModel(loadedModel)
                    selectedModelDescriptor = candidate.descriptor
                    selectedModelModeDescriptor = modeDescriptor
                    if candidate.id != config.journalModelID || candidate.version != config.journalModelVersion {
                        SumiInferenceLog.event(service: "Journal", action: "Switched to accessible model candidate", level: .warning, metadata: ["candidate": candidate.descriptor])
                    }
                    if !hasLoggedModelReady {
                        SumiInferenceLog.event(
                            service: "Journal",
                            action: "Model ready",
                            metadata: [
                                "candidate": candidate.descriptor,
                                "mode": modeDescriptor,
                                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: loadStart))"
                            ]
                        )
                        hasLoggedModelReady = true
                    }
                    return
                } catch {
                    lastError = error
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    SumiInferenceLog.event(
                        service: "Journal",
                        action: "Model candidate failed",
                        level: .warning,
                        metadata: [
                            "candidate": candidate.descriptor,
                            "mode": descriptor(for: mode),
                            "error": SumiInferenceLog.truncate(detail, limit: 220)
                        ]
                    )
                }
            }
        }

        throw JournalModelLoadError.noAccessibleModel(
            attemptedDescriptors: candidates.map(\.descriptor),
            underlying: lastError
        )
    }

    private func medgemmaCandidates() -> [JournalModelCandidate] {
        var unique: [JournalModelCandidate] = []

        func appendCandidate(_ id: String, _ version: Int?) {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else { return }
            let candidate = JournalModelCandidate(id: trimmedID, version: version)
            if !unique.contains(candidate) {
                unique.append(candidate)
            }
        }

        let configuredID = config.journalModelID
        let configuredVersion = config.journalModelVersion
        let configuredLooksLikeMedgemma = configuredID.lowercased().contains("medgemma")
        let configuredLooksLikeQwen = configuredID.lowercased().contains("qwen")

        if configuredLooksLikeMedgemma {
            if allowMedgemmaCandidate {
                appendCandidate(configuredID, configuredVersion ?? 1)
            }
        } else if configuredLooksLikeQwen {
            appendCandidate(configuredID, configuredVersion ?? 1)
        } else {
            // For unknown IDs, avoid "latest" and try a pinned version if provided.
            if let configuredVersion {
                appendCandidate(configuredID, configuredVersion)
            }
        }

        // Prefer a known official LLM sample candidate first.
        appendCandidate("Qwen/Qwen3-4B", 1)

        // Medgemma has shown constructor crashes on some runtimes; keep it opt-in only.
        if allowMedgemmaCandidate {
            appendCandidate("Steve/Medgemma-1.5-4b-it", 1)
        }

        return unique
    }

    private var allowMedgemmaCandidate: Bool {
        let env = ProcessInfo.processInfo.environment
        let raw = env["ZETIC_ENABLE_MEDGEMMA_JOURNAL"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    private func runLLM(prompt: String, with model: ZeticMLangeLLMModel) throws -> String {
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Journal",
            action: "LLM run start",
            metadata: ["promptChars": "\(prompt.count)", "tokenLimit": "\(tokenLimit)"]
        )
        let runResult = try model.run(prompt)
        SumiInferenceLog.event(
            service: "Journal",
            action: "LLM prompt accepted",
            level: .debug,
            metadata: ["promptTokens": "\(runResult.promptTokens)"]
        )

        var streamed = ""
        var emittedTokens = 0
        var idlePolls = 0

        for _ in 0..<tokenLimit {
            let next = model.waitForNextToken()
            if next.code < 0 {
                // Some runtimes report a terminal non-zero code after generation.
                // If we already have tokens or the stream is marked finished, treat as graceful termination.
                if next.isFinished || next.generatedTokens == 0 || emittedTokens > 0 || !next.token.isEmpty {
                    SumiInferenceLog.event(
                        service: "Journal",
                        action: "LLM token stream ended with terminal code",
                        level: .warning,
                        metadata: ["code": "\(next.code)", "generatedTokens": "\(next.generatedTokens)", "isFinished": "\(next.isFinished)"]
                    )
                    break
                }
                SumiInferenceLog.event(service: "Journal", action: "LLM token stream failed before output", level: .warning, metadata: ["code": "\(next.code)"])
                throw MelangeRuntimeError.invalidModelOutput
            }

            if !next.token.isEmpty {
                streamed += next.token
                emittedTokens += 1
                idlePolls = 0
                if emittedTokens % 40 == 0 {
                    SumiInferenceLog.event(
                        service: "Journal",
                        action: "LLM token progress",
                        level: .debug,
                        metadata: ["emittedTokens": "\(emittedTokens)"]
                    )
                }
            } else {
                idlePolls += 1
            }

            if next.generatedTokens == 0 || next.isFinished {
                if emittedTokens > 0 || !next.token.isEmpty || idlePolls >= 2 {
                    break
                }
                continue
            }

            if emittedTokens >= 12, emittedTokens % 4 == 0, hasCompleteJSONObject(in: streamed) {
                SumiInferenceLog.event(
                    service: "Journal",
                    action: "LLM early stop after JSON object",
                    level: .debug,
                    metadata: ["emittedTokens": "\(emittedTokens)"]
                )
                break
            }
        }

        let trimmed = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MelangeRuntimeError.invalidModelOutput }
        SumiInferenceLog.event(
            service: "Journal",
            action: "LLM run complete",
            metadata: [
                "emittedTokens": "\(emittedTokens)",
                "responseChars": "\(trimmed.count)",
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )
        return trimmed
    }

    private func hasCompleteJSONObject(in text: String) -> Bool {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return false
        }
        let candidate = String(text[start...end])
        guard let data = candidate.data(using: .utf8) else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return object is [String: Any]
    }

    private func runInferenceWithTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () throws -> T
    ) async throws -> T {
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Journal",
            action: "Queued inference operation",
            metadata: ["callID": String(callID), "timeoutSec": "\(Int(seconds))"]
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let lock = NSLock()
            var isResolved = false
            var timedOut = false

            @discardableResult
            func resolve(_ result: Result<T, Error>) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !isResolved else { return false }
                isResolved = true
                continuation.resume(with: result)
                return true
            }

            inferenceQueue.async {
                do {
                    let value = try operation()
                    let didResolve = resolve(.success(value))
                    if didResolve {
                        SumiInferenceLog.event(
                            service: "Journal",
                            action: "Inference operation completed",
                            metadata: [
                                "callID": String(callID),
                                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                            ]
                        )
                    }
                    let didPreviouslyTimeout = {
                        lock.lock()
                        defer { lock.unlock() }
                        return timedOut
                    }()
                    if !didResolve, didPreviouslyTimeout {
                        SumiInferenceLog.event(
                            service: "Journal",
                            action: "Late completion after timeout; preserving model cache",
                            level: .warning,
                            metadata: [
                                "callID": String(callID),
                                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                            ]
                        )
                    }
                } catch {
                    let didResolve = resolve(.failure(error))
                    if didResolve {
                        SumiInferenceLog.event(
                            service: "Journal",
                            action: "Inference operation failed",
                            level: .warning,
                            metadata: [
                                "callID": String(callID),
                                "error": SumiInferenceLog.truncate(error.localizedDescription, limit: 220),
                                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                            ]
                        )
                    }
                    let didPreviouslyTimeout = {
                        lock.lock()
                        defer { lock.unlock() }
                        return timedOut
                    }()
                    if !didResolve, didPreviouslyTimeout {
                        SumiInferenceLog.event(
                            service: "Journal",
                            action: "Late failure after timeout; preserving model cache",
                            level: .warning,
                            metadata: [
                                "callID": String(callID),
                                "error": SumiInferenceLog.truncate(error.localizedDescription, limit: 220),
                                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                            ]
                        )
                    }
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
                let shouldResolveTimeout = {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResolved else { return false }
                    timedOut = true
                    return true
                }()
                guard shouldResolveTimeout else { return }
                SumiInferenceLog.event(
                    service: "Journal",
                    action: "Inference timed out",
                    level: .warning,
                    metadata: [
                        "callID": String(callID),
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
                _ = resolve(.failure(MelangeRuntimeError.inferenceTimeout))
            }
        }
    }

    private func currentModel() -> ZeticMLangeLLMModel? {
        modelLock.lock()
        defer { modelLock.unlock() }
        return model
    }

    private func setModel(_ newModel: ZeticMLangeLLMModel?) {
        modelLock.lock()
        defer { modelLock.unlock() }
        model = newModel
    }

    private func logUsingModel(action: String) {
        let descriptor = selectedModelDescriptor ?? modelDescriptorFallback
        let modeDescriptor = selectedModelModeDescriptor ?? journalModeDescriptor
        SumiInferenceLog.event(
            service: "Journal",
            action: action,
            metadata: [
                "model": descriptor,
                "mode": modeDescriptor
            ]
        )
    }

    private var modelDescriptorFallback: String {
        if let version = config.journalModelVersion {
            return "\(config.journalModelID)@v\(version)"
        }
        return "\(config.journalModelID)@latest"
    }

    private var journalModelMode: LLMModelMode {
        let env = ProcessInfo.processInfo.environment
        let raw = env["ZETIC_JOURNAL_MODEL_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch raw {
        case "regular":
            return .RUN_REGULAR
        case "speed":
            return .RUN_SPEED
        case "accuracy":
            return .RUN_ACCURACY
        default:
            return .RUN_REGULAR
        }
    }

    private var journalModelModesToTry: [LLMModelMode] {
        let modes: [LLMModelMode] = [journalModelMode, .RUN_REGULAR, .RUN_SPEED, .RUN_ACCURACY]
        var unique: [LLMModelMode] = []
        for mode in modes where !unique.contains(mode) {
            unique.append(mode)
        }
        return unique
    }

    private var journalModeDescriptor: String {
        descriptor(for: journalModelMode)
    }

    private func descriptor(for mode: LLMModelMode) -> String {
        switch mode {
        case .RUN_SPEED: return "RUN_SPEED"
        case .RUN_ACCURACY: return "RUN_ACCURACY"
        case .RUN_REGULAR: return "RUN_REGULAR"
        @unknown default: return "UNKNOWN"
        }
    }

    private var shouldPrewarmJournalModel: Bool {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["ZETIC_PREWARM_JOURNAL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        return isTruthy(raw)
    }

    private func ensureRuntimeEligibility(phase: String) throws {
        let env = ProcessInfo.processInfo.environment
        let guardRaw = env["ZETIC_ENABLE_JOURNAL_RAM_GUARD"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldGuard = isTruthy(guardRaw)
        guard shouldGuard else { return }

        let minimumRecommendedRAMBytes: UInt64 = 6 * 1024 * 1024 * 1024
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        if physicalMemory < minimumRecommendedRAMBytes {
            let message = "Journal model skipped (\(phase)): device RAM \(physicalMemory / (1024 * 1024 * 1024))GB is below recommended 6GB. Disable ZETIC_ENABLE_JOURNAL_RAM_GUARD to force run."
            throw MelangeRuntimeError.unsupportedRuntime(message)
        }
    }

    private func isTruthy(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
    }
    #endif

    private func makePrompt(
        note: String,
        manualTags: [String],
        contextEntries: [JournalEntry],
        metrics: [WellnessMetricPoint]
    ) -> String {
        let sortedMetrics = metrics.sorted { $0.date < $1.date }
        let recent = Array(sortedMetrics.suffix(7))
        let baseline = Array(sortedMetrics.dropLast(min(7, sortedMetrics.count)).suffix(14))

        let recentSleep = recent.map(\.sleepHours).average
        let recentStress = recent.map(\.stressScore).average
        let recentCraving = recent.map(\.cravingScore).average

        let baselineSleep = baseline.map(\.sleepHours).average
        let baselineStress = baseline.map(\.stressScore).average
        let baselineCraving = baseline.map(\.cravingScore).average

        let contextSnippet = contextEntries
            .sorted { $0.date > $1.date }
            .prefix(2)
            .map { "- \($0.generatedSummary ?? $0.rawText)" }
            .joined(separator: "\n")

        let tagsSnippet = manualTags.joined(separator: ", ")

        return """
        Return strict JSON only:
        {"status":"stable|watch|elevated","summary":"<=140 chars","explanation":"<=180 chars","tags":["sleep disruption","stress","craving","isolation","fatigue"]}
        Output rule: one single-line JSON object only. No markdown. No prose outside JSON.

        Safety boundary: this is pattern-awareness support, not diagnosis.
        Tone: calm, precise, non-alarmist.

        Baseline stats:
        rs=\(formatDecimal(recentSleep)) bs=\(formatDecimal(baselineSleep))
        rstr=\(formatDecimal(recentStress)) bstr=\(formatDecimal(baselineStress))
        rcr=\(formatDecimal(recentCraving)) bcr=\(formatDecimal(baselineCraving))

        Recent context:
        \(contextSnippet.isEmpty ? "none" : contextSnippet)

        Manual tags: \(tagsSnippet.isEmpty ? "none" : tagsSnippet)
        Note: \(note)
        """
    }

    private func parseResponse(_ response: String) throws -> ParsedJournalOutput {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            throw MelangeRuntimeError.invalidModelOutput
        }

        let jsonString = String(cleaned[start...end])
        guard let data = jsonString.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MelangeRuntimeError.invalidModelOutput
        }

        guard let rawStatus = (object["status"] as? String),
              let status = normalizeStatus(rawStatus) else {
            throw MelangeRuntimeError.invalidModelOutput
        }

        let summary = (object["summary"] as? String) ?? ""
        let explanation = (object["explanation"] as? String) ?? ""
        let tags = parseTags(from: object["tags"])

        return ParsedJournalOutput(
            status: status,
            summary: summary,
            explanation: explanation,
            tags: tags
        )
    }

    private func normalizeStatus(_ raw: String) -> SignalState? {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains("elevated") || normalized.contains("high") || normalized.contains("risk") {
            return .elevated
        }
        if normalized.contains("watch") || normalized.contains("moderate") || normalized.contains("shift") {
            return .watch
        }
        if normalized.contains("stable") || normalized.contains("low") || normalized.contains("calm") {
            return .stable
        }
        return SignalState(rawValue: normalized)
    }

    private func lenientParseResponse(
        _ response: String,
        note: String,
        manualTags: [String],
        metrics: [WellnessMetricPoint]
    ) -> ParsedJournalOutput {
        let combined = "\(response)\n\(note)".lowercased()
        let detected = detectTags(from: combined, manualTags: manualTags)
        let status = inferStatus(from: combined, tags: detected, metrics: metrics)

        let sanitizedResponse = sanitizeModelNarrative(response)
        let compactSummary = sanitizedResponse
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        if compactSummary.isEmpty {
            summary = defaultSummary(for: status)
        } else {
            summary = String(compactSummary.prefix(140))
        }

        let explanation = defaultExplanation(for: status, tags: detected)
        return ParsedJournalOutput(status: status, summary: summary, explanation: explanation, tags: detected)
    }

    private func sanitizeModelNarrative(_ response: String) -> String {
        var sanitized = response

        // Strip chain-of-thought style blocks sometimes emitted by LLMs.
        sanitized = sanitized.replacingOccurrences(
            of: "(?is)<think>.*?</think>",
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "(?im)^\\s*<think>.*$",
            with: " ",
            options: .regularExpression
        )

        // Remove common meta-reasoning lead-ins that are not user-facing copy.
        let blockedLeadIns = [
            "okay, let's",
            "first, i need to",
            "the user wants",
            "strict json output",
            "based on the provided guidelines"
        ]
        let lines = sanitized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let normalized = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !normalized.isEmpty else { return false }
                return !blockedLeadIns.contains(where: { normalized.contains($0) })
            }

        sanitized = lines.joined(separator: " ")

        // If JSON object exists in response, prioritize extracting outside text only.
        if let start = sanitized.firstIndex(of: "{"),
           let end = sanitized.lastIndex(of: "}"),
           start <= end {
            let prefix = sanitized[..<start]
            let suffix = sanitized[sanitized.index(after: end)...]
            sanitized = "\(prefix) \(suffix)"
        }

        return sanitized
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeUserFacingSummary(_ summary: String, status: SignalState) -> String {
        let cleaned = sanitizeModelNarrative(summary)
        guard !cleaned.isEmpty else { return defaultSummary(for: status) }
        guard !looksLikeReasoningLeak(cleaned) else { return defaultSummary(for: status) }

        let trimmed: String
        if let firstSentence = cleaned.split(separator: ".").first {
            let candidate = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            trimmed = candidate.isEmpty ? cleaned : "\(candidate)."
        } else {
            trimmed = cleaned
        }
        return String(trimmed.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeUserFacingExplanation(_ explanation: String, status: SignalState, tags: [String]) -> String {
        let cleaned = sanitizeModelNarrative(explanation)
        guard !cleaned.isEmpty else { return defaultExplanation(for: status, tags: tags) }
        guard !looksLikeReasoningLeak(cleaned) else { return defaultExplanation(for: status, tags: tags) }
        return String(cleaned.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeReasoningLeak(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = [
            "<think>",
            "the user wants",
            "strict json",
            "provided guidelines",
            "first, i need to",
            "let's tackle this",
            "parse all the"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private func detectTags(from text: String, manualTags: [String]) -> [String] {
        var tags = Set(manualTags.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        let lexicon: [(String, String)] = [
            ("sleep", "sleep disruption"),
            ("insomnia", "sleep disruption"),
            ("stress", "stress"),
            ("anx", "stress"),
            ("crav", "craving"),
            ("alone", "isolation"),
            ("isolat", "isolation"),
            ("burnout", "fatigue"),
            ("exhaust", "fatigue"),
            ("tired", "fatigue")
        ]
        for (needle, tag) in lexicon where text.contains(needle) {
            tags.insert(tag)
        }
        return Array(tags.filter { !$0.isEmpty }).prefix(6).map { $0 }
    }

    private func inferStatus(from text: String, tags: [String], metrics: [WellnessMetricPoint]) -> SignalState {
        var score = 0
        if text.contains("panic") || text.contains("relapse") || text.contains("unsafe") {
            score += 3
        }
        if tags.contains("craving") { score += 2 }
        if tags.contains("sleep disruption") { score += 1 }
        if tags.contains("stress") { score += 1 }
        if tags.contains("isolation") { score += 1 }
        if tags.contains("fatigue") { score += 1 }

        let recent = metrics.sorted { $0.date < $1.date }.suffix(3)
        let avgSleep = recent.map(\.sleepHours).average
        let avgStress = recent.map(\.stressScore).average
        if avgSleep < 5.2 {
            score += 1
        }
        if avgStress > 7.2 {
            score += 1
        }

        if score >= 5 { return .elevated }
        if score >= 2 { return .watch }
        return .stable
    }

    private func defaultSummary(for status: SignalState) -> String {
        switch status {
        case .stable:
            return "Your note reflects a mostly stable pattern today."
        case .watch:
            return "Your note suggests a mild stability shift."
        case .elevated:
            return "Your note shows elevated signals relative to baseline."
        }
    }

    private func defaultExplanation(for status: SignalState, tags: [String]) -> String {
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

    private func parseTags(from value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
        }
        if let string = value as? String {
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return []
    }

    private func confidence(for state: SignalState) -> Double {
        switch state {
        case .stable:
            return 0.78
        case .watch:
            return 0.81
        case .elevated:
            return 0.84
        }
    }

    private func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

#if canImport(ZeticMLange)
private struct JournalModelCandidate: Equatable {
    let id: String
    let version: Int?

    var descriptor: String {
        if let version {
            return "\(id)@v\(version)"
        }
        return "\(id)@latest"
    }
}

private enum JournalModelLoadError: LocalizedError {
    case noAccessibleModel(attemptedDescriptors: [String], underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .noAccessibleModel(let attemptedDescriptors, let underlying):
            let attempted = attemptedDescriptors.joined(separator: ", ")
            let detail = (underlying as? LocalizedError)?.errorDescription ?? underlying?.localizedDescription ?? "unknown error"
            return "Journal model access failed for: \(attempted). Last error: \(detail)"
        }
    }
}
#endif

private struct ParsedJournalOutput {
    let status: SignalState
    let summary: String
    let explanation: String
    let tags: [String]
}
