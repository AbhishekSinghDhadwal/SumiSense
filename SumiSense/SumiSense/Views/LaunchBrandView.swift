import SwiftUI

struct LaunchBrandView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: SumiSpacing.lg) {
                SumiLogoMark(size: 94)
                    .scaleEffect(animate ? 1 : 0.85)
                    .opacity(animate ? 1 : 0.2)

                VStack(spacing: 6) {
                    Text("Sumi Sense")
                        .font(SumiTypography.title)
                        .foregroundStyle(SumiPalette.textPrimary)
                    Text("(숨 -Sense)")
                        .font(SumiTypography.body)
                        .foregroundStyle(SumiPalette.textSecondary)
                }
                .offset(y: animate ? 0 : 10)
                .opacity(animate ? 1 : 0.2)
            }
        }
        .onAppear {
            withAnimation(SumiMotion.gentleSpring.delay(0.05)) {
                animate = true
            }
        }
    }
}

#Preview {
    LaunchBrandView()
}
