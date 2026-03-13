import Foundation

enum ShareSourceSelection: String, Codable, CaseIterable, Identifiable {
    case selectedEntry
    case lastSevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedEntry:
            return "Single Entry"
        case .lastSevenDays:
            return "Last 7 Days"
        }
    }

    var helperText: String {
        switch self {
        case .selectedEntry:
            return "Share one journal entry with associated same-day wellness metrics."
        case .lastSevenDays:
            return "Share a 7-day digest of notes plus summarized wellness metrics."
        }
    }
}
