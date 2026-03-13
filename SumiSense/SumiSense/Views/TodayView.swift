import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel: JournalViewModel
    @FocusState private var focusedField: ComposerField?
    @Environment(\.colorScheme) private var colorScheme

    init(appState: AppStateViewModel) {
        _viewModel = StateObject(wrappedValue: JournalViewModel(appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SumiSpacing.lg) {
                SumiBrandLockup(
                    title: "Sumi Sense",
                    subtitle: "(숨 -Sense)",
                    compact: true
                )

                SectionHeader(
                    title: "Today",
                    subtitle: "Capture a short check-in and surface a calm stability insight."
                )

                if let assessment = viewModel.latestAssessment {
                    InsightCard(assessment: assessment)
                        .transition(SumiMotion.fadeSlide)
                } else {
                    emptyInsightCard
                        .transition(.opacity)
                }

                composerCard

                if !viewModel.recentEntries.isEmpty {
                    VStack(alignment: .leading, spacing: SumiSpacing.sm) {
                        Text("Recent entries")
                            .font(SumiTypography.cardTitle)
                            .foregroundStyle(SumiPalette.textPrimary)

                        ForEach(viewModel.recentEntries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(SumiDate.short(entry.date))
                                        .font(SumiTypography.caption)
                                        .foregroundStyle(SumiPalette.textSecondary)
                                    Spacer()
                                    if let status = entry.generatedStatus {
                                        StatusPill(status: status)
                                    }
                                }

                                Text(entry.rawText)
                                    .font(SumiTypography.body)
                                    .foregroundStyle(SumiPalette.textPrimary)
                                    .lineLimit(3)
                            }
                            .sumiCard()
                        }
                    }
                }
            }
            .padding(SumiSpacing.lg)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedField = nil
            }
        )
    }

    private var emptyInsightCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("No analysis yet")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)
            Text("Write 1 to 3 sentences and tap Analyze. SumiSense will surface a private stability signal.")
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textSecondary)
        }
        .sumiCard()
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("Daily note")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SumiPalette.surface)

                TextEditor(text: $viewModel.noteDraft)
                    .scrollContentBackground(.hidden)
                    .padding(SumiSpacing.xs)
                    .frame(minHeight: 120)
                    .font(SumiTypography.body)
                    .foregroundColor(
                        colorScheme == .dark
                        ? Color(hex: "E7F1EF")
                        : Color(hex: "1A2A28")
                    )
                    .tint(SumiPalette.accent)
                    .opacity(1)
                    .focused($focusedField, equals: .note)

                if viewModel.noteDraft.isEmpty {
                    Text("Example: Barely slept last night, felt wired and isolated at work, and cravings were louder by evening.")
                        .font(SumiTypography.body)
                        .foregroundStyle(SumiPalette.textSecondary.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 120)

            VStack(alignment: .leading, spacing: 6) {
                Text("Optional focus tags")
                    .font(SumiTypography.caption)
                    .foregroundStyle(SumiPalette.textSecondary)
                TextField("Optional tags (for example: sleep, stress, isolation)", text: $viewModel.manualTagsText)
                    .textFieldStyle(.roundedBorder)
                    .font(SumiTypography.body)
                    .focused($focusedField, equals: .tags)
            }

            Button {
                withAnimation(SumiMotion.spring) {
                    viewModel.analyzeNote()
                    focusedField = nil
                }
            } label: {
                HStack {
                    if viewModel.isAnalyzing || viewModel.isPrewarmingModels {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(
                        viewModel.isPrewarmingModels
                        ? "Preparing on-device models..."
                        : (viewModel.isAnalyzing ? "Analyzing locally..." : "Analyze Entry")
                    )
                        .font(SumiTypography.bodyEmphasis)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(SumiPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.isAnalyzing || viewModel.isPrewarmingModels)

            if viewModel.isPrewarmingModels {
                Label("Downloading and preparing models in the background. First setup can take a minute.", systemImage: "arrow.down.circle")
                    .font(SumiTypography.micro)
                    .foregroundStyle(SumiPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let runtimeMessage = viewModel.runtimeMessage {
                Label(
                    runtimeMessage,
                    systemImage: runtimeMessage.lowercased().contains("active")
                    ? "checkmark.seal"
                    : "exclamationmark.triangle"
                )
                    .font(SumiTypography.micro)
                    .foregroundStyle(
                        runtimeMessage.lowercased().contains("active")
                        ? SumiPalette.accent
                        : SumiPalette.textSecondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sumiCard()
    }
}

private enum ComposerField: Hashable {
    case note
    case tags
}
