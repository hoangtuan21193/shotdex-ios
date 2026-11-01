import Charts
import SwiftUI

/// The Statistics card at the top of Utilities: photos, camera bodies and
/// lenses, and photos per month over the last year. The whole card opens the
/// Statistics dashboard, where the charts are listed and added.
struct StatisticsOverviewCard: View {
    /// nil while the first load runs; the card keeps its size meanwhile.
    let overview: StatsOverview?
    /// Regular width: figures on the left, the chart beside them, so a card
    /// the width of an iPad is not twelve bars stretched across it.
    var isWide = false

    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 72

    private var shown: StatsOverview { overview ?? .empty }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Spacer(minLength: AppTheme.Spacing.sm)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if isWide {
                HStack(alignment: .bottom, spacing: AppTheme.Spacing.xxl) {
                    figures
                    chart
                }
            } else {
                figures
                chart
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .redacted(reason: overview == nil ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Statistics", comment: "VoiceOver label of the Statistics card in Utilities"))
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(.isButton)
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xxl) {
            figure(shown.photos, String(localized: "Photos", comment: "Statistics card in Utilities: label under the photo count"))
            figure(shown.cameras, String(localized: "Cameras", comment: "Statistics card in Utilities: label under the count of camera bodies"))
            figure(shown.lenses, String(localized: "Lenses", comment: "Statistics card in Utilities: label under the count of lenses"))
        }
        .fixedSize()
    }

    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color(.label))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// One series, so one hue (DESIGN.md §3.4): every month quiet, the
    /// busiest at full accent.
    private var chart: some View {
        let busiest = shown.months.max { $0.count < $1.count }
        return Chart(shown.months) { month in
            BarMark(
                x: .value("Month", month.start, unit: .month),
                y: .value("Photos", month.count)
            )
            .foregroundStyle(month.id == busiest?.id && month.count > 0 ? ChartPalette.emphasis : ChartPalette.quiet)
            .cornerRadius(2)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            // Three labels — first, middle, last month — not twelve: a name
            // under every bar crowded the card (user 2026-10-24), and three
            // are enough to read the span. Three letters, not one: "J J A"
            // reads as a code, not as June, July, August.
            // Placed mid-month rather than `centered:` — that centres a label
            // between its value and the next one given, which with three
            // values is three months over.
            AxisMarks(values: labelledMonths) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), anchor: .top, collisionResolution: .disabled)
            }
        }
        .chartXScale(domain: xDomain)
        .frame(height: chartHeight)
        .frame(maxWidth: .infinity)
    }

    /// First, middle and last month, each at its middle so the label sits
    /// under its bar.
    private var labelledMonths: [Date] {
        let months = shown.months
        guard !months.isEmpty else { return [] }
        let picks = months.count > 2 ? [0, months.count / 2, months.count - 1] : Array(months.indices)
        return picks.map { Self.middle(of: months[$0].start) }
    }

    /// From the first month's start to the last month's end, so the bars fill
    /// the width and the edge labels land on the edge bars.
    private var xDomain: ClosedRange<Date> {
        guard let first = shown.months.first?.start, let last = shown.months.last?.start,
              let end = Calendar.current.date(byAdding: .month, value: 1, to: last)
        else { return Date()...Date() }
        return first...end
    }

    private static func middle(of monthStart: Date) -> Date {
        let end = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return monthStart.addingTimeInterval(end.timeIntervalSince(monthStart) / 2)
    }

    private var spokenValue: String {
        var parts = [
            String(localized: "\(shown.photos) photos", comment: "VoiceOver value of the Statistics card: photo count"),
            String(localized: "\(shown.cameras) cameras", comment: "VoiceOver value of the Statistics card: camera body count"),
            String(localized: "\(shown.lenses) lenses", comment: "VoiceOver value of the Statistics card: lens count"),
        ]
        if let busiest = shown.months.max(by: { $0.count < $1.count }), busiest.count > 0 {
            let month = busiest.start.formatted(.dateTime.month(.wide).year())
            parts.append(String(
                localized: "Busiest month \(month), \(busiest.count) photos",
                comment: "VoiceOver value of the Statistics card: the month with the most photos in the last year"
            ))
        }
        return parts.joined(separator: ", ")
    }
}
