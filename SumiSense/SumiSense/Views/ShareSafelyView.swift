import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ShareSafelyView: View {
    @StateObject private var viewModel: ShareViewModel
    @State private var copied = false
    @State private var exportPayload: String = ""
    @State private var showingShareSheet = false

    init(appState: AppStateViewModel) {
        _viewModel = StateObject(wrappedValue: ShareViewModel(appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SumiSpacing.lg) {
                SectionHeader(
                    title: "Share Safely",
                    subtitle: "Generate privacy-safe versions for personal, clinician, or research use."
                )

                sourcePickerCard
                modeSelectorCard

                Button {
                    withAnimation(SumiMotion.spring) {
                        viewModel.generate()
                    }
                } label: {
                    HStack {
                        if viewModel.isGenerating || viewModel.isPrewarmingModels {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(
                            viewModel.isPrewarmingModels
                            ? "Preparing anonymizer model..."
                            : (viewModel.isGenerating
                               ? (viewModel.isLongRunning ? "Still generating..." : "Generating...")
                               : "Generate Privacy-safe Summary")
                        )
                            .font(SumiTypography.bodyEmphasis)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(SumiPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(viewModel.isGenerating || viewModel.isPrewarmingModels)

                if viewModel.isPrewarmingModels {
                    Label("Downloading and preparing anonymizer in the background.", systemImage: "arrow.down.circle")
                        .font(SumiTypography.micro)
                        .foregroundStyle(SumiPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if viewModel.isGenerating && viewModel.isLongRunning {
                    Label("Still running on-device redaction. First run can be slower while model files initialize.", systemImage: "hourglass")
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

                if let result = viewModel.latestResult {
                    VStack(alignment: .leading, spacing: SumiSpacing.sm) {
                        HStack {
                            Text("Transformation")
                                .font(SumiTypography.cardTitle)
                            Spacer()
                            Text(result.source == .melange ? "Melange" : "Fallback")
                                .font(SumiTypography.caption)
                                .foregroundStyle(SumiPalette.textSecondary)
                        }

                        RedactionComparisonView(source: result.sourceText, output: result.outputText)
                            .transition(SumiMotion.fadeSlide)

                        if !result.redactionsApplied.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(result.redactionsApplied, id: \.self) { item in
                                        TagChip(label: item)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Copy") { copy(result.outputText) }
                                .buttonStyle(.borderedProminent)
                            Button("Export") { export(result.outputText) }
                                .buttonStyle(.bordered)
                        }

                        if copied {
                            Text("Copied to clipboard")
                                .font(SumiTypography.caption)
                                .foregroundStyle(SumiPalette.accent)
                        }
                    }
                    .sumiCard()
                }
            }
            .padding(SumiSpacing.lg)
        }
        .scrollIndicators(.hidden)
        #if canImport(UIKit)
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: [exportPayload])
        }
        #endif
    }

    private var sourcePickerCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("Export source")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            Picker("Source", selection: $viewModel.selectedSource) {
                ForEach(ShareSourceSelection.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.sourceHelperText)
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)

            if viewModel.selectedSource == .selectedEntry {
                Picker("Entry", selection: $viewModel.selectedEntryID) {
                    ForEach(viewModel.entries) { entry in
                        Text("\(SumiDate.short(entry.date)) · \(entry.rawText.prefix(36))")
                            .tag(Optional(entry.id))
                    }
                }
                .pickerStyle(.menu)
            } else {
                Text("\(viewModel.sevenDayEntryCount) entries from the latest 7-day window will be included.")
                    .font(SumiTypography.caption)
                    .foregroundStyle(SumiPalette.textSecondary)
            }

            if !viewModel.sourcePreviewText.isEmpty {
                Text(viewModel.sourcePreviewText)
                    .font(SumiTypography.body)
                    .foregroundStyle(SumiPalette.textSecondary)
                    .lineLimit(8)
            }
        }
        .sumiCard()
    }

    private var modeSelectorCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            Text("Mode")
                .font(SumiTypography.cardTitle)
                .foregroundStyle(SumiPalette.textPrimary)

            Picker("Mode", selection: $viewModel.selectedMode) {
                ForEach(ShareMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.selectedMode.helperText)
                .font(SumiTypography.body)
                .foregroundStyle(SumiPalette.textSecondary)
        }
        .sumiCard()
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            copied = false
        }
    }

    private func export(_ text: String) {
        exportPayload = text
        copy(text)
        #if canImport(UIKit)
        showingShareSheet = true
        #endif
    }
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
