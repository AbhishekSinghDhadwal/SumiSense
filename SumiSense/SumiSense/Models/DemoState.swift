import Foundation

struct DemoState: Codable, Hashable {
    var hasLoadedSeedData: Bool
    var isDemoMode: Bool
    var seedVersion: Int

    static let `default` = DemoState(
        hasLoadedSeedData: false,
        isDemoMode: true,
        seedVersion: 1
    )
}
