import Foundation

#if canImport(ZeticMLange)
import ZeticMLange
#endif

final class MelangeChronosTrendService: TrendInferenceService {
    private let config: MelangeConfig
    private let localInterpreter = HeuristicTrendService()
    private let contextLength = 512
    private let modelLoadTimeoutSeconds: TimeInterval = 120
    private let modelRunTimeoutSeconds: TimeInterval = 20

    #if canImport(ZeticMLange)
    private var model: ZeticMLangeModel?
    private var selectedModelDescriptor: String?
    private var selectedExecutionPath: String = "RUN_SPEED"
    private let inferenceQueue = DispatchQueue(label: "com.sumisense.melange.chronos.inference", qos: .userInitiated)
    #endif

    init(config: MelangeConfig = .default) {
        self.config = config
        SumiInferenceLog.event(
            service: "Trend",
            action: "Initialized MelangeChronosTrendService",
            metadata: [
                "model": "\(config.chronosModelID)@v\(config.chronosModelVersion)",
                "preferredPath": preferCoreMLTargets ? "COREML->RUN_SPEED" : "RUN_SPEED",
                "keySource": config.personalKeySource,
                "hasKey": "\(config.hasPersonalKey)"
            ]
        )
    }

    func warmUp() async throws {
        #if canImport(ZeticMLange)
        guard config.hasPersonalKey else { throw MelangeRuntimeError.missingCredentials }
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(service: "Trend", action: "Warmup start")
        try await loadIfNeeded()
        _ = try await runInferenceWithTimeout(seconds: modelRunTimeoutSeconds) { [self] in
            guard let model else { throw MelangeRuntimeError.modelNotInitialized }
            let warmValues = Array(repeating: Float(0.55), count: 32)
            let inputTensor = makeContextTensor(values: warmValues)
            _ = try model.run(inputs: [inputTensor])
            return true
        }
        SumiInferenceLog.event(
            service: "Trend",
            action: "Warmup complete",
            metadata: ["elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"]
        )
        #else
        throw MelangeRuntimeError.sdkUnavailable
        #endif
    }

    func analyze(metrics: [WellnessMetricPoint], windowDays: Int) async throws -> TrendAssessment {
        #if canImport(ZeticMLange)
        guard config.hasPersonalKey else { throw MelangeRuntimeError.missingCredentials }
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Trend",
            action: "Analyze requested",
            metadata: [
                "callID": String(callID),
                "metricPoints": "\(metrics.count)",
                "windowDays": "\(windowDays)"
            ]
        )

        try await loadIfNeeded()

        let local = try await localInterpreter.analyze(metrics: metrics, windowDays: windowDays)
        let instabilitySeries = metrics.sorted { $0.date < $1.date }.map(instabilityScore)

        guard !instabilitySeries.isEmpty else {
            throw MelangeRuntimeError.invalidModelOutput
        }

        let forecast = try await runInferenceWithTimeout(seconds: modelRunTimeoutSeconds) { [self] in
            let inputTensor = makeContextTensor(values: instabilitySeries)
            guard let model else { throw MelangeRuntimeError.modelNotInitialized }
            let outputs = try model.run(inputs: [inputTensor])
            guard let first = outputs.first else {
                throw MelangeRuntimeError.invalidModelOutput
            }
            return try parseMedianForecast(from: first)
        }
        let projected = forecast.prefix(7).map(Double.init)
        let projectedAverage = projected.average

        let drift = projectedAverage - local.recentAverage
        let adjustedDirection = adjustedDirection(base: local.trendDirection, drift: drift)

        var highlights = local.metricHighlights
        if drift > 0.25 {
            highlights.insert("Chronos projects further instability", at: 0)
        } else if drift < -0.2 {
            highlights.insert("Chronos projects stabilization", at: 0)
        } else {
            highlights.insert("Chronos projection near baseline", at: 0)
        }

        let summary = summarize(direction: adjustedDirection, drift: drift)
        let result = TrendAssessment(
            windowDays: local.windowDays,
            stabilityScore: max(0, min(1, local.stabilityScore - drift * 0.05)),
            trendDirection: adjustedDirection,
            plainLanguageSummary: summary,
            metricHighlights: Array(highlights.prefix(4)),
            baselineAverage: local.baselineAverage,
            recentAverage: local.recentAverage,
            confidence: 0.84,
            source: .melange
        )

        SumiInferenceLog.event(
            service: "Trend",
            action: "Analyze completed",
            metadata: [
                "callID": String(callID),
                "direction": result.trendDirection.rawValue,
                "stability": String(format: "%.3f", result.stabilityScore),
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )
        return result
        #else
        throw MelangeRuntimeError.sdkUnavailable
        #endif
    }

