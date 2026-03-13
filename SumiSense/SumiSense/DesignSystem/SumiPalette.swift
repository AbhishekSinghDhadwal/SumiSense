import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SumiPalette {
    static let background = dynamic(light: "F5F6F3", dark: "101414")
    static let surface = dynamic(light: "FFFFFF", dark: "1A2020").opacity(0.78)

    static let accent = Color(hex: "1E8A7A")
    static let accentSoft = Color(hex: "CCEDE8")

    static let textPrimary = dynamic(light: "1A2A28", dark: "E7F1EF")
    static let textSecondary = dynamic(light: "5D6D6A", dark: "A7B9B6")

    static let stable = Color(hex: "3B9E73")
    static let watch = Color(hex: "D1902D")
    static let elevated = Color(hex: "C25757")

    private static func dynamic(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { traitCollection in
                UIColor(
                    hex: traitCollection.userInterfaceStyle == .dark ? dark : light
                )
            }
        )
        #else
        return Color(hex: light)
        #endif
    }
}

extension SignalState {
    var color: Color {
        switch self {
        case .stable:
            return SumiPalette.stable
        case .watch:
            return SumiPalette.watch
        case .elevated:
            return SumiPalette.elevated
        }
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let r, g, b: UInt64
        switch sanitized.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}
#endif
