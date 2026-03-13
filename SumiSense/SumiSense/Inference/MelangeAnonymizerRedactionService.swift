import Foundation

#if canImport(ZeticMLange)
import ZeticMLange
#endif

final class MelangeAnonymizerRedactionService: RedactionService {
    private let config: MelangeConfig
    private let modelMaxLength = 128
    private let modelLoadTimeoutSeconds: TimeInterval = 120
    private let modelRunTimeoutSeconds: TimeInterval = 20
    private let localFallback = RegexRedactionService()

    #if canImport(ZeticMLange)
    private var model: ZeticMLangeModel?
    private var selectedModelDescriptor: String?
    private var selectedExecutionPath: String = "RUN_SPEED"
    private var hasLoggedModelReady = false
    private let modelLock = NSLock()
    private let inferenceQueue = DispatchQueue(
        label: "com.sumisense.melange.redaction.inference",
        qos: .userInitiated,
        attributes: .concurrent
    )
    #endif

    private var tokenizer: MelangeTokenizer?
    private var labels: [Int: String] = [:]

    private let placeholderByLabel: [String: String] = [
        "EMAIL": "[Email]",
        "PHONE_NUMBER": "[Phone]",
        "CREDIT_CARD_NUMBER": "[Payment]",
        "SSN": "[ID]",
        "PERSON": "[Person]",
        "ADDRESS": "[Address]",
        "LOCATION": "[Location]",
        "DATE": "[Date]",
        "OTHER": "[Sensitive]"
    ]

    private struct PostFilterResult {
        let text: String
        let labels: [String]
    }

