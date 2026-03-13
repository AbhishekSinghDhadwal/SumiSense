import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var currentPage = 0

    private let pages: [(title: String, subtitle: String, icon: String)] = [
        (
            "Private by default",
            "Your daily notes stay on-device for core analysis and sharing flows.",
            "lock.shield"
        ),
        (
            "On-device AI inference",
            "SumiSense runs local trend and redaction intelligence with Melange-ready services.",
            "cpu"
        ),
        (
            "Pattern awareness, not diagnosis",
            "This app surfaces stability shifts to support reflection. It does not diagnose or treat.",
            "heart.text.square"
        )
    ]

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: SumiSpacing.xl) {
                SumiBrandLockup(
                    title: "Sumi Sense",
                    subtitle: "(숨 -Sense)",
                    compact: false
                )
                .padding(.top, SumiSpacing.md)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: SumiSpacing.lg) {
                            Image(systemName: page.icon)
                                .font(.system(size: 46, weight: .medium))
                                .foregroundStyle(SumiPalette.accent)
                                .padding(20)
                                .background(SumiPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                            Text(page.title)
                                .font(SumiTypography.section)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(SumiPalette.textPrimary)

                            Text(page.subtitle)
                                .font(SumiTypography.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(SumiPalette.textSecondary)
                                .padding(.horizontal, SumiSpacing.xl)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 360)

                Button(action: advance) {
                    Text(currentPage == pages.count - 1 ? "Enter SumiSense" : "Continue")
                        .font(SumiTypography.bodyEmphasis)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SumiPalette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, SumiSpacing.xl)
            }
            .padding(.bottom, SumiSpacing.xxl)
        }
    }

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation(SumiMotion.gentleSpring) {
                currentPage += 1
            }
        } else {
            onFinish()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
