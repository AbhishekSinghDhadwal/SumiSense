import SwiftUI

struct RedactionComparisonView: View {
    let source: String
    let output: String

    var body: some View {
        VStack(spacing: SumiSpacing.md) {
            VStack(alignment: .leading, spacing: SumiSpacing.xs) {
                Text("Before")
                    .font(SumiTypography.caption)
                    .foregroundStyle(SumiPalette.textSecondary)
                Text(source)
                    .font(SumiTypography.body)
                    .foregroundStyle(SumiPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SumiSpacing.sm)
                    .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: SumiSpacing.xs) {
                Text("After")
                    .font(SumiTypography.caption)
                    .foregroundStyle(SumiPalette.textSecondary)
                Text(stylizedOutput)
                    .font(SumiTypography.bodyEmphasis)
                    .foregroundStyle(SumiPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SumiSpacing.sm)
                    .background(SumiPalette.accentSoft.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var stylizedOutput: AttributedString {
        var attributed = AttributedString(output)
        var searchStart = attributed.startIndex

        while searchStart < attributed.endIndex,
              let start = attributed[searchStart...].range(of: "[") {
            guard let end = attributed[start.upperBound...].range(of: "]") else { break }
            let tokenRange = start.lowerBound..<end.upperBound
            attributed[tokenRange].foregroundColor = SumiPalette.accent
            attributed[tokenRange].font = SumiTypography.bodyEmphasis
            searchStart = end.upperBound
        }
        return attributed
    }
}
