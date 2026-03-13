import Foundation

struct MelangeConfig {
    // TODO: Replace scheme environment values with secure credential flow for production.
    let personalKey: String
    let personalKeySource: String

    // TODO: Replace defaults with dashboard-provisioned model IDs/versions used by your team.
    let chronosModelID: String
    let chronosModelVersion: Int

    let redactionModelID: String
    let redactionModelVersion: Int

    let journalModelID: String
    let journalModelVersion: Int?

    static let `default`: MelangeConfig = {
        let resolvedKey = resolvePersonalKey()
        let env = ProcessInfo.processInfo.environment
        let journalVersionRaw = env["ZETIC_JOURNAL_MODEL_VERSION"]
            ?? env["ZETIC_MEDGEMMA_MODEL_VERSION"]
            ?? env["ZETIC_QWEN_MODEL_VERSION"]

        return MelangeConfig(
            personalKey: resolvedKey.value,
            personalKeySource: resolvedKey.source,
            chronosModelID: env["ZETIC_CHRONOS_MODEL_ID"] ?? "Team_ZETIC/Chronos-balt-tiny",
            chronosModelVersion: Int(env["ZETIC_CHRONOS_MODEL_VERSION"] ?? "") ?? 5,
            redactionModelID: env["ZETIC_REDACTION_MODEL_ID"] ?? "Steve/text-anonymizer-v1",
            redactionModelVersion: Int(env["ZETIC_REDACTION_MODEL_VERSION"] ?? "") ?? 1,
            journalModelID: env["ZETIC_JOURNAL_MODEL_ID"]
                ?? env["ZETIC_MEDGEMMA_MODEL_ID"]
                ?? env["ZETIC_QWEN_MODEL_ID"]
                ?? "Qwen/Qwen3-4B",
            journalModelVersion: journalVersionRaw.flatMap { Int($0) }
        )
    }()

    var hasPersonalKey: Bool {
        !personalKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func resolvePersonalKey() -> (value: String, source: String) {
        let env = ProcessInfo.processInfo.environment
        if let key = normalizedKey(env["ZETIC_PERSONAL_KEY"]) {
            return (key, "environment:ZETIC_PERSONAL_KEY")
        }
        if let key = normalizedKey(env["ZETIC_ACCESS_TOKEN"]) {
            return (key, "environment:ZETIC_ACCESS_TOKEN")
        }
        if let key = normalizedKey(env["ZETIC_TOKEN_KEY"]) {
            return (key, "environment:ZETIC_TOKEN_KEY")
        }
        if let key = normalizedKey(env["MELANGE_PERSONAL_KEY"]) {
            return (key, "environment:MELANGE_PERSONAL_KEY")
        }

        if let key = normalizedKey(UserDefaults.standard.string(forKey: "ZETIC_PERSONAL_KEY")) {
            return (key, "userdefaults:ZETIC_PERSONAL_KEY")
        }
        if let key = normalizedKey(UserDefaults.standard.string(forKey: "ZETIC_ACCESS_TOKEN")) {
            return (key, "userdefaults:ZETIC_ACCESS_TOKEN")
        }
        if let key = normalizedKey(UserDefaults.standard.string(forKey: "MELANGE_PERSONAL_KEY")) {
            return (key, "userdefaults:MELANGE_PERSONAL_KEY")
        }
        if let key = normalizedKey(UserDefaults.standard.string(forKey: "sumi_zetic_personal_key")) {
            return (key, "userdefaults:sumi_zetic_personal_key")
        }

        if let key = Bundle.main.object(forInfoDictionaryKey: "ZETIC_PERSONAL_KEY") as? String,
           let trimmed = normalizedKey(key) {
            return (trimmed, "Info.plist:ZETIC_PERSONAL_KEY")
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "ZETIC_ACCESS_TOKEN") as? String,
           let trimmed = normalizedKey(key) {
            return (trimmed, "Info.plist:ZETIC_ACCESS_TOKEN")
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "MELANGE_PERSONAL_KEY") as? String,
           let trimmed = normalizedKey(key) {
            return (trimmed, "Info.plist:MELANGE_PERSONAL_KEY")
        }

        return ("", "missing")
    }

    private static func normalizedKey(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmedNonEmpty else {
            return nil
        }

        let normalized = trimmed.lowercased()
        let placeholders: Set<String> = [
            "your_mlange_key",
            "your_melange_key",
            "your_token_here",
            "your_personal_key"
        ]
        if placeholders.contains(normalized) {
            return nil
        }

        return trimmed
    }
}

enum MelangeAvailability {
    static var sdkAvailable: Bool {
        #if canImport(ZeticMLange)
        true
        #else
        false
        #endif
    }
}

enum MelangeRuntimeError: LocalizedError {
    case missingCredentials
    case sdkUnavailable
    case modelNotInitialized
    case resourceMissing(String)
    case invalidModelOutput
    case inferenceTimeout
    case unsupportedRuntime(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing Melange personal key. Configure ZETIC_PERSONAL_KEY or ZETIC_ACCESS_TOKEN."
        case .sdkUnavailable:
            return "Melange SDK is not available in this build environment."
        case .modelNotInitialized:
            return "Model is not initialized."
        case .resourceMissing(let name):
            return "Missing required resource: \(name)."
        case .invalidModelOutput:
            return "Model output shape was not recognized."
        case .inferenceTimeout:
            return "Model inference timed out."
        case .unsupportedRuntime(let detail):
            return detail
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