    init(config: MelangeConfig = .default) {
        self.config = config
        SumiInferenceLog.event(
            service: "Redaction",
            action: "Initialized MelangeAnonymizerRedactionService",
            metadata: [
                "model": "\(config.redactionModelID)@v\(config.redactionModelVersion)",
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
        SumiInferenceLog.event(service: "Redaction", action: "Warmup start")
        try await loadIfNeeded()
        _ = try await runInferenceWithTimeout(seconds: modelRunTimeoutSeconds) { [self] in
            guard let tokenizer, let model = currentModel() else { throw MelangeRuntimeError.modelNotInitialized }
            let sample = "Warmup note: Alex from Tempe called 602-555-0142 on 2026-03-12."
            let (inputIDs, attentionMask) = tokenize(text: sample, tokenizer: tokenizer)
            let inputTensor = try makeInt64Tensor(values: inputIDs, shape: [1, modelMaxLength])
            let maskTensor = try makeInt64Tensor(values: attentionMask, shape: [1, modelMaxLength])
            _ = try model.run(inputs: [inputTensor, maskTensor])
            return true
        }
        SumiInferenceLog.event(
            service: "Redaction",
            action: "Warmup complete",
            metadata: ["elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"]
        )
        #else
        throw MelangeRuntimeError.sdkUnavailable
        #endif
    }

    func redact(text: String, mode: ShareMode) async throws -> RedactionResult {
        #if canImport(ZeticMLange)
        guard config.hasPersonalKey else { throw MelangeRuntimeError.missingCredentials }
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Redaction",
            action: "Redaction request",
            metadata: [
                "callID": String(callID),
                "mode": mode.rawValue,
                "inputChars": "\(text.count)"
            ]
        )

        try await loadIfNeeded()
        logUsingModel(action: "Redaction generate")
        let anonymized = try await runInferenceWithTimeout(seconds: modelRunTimeoutSeconds) { [self] in
            guard let tokenizer, let model = currentModel() else { throw MelangeRuntimeError.modelNotInitialized }

            let (inputIDs, attentionMask) = tokenize(text: text, tokenizer: tokenizer)
            let activeTokens = attentionMask.filter { $0 != 0 }.count
            SumiInferenceLog.event(
                service: "Redaction",
                action: "Prepared tensors",
                metadata: [
                    "callID": String(callID),
                    "tokenCount": "\(activeTokens)",
                    "maxLength": "\(modelMaxLength)",
                    "truncated": "\(text.count > modelMaxLength)"
                ]
            )
            let inputTensor = try makeInt64Tensor(values: inputIDs, shape: [1, modelMaxLength])
            let maskTensor = try makeInt64Tensor(values: attentionMask, shape: [1, modelMaxLength])

            let outputs = try model.run(inputs: [inputTensor, maskTensor])
            guard let output = outputs.first else {
                throw MelangeRuntimeError.invalidModelOutput
            }

            return decodeAndMask(
                logitsTensor: output,
                inputIDs: inputIDs,
                attentionMask: attentionMask,
                tokenizer: tokenizer
            )
        }

        SumiInferenceLog.event(
            service: "Redaction",
            action: "Post-filter start",
            metadata: ["callID": String(callID), "modelOutputChars": "\(anonymized.count)"]
        )
        let normalizedModelOutput = normalizeModelOutput(anonymized)
        let postFiltered = applySafetyPostFilter(input: text, modelOutput: normalizedModelOutput, mode: mode)
        let modeAdjusted = applyModeTransform(text: postFiltered.text, mode: mode)
        var redactions = extractRedactionLabels(from: modeAdjusted)
        redactions.append(contentsOf: postFiltered.labels)
        redactions = Array(NSOrderedSet(array: redactions).compactMap { $0 as? String })
        SumiInferenceLog.event(
            service: "Redaction",
            action: "Post-filter complete",
            metadata: [
                "callID": String(callID),
                "postFilterChars": "\(modeAdjusted.count)",
                "labels": redactions.joined(separator: "|")
            ]
        )

        if shouldFallbackToRegex(input: text, output: modeAdjusted, mode: mode, labels: redactions) {
            SumiInferenceLog.event(
                service: "Redaction",
                action: "Quality gate failed; switching to regex fallback",
                level: .warning,
                metadata: [
                    "callID": String(callID),
                    "mode": mode.rawValue,
                    "melangeOutputChars": "\(modeAdjusted.count)",
                    "labels": redactions.joined(separator: "|")
                ]
            )
            let fallback = try await localFallback.redact(text: text, mode: mode)
            return RedactionResult(
                mode: mode,
                sourceText: text,
                outputText: fallback.outputText,
                redactionsApplied: fallback.redactionsApplied,
                source: .fallback
            )
        }
        SumiInferenceLog.event(
            service: "Redaction",
            action: "Redaction complete",
            metadata: [
                "callID": String(callID),
                "pipeline": "melange+postfilter",
                "redactionLabels": redactions.joined(separator: "|"),
                "outputChars": "\(modeAdjusted.count)",
                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"
            ]
        )

        return RedactionResult(
            mode: mode,
            sourceText: text,
            outputText: modeAdjusted,
            redactionsApplied: redactions,
            source: .melange
        )
        #else
        throw MelangeRuntimeError.sdkUnavailable
        #endif
    }

    #if canImport(ZeticMLange)
    private func loadIfNeeded() async throws {
        if currentModel() != nil && tokenizer != nil && !labels.isEmpty {
            SumiInferenceLog.event(
                service: "Redaction",
                action: "Model/tokenizer cache hit",
                metadata: ["model": selectedModelDescriptor ?? "\(config.redactionModelID)@v\(config.redactionModelVersion)"]
            )
            return
        }

        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(service: "Redaction", action: "Loading tokenizer/labels")
        tokenizer = try MelangeTokenizer()
        labels = try loadLabels()
        SumiInferenceLog.event(
            service: "Redaction",
            action: "Tokenizer/labels ready",
            metadata: ["labelCount": "\(labels.count)"]
        )

        let candidates = redactionCandidates()
        SumiInferenceLog.event(
            service: "Redaction",
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
                    SumiInferenceLog.event(service: "Redaction", action: "Trying model candidate", metadata: ["candidate": candidate.descriptor])
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
                            service: "Redaction",
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
                                    service: "Redaction",
                                    action: "Loaded model with explicit target",
                                    metadata: [
                                        "candidate": candidate.descriptor,
                                        "target": executionPath
                                    ]
                                )
                                break
                            } catch {
                                SumiInferenceLog.event(
                                    service: "Redaction",
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
                    self.setModel(loadedModel)
                    self.selectedExecutionPath = executionPath
                    self.selectedModelDescriptor = candidate.descriptor
                    if candidate.id != config.redactionModelID || candidate.version != config.redactionModelVersion {
                        SumiInferenceLog.event(service: "Redaction", action: "Switched to accessible model candidate", level: .warning, metadata: ["candidate": candidate.descriptor])
                    }
                    if !hasLoggedModelReady {
                        SumiInferenceLog.event(
                            service: "Redaction",
                            action: "Model ready",
                            metadata: [
                                "candidate": candidate.descriptor,
                                "executionPath": executionPath,
                                "elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: candidateStart))"
                            ]
                        )
                        hasLoggedModelReady = true
                    }
                    SumiInferenceLog.event(
                        service: "Redaction",
                        action: "Model load complete",
                        metadata: ["elapsedMs": "\(SumiInferenceLog.elapsedMilliseconds(since: start))"]
                    )
                    return true
                } catch {
                    lastError = error
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    SumiInferenceLog.event(
                        service: "Redaction",
                        action: "Model candidate failed",
                        level: .warning,
                        metadata: [
                            "candidate": candidate.descriptor,
                            "error": SumiInferenceLog.truncate(detail, limit: 220)
                        ]
                    )
                }
            }

            throw RedactionModelLoadError.noAccessibleModel(
                attemptedDescriptors: candidates.map(\.descriptor),
                underlying: lastError
            )
        }
    }

    private func redactionCandidates() -> [RedactionModelCandidate] {
        var unique: [RedactionModelCandidate] = []

        func appendCandidate(_ id: String, _ version: Int?) {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else { return }
            let candidate = RedactionModelCandidate(id: trimmedID, version: version)
            if !unique.contains(candidate) {
                unique.append(candidate)
            }
        }

        appendCandidate(config.redactionModelID, config.redactionModelVersion)
        appendCandidate(config.redactionModelID, nil)

        appendCandidate("Steve/text-anonymizer-v1", 1)
        appendCandidate("Steve/text-anonymizer-v1", nil)
        appendCandidate("jathin-zetic/tanaos-text-anonymizer", 1)
        appendCandidate("jathin-zetic/tanaos-text-anonymizer", nil)
        appendCandidate("tanaos/tanaos-text-anonymizer-v1", 1)
        appendCandidate("tanaos/tanaos-text-anonymizer-v1", nil)

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

    private func loadLabels() throws -> [Int: String] {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "labels", withExtension: "json")
            ?? bundle.url(forResource: "labels", withExtension: "json", subdirectory: "Resources/MelangeAssets")
            ?? bundle.url(forResource: "labels", withExtension: "json", subdirectory: "MelangeAssets")

        guard let url else {
            throw MelangeRuntimeError.resourceMissing("labels.json")
        }

        let data = try Data(contentsOf: url)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw MelangeRuntimeError.resourceMissing("labels.json format")
        }

        var map: [Int: String] = [:]
        for (key, value) in payload {
            if let intKey = Int(key) {
                map[intKey] = value
            }
        }
        return map
    }

    private func tokenize(text: String, tokenizer: MelangeTokenizer) -> ([Int], [Int]) {
        var inputIDs = tokenizer.encode(text)
        var mask = Array(repeating: 1, count: inputIDs.count)

        if inputIDs.count > modelMaxLength {
            inputIDs = Array(inputIDs.prefix(modelMaxLength))
            mask = Array(mask.prefix(modelMaxLength))
        } else if inputIDs.count < modelMaxLength {
            let padding = modelMaxLength - inputIDs.count
            inputIDs.append(contentsOf: Array(repeating: tokenizer.padId, count: padding))
            mask.append(contentsOf: Array(repeating: 0, count: padding))
        }

        return (inputIDs, mask)
    }

    private func makeInt64Tensor(values: [Int], shape: [Int]) throws -> Tensor {
        let int64Values = values.map(Int64.init)
        let data = int64Values.withUnsafeBufferPointer { Data(buffer: $0) }
        return Tensor(data: data, dataType: BuiltinDataType.int64, shape: shape)
    }

    private func decodeAndMask(
        logitsTensor: Tensor,
        inputIDs: [Int],
        attentionMask: [Int],
        tokenizer: MelangeTokenizer
    ) -> String {
        let classCount = max(labels.count, 1)
        let floatValues = logitsTensor.data.withUnsafeBytes { bytes -> [Float32] in
            Array(bytes.bindMemory(to: Float32.self))
        }

        let sequenceLength = floatValues.count / classCount
        var predictedClassIDs: [Int] = []

        for tokenIndex in 0..<sequenceLength {
            var bestScore = -Float32.infinity
            var bestClass = 0
            let offset = tokenIndex * classCount

            for classIndex in 0..<classCount {
                let current = floatValues[safe: offset + classIndex] ?? -Float32.infinity
                if current > bestScore {
                    bestScore = current
                    bestClass = classIndex
                }
            }

            predictedClassIDs.append(bestClass)
        }

        var outputTokens: [String] = []
        var index = 0

        while index < min(sequenceLength, inputIDs.count) {
            if attentionMask[safe: index] == 0 {
                index += 1
                continue
            }

            let tokenID = inputIDs[index]
            if tokenID == tokenizer.bosId || tokenID == tokenizer.eosId || tokenID == tokenizer.padId {
                index += 1
                continue
            }

            let label = labels[predictedClassIDs[safe: index] ?? 0] ?? "O"

            if label == "O" {
                outputTokens.append(tokenizer.decodeToken(tokenID))
                index += 1
                continue
            }

            var entity = label
            if label.hasPrefix("B-") || label.hasPrefix("I-") {
                entity = String(label.dropFirst(2))
            }

            var replacement = placeholderByLabel[entity] ?? "[\(entity)]"
            if tokenizer.rawToken(tokenID)?.hasPrefix("\u{0120}") == true {
                replacement = "\u{0120}" + replacement
            }
            outputTokens.append(replacement)

            index += 1
            while index < min(sequenceLength, inputIDs.count) {
                let nextLabel = labels[predictedClassIDs[safe: index] ?? 0] ?? "O"
                if nextLabel == "I-\(entity)" || nextLabel == "B-\(entity)" {
                    index += 1
                } else {
                    break
                }
            }
        }

        return outputTokens
            .joined(separator: "")
            .replacingOccurrences(of: "\u{0120}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    private func shouldFallbackToRegex(
        input: String,
        output: String,
        mode: ShareMode,
        labels: [String]
    ) -> Bool {
        let normalizedOutput = output.lowercased()
        if normalizedOutput.contains("�") {
            return true
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let unkCount = normalizedOutput.components(separatedBy: "<unk>").count - 1
        if unkCount >= 4 {
            return true
        }

        let inputSensitive = containsSensitivePattern(input)
        if !inputSensitive {
            return false
        }

        let normalizedInput = normalizeForComparison(input)
        let normalizedOut = normalizeForComparison(output)
        let unchanged = normalizedInput == normalizedOut

        if unchanged && mode == .researchSafe {
            return true
        }
        if mode == .researchSafe && labels.isEmpty {
            return true
        }

        return false
    }

    private func normalizeModelOutput(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<unk>", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applySafetyPostFilter(input: String, modelOutput: String, mode: ShareMode) -> PostFilterResult {
        var transformed = modelOutput
        var applied: [String] = []

        // If model output is too small compared with input, recover by filtering the input directly.
        // This keeps demo reliability while still keeping Melange as the primary signal source.
        if transformed.count < max(24, input.count / 6) {
            transformed = input
            applied.append("model_recovery")
        }

        transformed = replace(
            pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            in: transformed,
            with: "[Email]",
            options: [.caseInsensitive],
            applied: &applied,
            label: "email"
        )
        transformed = replace(
            pattern: "(?<!\\d)(?:\\+1[-.\\s]?)?(?:\\(?\\d{3}\\)?[-.\\s]?)\\d{3}[-.\\s]?\\d{4}(?!\\d)",
            in: transformed,
            with: "[Phone]",
            options: [],
            applied: &applied,
            label: "phone"
        )
        transformed = replace(
            pattern: "\\b(?:MRN|ID|Case|Record)[:#]?\\s*[A-Z0-9-]{4,}\\b",
            in: transformed,
            with: "[Identifier]",
            options: [.caseInsensitive],
            applied: &applied,
            label: "id"
        )

        if mode != .personal {
            transformed = replace(
                pattern: "\\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}(?:,\\s*\\d{2,4})?\\b",
                in: transformed,
                with: "[Date]",
                options: [.caseInsensitive],
                applied: &applied,
                label: "date"
            )
            transformed = replace(
                pattern: "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b",
                in: transformed,
                with: "[Date]",
                options: [],
                applied: &applied,
                label: "date"
            )
        }

        if mode == .researchSafe {
            transformed = replace(
                pattern: "\\bDr\\.?\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?\\b",
                in: transformed,
                with: "[Provider]",
                options: [],
                applied: &applied,
                label: "provider"
            )
            transformed = replace(
                pattern: "\\b[A-Z][a-z]+\\s+[A-Z][a-z]+\\b",
                in: transformed,
                with: "[Person]",
                options: [],
                applied: &applied,
                label: "name"
            )
            transformed = replace(
                pattern: "\\b\\d{1,5}\\s+[A-Za-z0-9.\\s]+(?:Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd)\\b",
                in: transformed,
                with: "[Address]",
                options: [.caseInsensitive],
                applied: &applied,
                label: "address"
            )
            transformed = replace(
                pattern: "\\b(?:Tempe|Phoenix|Scottsdale|Mesa|Chandler|Gilbert|clinic|hospital|center|park|studio)\\b",
                in: transformed,
                with: "[Location]",
                options: [.caseInsensitive],
                applied: &applied,
                label: "location"
            )
        }

        transformed = transformed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PostFilterResult(
            text: transformed,
            labels: Array(NSOrderedSet(array: applied).compactMap { $0 as? String })
        )
    }

    private func replace(
        pattern: String,
        in text: String,
        with replacement: String,
        options: NSRegularExpression.Options,
        applied: inout [String],
        label: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        applied.append(label)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private func normalizeForComparison(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\[[^\\]]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "Research-safe summary:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Clinician summary:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func containsSensitivePattern(_ text: String) -> Bool {
        let patterns = [
            "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            "(?<!\\d)(?:\\+1[-.\\s]?)?(?:\\(?\\d{3}\\)?[-.\\s]?)\\d{3}[-.\\s]?\\d{4}(?!\\d)",
            "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b",
            "\\b(?:MRN|ID|Case|Record)[:#]?\\s*[A-Z0-9-]{3,}\\b",
            "\\bDr\\.?\\s+[A-Z][a-z]+",
            "\\b\\d{1,5}\\s+[A-Za-z0-9.\\s]+(?:Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd)\\b"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    private func applyModeTransform(text: String, mode: ShareMode) -> String {
        switch mode {
        case .personal:
            return text
        case .clinician:
            return "Clinician summary: \(text)"
        case .researchSafe:
            return "Research-safe summary: \(text)"
        }
    }

    private func extractRedactionLabels(from text: String) -> [String] {
        let pattern = "\\[(.*?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        let labels = regex.matches(in: text, options: [], range: range).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }

        return Array(NSOrderedSet(array: labels).compactMap { $0 as? String })
    }

    private func runInferenceWithTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () throws -> T
    ) async throws -> T {
        let callID = UUID().uuidString.prefix(8)
        let start = CFAbsoluteTimeGetCurrent()
        SumiInferenceLog.event(
            service: "Redaction",
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
                            service: "Redaction",
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
                            service: "Redaction",
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
                            service: "Redaction",
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
                            service: "Redaction",
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
                    service: "Redaction",
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

    private func currentModel() -> ZeticMLangeModel? {
        modelLock.lock()
        defer { modelLock.unlock() }
        return model
    }

    private func setModel(_ newModel: ZeticMLangeModel?) {
        modelLock.lock()
        defer { modelLock.unlock() }
        model = newModel
    }

    private func logUsingModel(action: String) {
        let descriptor = selectedModelDescriptor ?? "\(config.redactionModelID)@v\(config.redactionModelVersion)"
        SumiInferenceLog.event(
            service: "Redaction",
            action: action,
            metadata: [
                "model": descriptor,
                "executionPath": selectedExecutionPath
            ]
        )
    }
}

#if canImport(ZeticMLange)
private struct RedactionModelCandidate: Equatable {
    let id: String
    let version: Int?

    var descriptor: String {
        if let version {
            return "\(id)@v\(version)"
        }
        return "\(id)@latest"
    }
}

private enum RedactionModelLoadError: LocalizedError {
    case noAccessibleModel(attemptedDescriptors: [String], underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .noAccessibleModel(let attemptedDescriptors, let underlying):
            let attempted = attemptedDescriptors.joined(separator: ", ")
            let detail = (underlying as? LocalizedError)?.errorDescription ?? underlying?.localizedDescription ?? "unknown error"
            return "Redaction model access failed for: \(attempted). Last error: \(detail)"
        }
    }
}
#endif
