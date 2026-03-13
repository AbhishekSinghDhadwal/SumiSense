import Foundation

enum SumiInferenceLogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
}

enum SumiInferenceLog {
    private static let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()
    private static let formatterLock = NSLock()

    static var verboseEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["SUMISENSE_VERBOSE_LOGS"]?.lowercased()
        if let env, ["0", "false", "off", "no"].contains(env) {
            return false
        }
        return true
    }

    static func event(
        service: String,
        action: String,
        level: SumiInferenceLogLevel = .info,
        metadata: [String: String] = [:]
    ) {
        guard verboseEnabled else { return }
        formatterLock.lock()
        let timestamp = formatter.string(from: Date())
        formatterLock.unlock()
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if metadataText.isEmpty {
            print("[SumiSense][Inference][\(service)][\(level.rawValue)][\(timestamp)] \(action)")
        } else {
            print("[SumiSense][Inference][\(service)][\(level.rawValue)][\(timestamp)] \(action) \(metadataText)")
        }
    }

    static func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    static func truncate(_ text: String, limit: Int) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        if cleaned.count <= limit { return cleaned }
        return String(cleaned.prefix(limit)) + "..."
    }
}
