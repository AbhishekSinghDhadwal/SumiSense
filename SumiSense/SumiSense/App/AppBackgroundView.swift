import SwiftUI

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                SumiPalette.background,
                colorScheme == .dark ? SumiPalette.surface.opacity(0.42) : Color.white,
                SumiPalette.accentSoft.opacity(colorScheme == .dark ? 0.2 : 0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Circle()
                .fill(SumiPalette.accentSoft.opacity(colorScheme == .dark ? 0.2 : 0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 46)
                .offset(x: 132, y: -228)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.45),
                    lineWidth: 1
                )
                .padding(-20)
                .blur(radius: 8)
        }
        .ignoresSafeArea()
    }
}
