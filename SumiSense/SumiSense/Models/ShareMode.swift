import Foundation

enum ShareMode: String, Codable, CaseIterable, Identifiable {
    case personal
    case clinician
    case researchSafe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal:
            return "Personal"
        case .clinician:
            return "Clinician"
        case .researchSafe:
            return "Research-safe"
        }
    }

    var helperText: String {
        switch self {
        case .personal:
            return "Keeps your original context with light cleanup."
        case .clinician:
            return "Keeps key symptoms in a concise clinical-style summary."
        case .researchSafe:
            return "Aggressively removes identifiers for safer sharing."
        }
    }
}
