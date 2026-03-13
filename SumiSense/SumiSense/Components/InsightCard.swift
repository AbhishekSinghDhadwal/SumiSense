import SwiftUI

struct InsightCard: View {
    let assessment: DailySignalAssessment
    private var sanitizedAssessment: DailySignalAssessment {
        UserFacingTextSanitizer.sanitizeAssessment(assessment)
    }
    private var guardedSummary: String {
        let candidate = sanitizedAssessment.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = candidate.lowercased()
        let isPromptEcho =
            normalized.contains("status")
            && normalized.contains("stable")
            && normalized.contains("watch")
            && normalized.contains("elevated")
        if candidate.isEmpty || isPromptEcho {
            switch sanitizedAssessment.status {
            case .stable:
                return "Your note reflects a mostly stable pattern today."
            case .watch:
                return "Your note suggests a mild stability shift."
            case .elevated:
                return "Your note shows elevated signals relative to baseline."
            }
        }
        return candidate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            HStack {
                StatusPill(status: sanitizedAssessment.status)
                Spacer()
                Text(sanitizedAssessment.source == .melange ? "Melange" : "Fallback")
                    .font(SumiTypography.micro)
                    .foregroundStyle(SumiPalette.textSecondary)
            }

            Text(guardedSummary)
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            Text(sanitizedAssessment.explanation)
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !sanitizedAssessment.signalTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sanitizedAssessment.signalTags, id: \.self) { tag in
                            TagChip(label: tag)
                        }
                    }
                }
            }
        }
        .sumiCard()
    }
}
