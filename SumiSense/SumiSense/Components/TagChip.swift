import SwiftUI

struct TagChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(SumiTypography.micro)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(SumiPalette.textSecondary)
            .background(SumiPalette.accentSoft.opacity(0.5), in: Capsule())
    }
}

#Preview {
    TagChip(label: "sleep disruption")
}
