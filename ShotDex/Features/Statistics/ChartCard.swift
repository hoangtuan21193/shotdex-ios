import Charts
import SwiftUI

/// Formats a chart's Y value for display, honoring the metric's field so an
/// aperture average reads "f/2.8", a file-size total "1.2 GB", etc.
enum ChartValueFormatter {
    static func string(_ value: Double, metric: ChartMetric) -> String {
        guard metric.aggregation != .count, let field = metric.field else {
            return "\(Int(value.rounded()))"
        }
        switch field {
        case .iso: return "ISO \(Int(value.rounded()))"
        case .aperture: return MetadataFormatter.aperture(value) ?? Self.plain(value)
        case .shutter: return MetadataFormatter.shutterSpeed(value) ?? Self.plain(value)
        case .focalLength, .equivalentFocalLength: return MetadataFormatter.focalLength(value) ?? Self.plain(value)
        case .fileSize: return MetadataFormatter.fileSize(Int(value.rounded())) ?? Self.plain(value)
        case .megapixels: return MetadataFormatter.megapixels(value) ?? Self.plain(value)
        }
    }

    private static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The chart body for a spec (no surrounding `Section`), reused by both the
/// dashboard card and the editor's live preview. Tapping a categorical/binned
/// row drills into a filtered Library via `onDrill` (nil disables drilling).
struct ChartContentView: View {
    let spec: ChartSpec
    let data: [ChartDatum]
    var isLoading: Bool = false
    var onDrill: ((FilterCriteria) -> Void)?

    private var known: [ChartDatum] { data.filter { !$0.isUnknown } }
    private var knownTotal: Double { known.reduce(0) { $0 + $1.value } }

    var body: some View {
        if isLoading && data.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else if known.isEmpty && spec.kind != .kpi {
            Text("No data for this range.")
                .foregroundStyle(.secondary)
        } else {
            switch spec.kind {
            case .kpi: kpiBody
            case .bar: barBody
            case .donut: donutBody
            case .line: lineBody
            }
        }
    }

    // MARK: KPI

    @ViewBuilder
    private var kpiBody: some View {
        if let datum = known.first {
            let value = ChartValueFormatter.string(datum.value, metric: spec.metric)
            drillButton(key: datum.drillKey) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color(.label))
                    if spec.dimension != nil {
                        Text(datum.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No data for this range.").foregroundStyle(.secondary)
        }
    }

    // MARK: Bar

    private var barBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(known) { datum in
                BarMark(
                    x: .value("Value", datum.value),
                    y: .value("Category", datum.label)
                )
                .foregroundStyle(ChartPalette.bar)
                .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .frame(height: CGFloat(known.count) * 28 + 20)
            .padding(.vertical, 4)
            .accessibilityLabel("\(spec.title) bar chart")

            drillRows
        }
    }

    // MARK: Donut

    private var donutBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(known) { datum in
                SectorMark(
                    angle: .value("Value", datum.value),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Category", datum.label))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(range: ChartPalette.colors)
            .chartLegend(.hidden)
            .frame(height: 220)
            .padding(.vertical, 4)
            .accessibilityLabel("\(spec.title) donut chart")

            drillRows
        }
    }

    // MARK: Line

    private var lineBody: some View {
        Chart(known) { datum in
            LineMark(
                x: .value("Period", datum.label),
                y: .value("Value", datum.value)
            )
            .foregroundStyle(by: .value("Series", datum.series ?? spec.title))
        }
        .chartForegroundStyleScale(range: ChartPalette.colors)
        .chartLegend(known.contains { $0.series != nil } ? .visible : .hidden)
        .frame(height: 200)
        .padding(.vertical, 4)
        .accessibilityLabel("\(spec.title) line chart")
    }

    // MARK: Drill helpers (bar / donut rows)

    @ViewBuilder
    private var drillRows: some View {
        ForEach(Array(known.enumerated()), id: \.element.id) { index, datum in
            drillButton(key: datum.drillKey) {
                HStack {
                    if spec.kind == .donut {
                        Circle()
                            .fill(ChartPalette.colors[index % ChartPalette.colors.count])
                            .frame(width: 10, height: 10)
                    }
                    Text(datum.label)
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                    Spacer()
                    Text(ChartValueFormatter.string(datum.value, metric: spec.metric))
                        .foregroundStyle(.secondary)
                    if spec.metric.aggregation == .count, knownTotal > 0 {
                        Text(String(format: "%.0f%%", datum.value / knownTotal * 100))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Wraps content in a drill button when the bucket maps to a Library
    /// filter; otherwise renders it plainly (temporal buckets, "Unknown").
    @ViewBuilder
    private func drillButton<Content: View>(key: String?, @ViewBuilder content: () -> Content) -> some View {
        let criteria = key.flatMap { spec.dimension?.drillCriteria(key: $0) }
        if let criteria, let onDrill {
            Button { onDrill(criteria) } label: { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

/// One dashboard chart as a single `List` row: a title/menu header, the chart
/// body, and an "Unknown" footnote when metadata is missing. A row (not a
/// Section) so the parent `ForEach` can drag-reorder and swipe-delete it.
struct ChartCard: View {
    let spec: ChartSpec
    let data: [ChartDatum]
    let isLoading: Bool
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onDrill: (FilterCriteria) -> Void

    private var unknownCount: Int { data.first { $0.isUnknown }.map { Int($0.value) } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ChartContentView(spec: spec, data: data, isLoading: isLoading, onDrill: onDrill)
            if unknownCount > 0 {
                Text("\(unknownCount) photos without this info.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.title)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text(spec.scope.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("\(spec.title) options")
        }
    }
}