    #if canImport(ZeticMLange)
    private func loadIfNeeded() async throws {
        if model != nil {
            SumiInferenceLog.event(service: "Trend", action: "Model cache hit", metadata: ["model": selectedModelDescriptor ?? "\(config.chronosModelID)@v\(config.chronosModelVersion)"])
            return
        }

        let candidates = chronosCandidates()
        let loadStart = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Trend",
            action: "Model load started",
            metadata: [
                "candidateCount": "\(candidates.count)",
                "candidates": candidates.map(\.descriptor).joined(separator: "|")
            ]
        )
        _ = try await runInferenceWithTimeout(seconds: modelLoadTimeoutSeconds) { [self] in
            var lastError: Error?

            for candidate in candidates {
                do {
                    var lastProgressBucket = -1
                    let progressLock = NSLock()
                    let candidateStart = CFAbsoluteTimeGetCurrent()
                    SumiInferenceLog.event(service: "Trend", action: "Trying model candidate", metadata: ["candidate": candidate.descriptor])
                    let progressHandler: (Float) -> Void = { progress in
                        let bucket = Int((progress * 100).rounded(.down) / 10) * 10
                        let shouldLog: Bool = {
                            progressLock.lock()
                            defer { progressLock.unlock() }
                            guard bucket != lastProgressBucket else { return false }
                            lastProgressBucket = bucket
                            return true
                        }()
                        guard shouldLog else { return }
                        SumiInferenceLog.event(
                            service: "Trend",
                            action: "Model download progress",
                            metadata: [
                                "candidate": candidate.descriptor,
                                "progressPct": "\(bucket)"
                            ]
                        )
                    }

                    var loadedModel: ZeticMLangeModel?
                    var executionPath = "RUN_SPEED"
                    if preferCoreMLTargets {
                        for target in preferredCoreMLTargets {
                            do {
                                loadedModel = try ZeticMLangeModel(
                                    personalKey: config.personalKey,
                                    name: candidate.id,
                                    version: candidate.version,
                                    target: target,
                                    onDownload: progressHandler
                                )
                                executionPath = targetDescriptor(target)
                                SumiInferenceLog.event(
                                    service: "Trend",
                                    action: "Loaded model with explicit target",
                                    metadata: [
                                        "candidate": candidate.descriptor,
                                        "target": executionPath
                                    ]
                                )
                                break
                            } catch {
                                SumiInferenceLog.event(
                                    service: "Trend",
                                    action: "Explicit target load failed",
                                    level: .warning,
                                    metadata: [
                                        "candidate": candidate.descriptor,
                                        "target": targetDescriptor(target),
                                        "error": SumiInferenceLog.truncate(error.localizedDescription, limit: 180)
                                    ]
                                )
                            }
                        }
                    }

                    if loadedModel == nil {
                        loadedModel = try ZeticMLangeModel(
                            personalKey: config.personalKey,
                            name: candidate.id,
                            version: candidate.version,
                            modelMode: .RUN_SPEED,
                            onDownload: progressHandler
                        )
                    }

                    guard let loadedModel else { throw MelangeRuntimeError.modelNotInitialized }
                    self.model = loadedModel
                    self.selectedExecutionPath = executionPath
                    self.selectedModelDescriptor = candidate.descriptor

                    if candidate.id != config.chronosModelID || candidate.version != config.chronosModelVersion {
                        SumiInferenceLog.event(service: "Trend", action: "Switched to accessible model candidate", level: .warning, metadata: ["candidate": candidate.descriptor])
                    }
                    SumiInferenceLog.event(
                        service: "Trend",
                        action: "Model ready",
                        metadata: [
                            "candidate": candidate.descriptor,
                            "executionPath": executionPath,
                            "candidateElapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: candidateStart))",
                            "totalElapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: loadStart))"
                        ]
                    )
                    return true
                } catch {
                    lastError = error
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    SumiInferenceLog.event(
                        service: "Trend",
                        action: "Model candidate failed",
                        level: .warning,
                        metadata: [
                            "candidate": candidate.descriptor,
                            "error": SumiInferenceLog.truncate(detail, limit: 220)
                        ]
                    )
                }
            }

            throw ChronosModelLoadError.noAccessibleModel(
                attemptedDescriptors: candidates.map(\.descriptor),
                underlying: lastError
            )
        }
    }

    private func chronosCandidates() -> [ChronosModelCandidate] {
        var unique: [ChronosModelCandidate] = []

        func appendCandidate(_ id: String, _ version: Int?) {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else { return }
            let candidate = ChronosModelCandidate(id: trimmedID, version: version)
            if !unique.contains(candidate) {
                unique.append(candidate)
            }
        }

        appendCandidate(config.chronosModelID, config.chronosModelVersion)
        appendCandidate(config.chronosModelID, nil)

        // Official/public Chronos IDs seen across docs/samples.
        appendCandidate("palm/chronos-bolt-tiny", 3)
        appendCandidate("palm/chronos-bolt-tiny", nil)
        appendCandidate("Team_ZETIC/Chronos-balt-tiny", 5)
        appendCandidate("Team_ZETIC/Chronos-balt-tiny", nil)

        return unique
    }

    private var preferCoreMLTargets: Bool {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["ZETIC_PREFER_COREML_TARGETS"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        let normalized = raw.lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
    }

    private var preferredCoreMLTargets: [Target] {
        [
            .ZETIC_MLANGE_TARGET_COREML_QUANT,
            .ZETIC_MLANGE_TARGET_COREML,
            .ZETIC_MLANGE_TARGET_COREML_FP32
        ]
    }

    private func targetDescriptor(_ target: Target) -> String {
        switch target {
        case .ZETIC_MLANGE_TARGET_COREML_QUANT:
            return "COREML_QUANT"
        case .ZETIC_MLANGE_TARGET_COREML:
            return "COREML"
        case .ZETIC_MLANGE_TARGET_COREML_FP32:
            return "COREML_FP32"
        default:
            return String(describing: target)
        }
    }

    private func runInferenceWithTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () throws -> T
    ) async throws -> T {
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Trend",
            action: "Queued inference operation",
            metadata: ["callID": String(callID), "timeoutSec": "\(Int(seconds))"]
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let lock = NSLock()
            var isResolved = false

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
                            service: "Trend",
                            action: "Inference operation completed",
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
                            service: "Trend",
                            action: "Inference operation failed",
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
                let didTimeout = resolve(.failure(MelangeRuntimeError.inferenceTimeout))
                guard didTimeout else { return }
                SumiInferenceLog.event(
                    service: "Trend",
                    action: "Inference timed out",
                    level: .warning,
                    metadata: [
                        "callID": String(callID),
                        "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
                    ]
                )
            }
        }
    }

    private func makeContextTensor(values: [Float]) -> Tensor {
        var padded = Array(repeating: Float.nan, count: contextLength)

        if values.count >= contextLength {
            let suffix = values.suffix(contextLength)
            for (index, value) in suffix.enumerated() {
                padded[index] = value
            }
        } else {
            let offset = contextLength - values.count
            for (index, value) in values.enumerated() {
                padded[offset + index] = value
            }
        }

        let data = padded.withUnsafeBufferPointer { Data(buffer: $0) }
        return Tensor(data: data, dataType: BuiltinDataType.float32, shape: [1, contextLength])
    }

    private func parseMedianForecast(from tensor: Tensor) throws -> [Float] {
        let values = tensor.data.withUnsafeBytes { rawBuffer -> [Float] in
            let typed = rawBuffer.bindMemory(to: Float.self)
            return Array(typed)
        }

        guard !values.isEmpty else { throw MelangeRuntimeError.invalidModelOutput }

        let quantileCount = 9
        let horizon = values.count / quantileCount
        guard horizon > 0 else { throw MelangeRuntimeError.invalidModelOutput }

        let medianIndex = 4
        let start = medianIndex * horizon
        let end = start + horizon

        guard end <= values.count else { throw MelangeRuntimeError.invalidModelOutput }
        return Array(values[start..<end])
    }
    #endif

    private func instabilityScore(for metric: WellnessMetricPoint) -> Float {
        let sleepPenalty = Float(max(0, 7.5 - metric.sleepHours) * 1.05)
        let stressPenalty = Float(metric.stressScore * 0.95)
        let cravingPenalty = Float(metric.cravingScore * 1.15)
        let moodPenalty = Float(max(0, 6.5 - metric.moodScore) * 0.8)
        let energyPenalty = Float(max(0, 6.3 - metric.energyScore) * 0.65)
        return (sleepPenalty + stressPenalty + cravingPenalty + moodPenalty + energyPenalty) / 4.6
    }

    private func adjustedDirection(base: TrendDirection, drift: Double) -> TrendDirection {
        switch (base, drift) {
        case (_, let d) where d > 0.35:
            return .worsening
        case (_, let d) where d < -0.3:
            return .improving
        case (.worsening, _), (.improving, _), (.stable, _), (.mixed, _):
            return base
        }
    }

    private func summarize(direction: TrendDirection, drift: Double) -> String {
        switch direction {
        case .worsening:
            return "Chronos and your recent baseline both indicate a less stable pattern with elevated stress-linked drift."
        case .improving:
            return "Chronos suggests your next week may stabilize relative to your recent baseline."
        case .mixed:
            return "Chronos projects mixed movement: some recovery signals, but instability remains above baseline."
        case .stable:
            if abs(drift) < 0.2 {
                return "Chronos projection is close to baseline, with no strong stability shift expected short-term."
            }
            return "Chronos shows limited drift and mostly stable short-horizon patterning."
        }
    }
}

#if canImport(ZeticMLange)
private struct ChronosModelCandidate: Equatable {
    let id: String
    let version: Int?

    var descriptor: String {
        if let version {
            return "\(id)@v\(version)"
        }
        return "\(id)@latest"
    }
}

private enum ChronosModelLoadError: LocalizedError {
    case noAccessibleModel(attemptedDescriptors: [String], underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .noAccessibleModel(let attemptedDescriptors, let underlying):
            let attempted = attemptedDescriptors.joined(separator: ", ")
            let detail = (underlying as? LocalizedError)?.errorDescription ?? underlying?.localizedDescription ?? "unknown error"
            return "Chronos model access failed for: \(attempted). Last error: \(detail)"
        }
    }
}
#endif
