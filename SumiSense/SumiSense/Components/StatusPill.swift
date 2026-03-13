import SwiftUI

struct StatusPill: View {
    let status: SignalState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.title)
                .font(SumiTypography.caption)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.14), in: Capsule())
    }
}

#Preview {
    StatusPill(status: .watch)
}
