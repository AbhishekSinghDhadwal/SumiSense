import SwiftUI
import Charts

struct TrendsView: View {
    @StateObject private var viewModel: TrendViewModel

    init(appState: AppStateViewModel) {
        _viewModel = StateObject(wrappedValue: TrendViewModel(appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SumiSpacing.lg) {
                SectionHeader(
                    title: "Trends",
                    subtitle: "Compare baseline and recent pattern stability over time."
                )

                windowPicker
                metricPicker
                trendChartCard
                trendSummaryCard
            }
            .padding(SumiSpacing.lg)
        }
        .scrollIndicators(.hidden)
    }

    private var windowPicker: some View {
        Picker("Window", selection: $viewModel.selectedWindow) {
            Text("14 days").tag(14)
            Text("30 days").tag(30)
        }
        .pickerStyle(.segmented)
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WellnessMetricType.allCases) { metric in
                    Button {
                        withAnimation(SumiMotion.gentleSpring) {
                            viewModel.selectedMetric = metric
                        }
                    } label: {
                        Text(metric.title)
                            .font(SumiTypography.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(viewModel.selectedMetric == metric ? SumiPalette.accent : SumiPalette.surface)
                            )
                            .foregroundStyle(viewModel.selectedMetric == metric ? Color.white : SumiPalette.textSecondary)
                    }
                }
            }
        }
    }

    private var trendChartCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            HStack {
                Text("\(viewModel.selectedWindow)-day \(viewModel.selectedMetric.title)")
                    .font(SumiTypography.cardTitle)
                    .foregroundStyle(SumiPalette.textPrimary)
                Spacer()
                if viewModel.isRefreshing || viewModel.isPrewarmingModels {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            Chart(filteredMetrics) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value(viewModel.selectedMetric.title, point.value(for: viewModel.selectedMetric))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [SumiPalette.accent.opacity(0.35), SumiPalette.accent.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date),
                    y: .value(viewModel.selectedMetric.title, point.value(for: viewModel.selectedMetric))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(SumiPalette.accent)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value(viewModel.selectedMetric.title, point.value(for: viewModel.selectedMetric))
                )
                .foregroundStyle(SumiPalette.accent)
                .symbolSize(28)
            }
            .frame(height: 240)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, viewModel.selectedWindow / 4))) {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.4))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(SumiTypography.micro)
                        .foregroundStyle(SumiPalette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.35))
                    AxisValueLabel()
                        .font(SumiTypography.micro)
                        .foregroundStyle(SumiPalette.textSecondary)
                }
            }
        }
        .sumiCard()
    }

    private var trendSummaryCard: some View {
        VStack(alignment: .leading, spacing: SumiSpacing.sm) {
            HStack {
                Text("Interpretation")
                    .font(SumiTypography.cardTitle)
                    .foregroundStyle(SumiPalette.textPrimary)
                Spacer()
                Button("Refresh") {
                    viewModel.refresh()
                }
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.accent)
                .disabled(viewModel.isRefreshing || viewModel.isPrewarmingModels)
            }

            if let assessment = viewModel.latestTrendAssessment {
                Text(assessment.plainLanguageSummary)
                    .font(SumiTypography.body)
                    .foregroundStyle(SumiPalette.textPrimary)

                HStack {
                    Text("Direction: \(assessment.trendDirection.title)")
                    Spacer()
                    Text(assessment.source == .melange ? "Chronos" : "Fallback")
                }
                .font(SumiTypography.caption)
                .foregroundStyle(SumiPalette.textSecondary)

                Label(
                    viewModel.trendEngineStatusText,
                    systemImage: assessment.source == .melange ? "checkmark.seal" : "exclamationmark.triangle"
                )
                .font(SumiTypography.micro)
                .foregroundStyle(assessment.source == .melange ? SumiPalette.accent : SumiPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(assessment.metricHighlights, id: \.self) { highlight in
                    Label(highlight, systemImage: "circle.fill")
                        .font(SumiTypography.caption)
                        .foregroundStyle(SumiPalette.textSecondary)
                }
            } else {
                Text("Trend summary will appear after data loads.")
                    .font(SumiTypography.body)
                    .foregroundStyle(SumiPalette.textSecondary)
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
            if viewModel.isPrewarmingModels {
                Label("Preparing trend model in the background. Initial download may take a minute.", systemImage: "arrow.down.circle")
                    .font(SumiTypography.micro)
                    .foregroundStyle(SumiPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sumiCard()
    }

    private var filteredMetrics: [WellnessMetricPoint] {
        let sorted = viewModel.metrics.sorted { $0.date < $1.date }
        return Array(sorted.suffix(viewModel.selectedWindow))
    }
}
