import SwiftUI

struct SumiCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(SumiSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.35),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08),
                radius: colorScheme == .dark ? 24 : 18,
                x: 0,
                y: 12
            )
    }
}

extension View {
    func sumiCard() -> some View {
        modifier(SumiCardModifier())
    }
}
