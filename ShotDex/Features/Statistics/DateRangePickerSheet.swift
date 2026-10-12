import SwiftUI

/// Flight-booking style start–end date picker: a vertical list of month
/// calendars; first tap picks the start day, second tap the end day, and the
/// span between them is highlighted. Months run oldest → newest with the
/// current month at the bottom, matching the Library grid orientation.
struct DateRangePickerSheet: View {
    /// Earliest month to offer (first indexed photo); defaults to 10 years back.
    var earliestDate: Date?
    var initialRange: ClosedRange<Date>?
    var onApply: (ClosedRange<Date>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    @State private var startDay: Date?
    @State private var endDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = DateRangeMonthLayout(width: proxy.size.width)
                VStack(spacing: 0) {
                    if layout.columns == 1 {
                        weekdayHeader
                            .padding(.horizontal, DateRangeMonthLayout.margin)
                            .padding(.vertical, 6)
                        Divider()
                    }
                    ScrollView {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: DateRangeMonthLayout.columnGap, alignment: .top),
                                count: layout.columns
                            ),
                            spacing: layout.columns == 1 ? 24 : 16
                        ) {
                            // Blanks before the oldest month, so the current
                            // month always closes the bottom row.
                            ForEach(0..<layout.leadingBlanks(monthCount: months.count), id: \.self) { _ in
                                Color.clear.frame(height: 1)
                            }
                            ForEach(months, id: \.self) { month in
                                monthView(month, layout: layout)
                            }
                        }
                        .padding(.horizontal, DateRangeMonthLayout.margin)
                        .padding(.vertical, 16)
                    }
                    .defaultScrollAnchor(.bottom)
                }
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let startDay {
                            onApply(startDay...(endDay ?? startDay))
                            dismiss()
                        }
                    }
                    .disabled(startDay == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                selectionSummary
            }
        }
        .onAppear {
            if let initialRange {
                startDay = calendar.startOfDay(for: initialRange.lowerBound)
                endDay = calendar.startOfDay(for: initialRange.upperBound)
            }
        }
    }

    // MARK: Selection

    private func select(_ day: Date) {
        if let start = startDay, endDay == nil, day >= start {
            endDay = day
        } else {
            startDay = day
            endDay = nil
        }
    }

    private func dayState(_ day: Date) -> DayState {
        guard let startDay else { return .none }
        if day == startDay { return endDay == nil ? .single : .start }
        guard let endDay else { return .none }
        if day == endDay { return .end }
        return (startDay...endDay).contains(day) ? .inRange : .none
    }

    private enum DayState {
        case none, single, start, end, inRange
    }

    private var selectionSummary: some View {
        Group {
            if let startDay {
                Text(MetadataFormatter.dateRange(startDay, endDay ?? startDay))
            } else {
                Text("Select a start date")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Months

    private var months: [Date] {
        let now = Date()
        let fallback = calendar.date(byAdding: .year, value: -10, to: now) ?? now
        let earliest = earliestDate ?? fallback
        guard let firstMonth = calendar.dateInterval(of: .month, for: earliest)?.start,
              let currentMonth = calendar.dateInterval(of: .month, for: now)?.start
        else { return [] }
        var result: [Date] = []
        var month = firstMonth
        while month <= currentMonth {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }

    @ViewBuilder
    private func monthView(_ month: Date, layout: DateRangeMonthLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.columns == 1 ? 8 : 4) {
            Text(MetadataFormatter.monthHeader(month))
                .font(.headline)

            // Side-by-side months each carry their weekdays: one header row
            // cannot line up over several grids.
            if layout.columns > 1 {
                weekdayHeader
            }

            let days = daysInMonth(month)
            let leading = leadingBlankCount(month)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.frame(height: layout.dayHeight)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day, layout: layout)
                }
            }
        }
    }

    private func dayCell(_ day: Date, layout: DateRangeMonthLayout) -> some View {
        let state = dayState(day)
        let isFuture = day > Date()
        let dayNumber = calendar.component(.day, from: day)
        return Button {
            select(day)
        } label: {
            Text("\(dayNumber)")
                .font(layout.columns == 1 ? .callout : .subheadline)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: layout.dayHeight)
                .foregroundStyle(foreground(for: state, isFuture: isFuture))
                .background(background(for: state))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(day, style: .date))
    }

    private func foreground(for state: DayState, isFuture: Bool) -> Color {
        if isFuture { return Color(.tertiaryLabel) }
        switch state {
        case .single, .start, .end: return .white
        case .inRange, .none: return Color(.label)
        }
    }

    @ViewBuilder
    private func background(for state: DayState) -> some View {
        switch state {
        case .single:
            Circle().fill(accent)
        case .start:
            // Half band toward the range side + the endpoint circle.
            HStack(spacing: 0) {
                Color.clear
                accent.opacity(0.2)
            }
            .overlay(Circle().fill(accent))
        case .end:
            HStack(spacing: 0) {
                accent.opacity(0.2)
                Color.clear
            }
            .overlay(Circle().fill(accent))
        case .inRange:
            accent.opacity(0.2)
        case .none:
            Color.clear
        }
    }

    // MARK: Calendar math

    private func daysInMonth(_ month: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: month)
        }
    }

    /// Blank cells before day 1, honoring the locale's first weekday.
    private func leadingBlankCount(_ month: Date) -> Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Rotate so the row starts at the locale's first weekday.
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// How many months sit side by side (FS-07 Date Range): one column on a
/// phone, more on a wide sheet so the days stay close together instead of
/// spreading 130pt apart — two in an iPad form sheet, four on the Duo's
/// inner display.
struct DateRangeMonthLayout: Equatable {
    static let margin: CGFloat = 16
    static let columnGap: CGFloat = 24
    /// Narrowest month: seven 30pt days.
    static let minimumMonthWidth: CGFloat = 210

    let columns: Int

    init(width: CGFloat) {
        let usable = width - 2 * Self.margin
        columns = max(1, Int((usable + Self.columnGap) / (Self.minimumMonthWidth + Self.columnGap)))
    }

    /// Shorter days once months sit side by side, so two rows of months fit
    /// the Duo's 669pt.
    var dayHeight: CGFloat { columns == 1 ? 36 : 32 }

    /// Empty cells before the oldest month, so the newest month ends the
    /// last row and the bottom-anchored scroll opens on a full row.
    func leadingBlanks(monthCount: Int) -> Int {
        let remainder = monthCount % columns
        return remainder == 0 ? 0 : columns - remainder
    }
}

#Preview {
    DateRangePickerSheet(earliestDate: nil, initialRange: nil) { _ in }
}
