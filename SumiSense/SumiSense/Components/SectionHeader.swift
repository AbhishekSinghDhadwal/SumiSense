import SwiftUI

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(SumiPalette.accent.opacity(0.88))
                    .frame(width: 26, height: 5)

                Text(title)
                    .font(SumiTypography.section)
                    .foregroundStyle(SumiPalette.textPrimary)
            }

            Text(subtitle)
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
