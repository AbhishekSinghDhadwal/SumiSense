import SwiftUI

struct SumiLogoMark: View {
    var size: CGFloat = 64
    var withBackground: Bool = true

    var body: some View {
        ZStack {
            if withBackground {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [SumiPalette.accent.opacity(0.95), SumiPalette.accentSoft.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Circle()
                .trim(from: 0.08, to: 0.83)
                .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                .rotationEffect(.degrees(-14))
                .padding(size * 0.15)

            Circle()
                .trim(from: 0.28, to: 0.95)
                .stroke(Color.white.opacity(0.64), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                .rotationEffect(.degrees(22))
                .padding(size * 0.24)

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(y: size * 0.03)
        }
        .frame(width: size, height: size)
        .shadow(color: SumiPalette.accent.opacity(0.28), radius: size * 0.14, x: 0, y: size * 0.08)
        .accessibilityLabel("SumiSense logo")
    }
}

struct SumiBrandLockup: View {
    var title: String = "Sumi Sense"
    var subtitle: String = "Private pattern awareness"
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            SumiLogoMark(size: compact ? 34 : 54)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(title)
                    .font(compact ? SumiTypography.bodyEmphasis : SumiTypography.section)
                    .foregroundStyle(SumiPalette.textPrimary)

                Text(subtitle)
                    .font(compact ? SumiTypography.micro : SumiTypography.caption)
                    .foregroundStyle(SumiPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SumiBrandLockup(title: "Sumi Sense", subtitle: "(숨 -Sense)")
        .padding()
}
