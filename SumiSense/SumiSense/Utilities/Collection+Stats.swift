import Foundation

extension Collection where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        let total = reduce(0, +)
        return total / Double(count)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
