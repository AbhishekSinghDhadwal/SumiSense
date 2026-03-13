import Foundation

struct UserPreferences: Codable, Hashable {
    var id: UUID
    var displayName: String
    var baselineSensitivity: Double
    var preferredTrendWindow: Int
    var demoModeEnabled: Bool

    static let `default` = UserPreferences(
        id: UUID(),
        displayName: "Maya R.",
        baselineSensitivity: 0.6,
        preferredTrendWindow: 14,
        demoModeEnabled: true
    )
}
