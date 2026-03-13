import Foundation

enum TrendDirection: String, Codable {
    case improving
    case stable
    case worsening
    case mixed

    var title: String {
        switch self {
        case .improving:
            return "Improving"
        case .stable:
            return "Stable"
        case .worsening:
            return "Worsening"
        case .mixed:
            return "Mixed"
        }
    }
}
