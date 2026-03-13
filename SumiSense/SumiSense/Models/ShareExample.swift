import Foundation

struct ShareExample: Codable, Hashable {
    let mode: ShareMode
    let sourceText: String
    let expectedStyle: String
}
