import SwiftUI

struct AboutView: View {
    @StateObject private var viewModel: AboutViewModel
    @Binding private var appTheme: AppTheme

    init(appState: AppStateViewModel, appTheme: Binding<AppTheme>) {
        _viewModel = StateObject(wrappedValue: AboutViewModel(appState: appState))
        _appTheme = appTheme
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SumiSpacing.lg) {
                SumiBrandLockup(
                    title: "Sumi Sense",
                    subtitle: "(숨 -Sense)",
                    compact: false
                )

                SectionHeader(
                    title: "About SumiSense",
                    subtitle: "On-device AI architecture with privacy-safe behavioral-health journaling."
                )

                appearanceCard
                infoCard
                statusCard
                disclaimerCard
            }
            .padding(SumiSpacing.lg)
        }
        .scrollIndicators(.hidden)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("Appearance")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            Picker("Appearance", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Text("Choose system, light, or dark mode for the full app.")
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)
        }
        .sumiCard()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("What runs locally")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            bullet("Journal signal interpretation (Medgemma via Melange with rule-based fallback)")
            bullet("Trend inference (Chronos via Melange with local baseline fallback)")
            bullet("Safe-share anonymization (Melange text anonymizer with regex fallback)")

            Text(viewModel.modelReadinessText)
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)
        }
        .sumiCard()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("Current inference source")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            statusRow("Journal", viewModel.journalSource)
            statusRow("Trend", viewModel.trendSource)
            statusRow("Redaction", viewModel.redactionSource)

            statusDetailRow("Journal model", viewModel.journalModelDescriptor)
            statusDetailRow("Chronos model", viewModel.chronosModelDescriptor)
            statusDetailRow("Redaction model", viewModel.redactionModelDescriptor)
            statusDetailRow(
                "Journal runtime",
                viewModel.isSwitchingJournalMelange
                    ? "Warming..."
                    : (viewModel.isJournalModelReady ? "Ready" : "Not ready")
            )
            statusDetailRow(
                "Trend runtime",
                viewModel.isTrendModelReady ? "Ready" : "Not ready"
            )
            statusDetailRow(
                "Redaction runtime",
                viewModel.isRedactionModelReady ? "Ready" : "Not ready"
            )

            Text(viewModel.melangeAvailable ? "Melange SDK: available" : "Melange SDK: unavailable")
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)
            Text(viewModel.melangeConfigured ? "Credentials: configured" : "Credentials: missing")
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)
            Text("Credential source: \(viewModel.personalKeySource)")
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)

            Divider()
                .padding(.vertical, 4)

            Toggle(
                "Enable Journal live model (experimental)",
                isOn: Binding(
                    get: { viewModel.journalMelangeEnabled },
                    set: { viewModel.journalMelangeEnabled = $0 }
                )
            )
            .font(SumiTypography.body)
            .tint(SumiPalette.accent)
            .disabled(!viewModel.melangeAvailable || !viewModel.melangeConfigured || viewModel.isSwitchingJournalMelange)

            Button {
                viewModel.refreshInferenceStatus()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text(viewModel.isRefreshingInferenceStatus ? "Refreshing..." : "Refresh Status")
                }
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.accent)
            }
            .disabled(!viewModel.melangeAvailable || !viewModel.melangeConfigured || viewModel.isSwitchingJournalMelange || viewModel.isRefreshingInferenceStatus)

            if let journalRuntimeMessage = viewModel.journalRuntimeMessage {
                runtimeMessageRow(journalRuntimeMessage)
            }
            if let trendRuntimeMessage = viewModel.trendRuntimeMessage {
                runtimeMessageRow(trendRuntimeMessage)
            }
            if let redactionRuntimeMessage = viewModel.redactionRuntimeMessage {
                runtimeMessageRow(redactionRuntimeMessage)
            }
        }
        .sumiCard()
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("Non-diagnostic boundary")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            Text("SumiSense is a pattern-awareness and safe-sharing tool. It does not diagnose conditions, provide treatment advice, or replace clinical care.")
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Internal alias: QuietSignal")
                .font(SumiTypography.micro)
                .foregroundStyle(SumiPalette.textSecondary)

            Button("Reset Demo Data") {
                viewModel.resetDemoData()
            }
            .font(SumiTypography.caption)
            .foregroundStyle(SumiPalette.accent)
        }
        .sumiCard()
    }

    private func statusRow(_ label: String, _ source: InferenceSource) -> some View {
        HStack {
            Text(label)
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textPrimary)
            Spacer()
            Text(source == .melange ? "Melange" : "Fallback")
                .font(SumiTypography.caption)
                .foregroundStyle(source == .melange ? SumiPalette.accent : SumiPalette.textSecondary)
        }
    }

    private func statusDetailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)
            Spacer()
            Text(value)
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func runtimeMessageRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(SumiTypography.micro)
            .foregroundStyle(SumiPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(SumiPalette.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textSecondary)
        }
    }
}
