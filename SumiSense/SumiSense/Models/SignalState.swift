import Foundation

enum SignalState: String, Codable, CaseIterable {
    case stable
    case watch
    case elevated

    var title: String {
        switch self {
        case .stable:
            return "Stable"
        case .watch:
            return "Watch"
        case .elevated:
            return "Elevated"
        }
    }

    var shortDescription: String {
        switch self {
        case .stable:
            return "Patterns are near your baseline."
        case .watch:
            return "Some elevated signals are present."
        case .elevated:
            return "Multiple elevated signals detected."
        }
    }
}
