import SwiftUI

/// The Insights card at the top of Statistics (FS-07.02 §6): up to three
/// sentences about the user's own library, each opening the Library filtered
/// to the photos it talks about. The chart card's look — `r-lg` corners, the
/// grouped secondary background, 16pt padding — and no tokens of its own.
struct InsightsCard: View {
    let state: StatisticsModel.InsightsLoad
    /// The index is still running: the sentences describe what it has read.
    var isIndexing = false
    /// Sentence columns — 1 on a narrow screen, the dashboard's 2…3 on a wide one.
    var columns = 1
    var onOpen: (FilterCriteria) -> Void
    var onHide: () -> Void
    var onRetry: () -> Void
    /// Opens Settings → Unknown Cameras from the unknown-sensor footer.
    var onUnknownCameras: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            header
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Insights", tableName: InsightCopy.table)
                .font(.headline)
                .foregroundStyle(Color(.label))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button(action: onHide) {
                    Label(String(localized: "Hide Insights", table: InsightCopy.table), systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .tint(.primary)
            .accessibilityLabel(Text("Insights options", tableName: InsightCopy.table))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed:
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Couldn't compute insights.", tableName: InsightCopy.table)
                    .foregroundStyle(.secondary)
                // Borderless: inside a List row the default style turns the
                // whole row into the button and draws it in label colour.
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderless)
            }
        case .loaded(.hidden):
            EmptyView()
        case .loaded(.belowThreshold(let photosWithCamera)):
            Text(InsightCopy.belowThreshold(photosWithCamera))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(.insights(let sentences, let unknownSensorCount)):
            if !sentences.isEmpty {
                sentenceGrid(sentences)
            }
            footers(unknownSensorCount: unknownSensorCount)
        }
    }

    // MARK: Sentences

    /// One column: rows stacked, a hairline between them. Several: the
    /// sentences dealt round-robin into the dashboard's column count, so a
    /// wide screen reads them side by side.
    @ViewBuilder
    private func sentenceGrid(_ sentences: [Insight]) -> some View {
        if columns <= 1 {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(Array(sentences.enumerated()), id: \.offset) { index, insight in
                    if index > 0 { Divider() }
                    row(insight)
                }
            }
        } else {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        ForEach(Array(sentences.enumerated()).filter { $0.offset % columns == column }, id: \.offset) {
                            row($0.element)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// The kind's symbol, the sentence, and a chevron when it opens the
    /// Library. VoiceOver reads the sentence alone, as a button only when it
    /// is one.
    @ViewBuilder
    private func row(_ insight: Insight) -> some View {
        let sentence = InsightCopy.sentence(insight)
        let label = HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            Image(systemName: insight.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(sentence)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if insight.filter != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())

        if let filter = insight.filter {
            Button { onOpen(filter) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(sentence)
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sentence)
        }
    }

    // MARK: Footers

    @ViewBuilder
    private func footers(unknownSensorCount: Int?) -> some View {
        if let unknownSensorCount {
            let text = InsightCopy.unknownSensorFooter(unknownSensorCount)
            if let onUnknownCameras {
                Button(action: onUnknownCameras) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(text).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text)
            } else {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if isIndexing {
            Text(InsightCopy.indexingFooter())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
