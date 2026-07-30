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
            VStack(spacing: 0) {
                weekdayHeader
                Divider()
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(months, id: \.self) { month in
                            monthView(month)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .defaultScrollAnchor(.bottom)
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
    private func monthView(_ month: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MetadataFormatter.monthHeader(month))
                .font(.headline)

            let days = daysInMonth(month)
            let leading = leadingBlankCount(month)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let state = dayState(day)
        let isFuture = day > Date()
        let dayNumber = calendar.component(.day, from: day)
        return Button {
            select(day)
        } label: {
            Text("\(dayNumber)")
                .font(.callout)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 36)
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
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

#Preview {
    DateRangePickerSheet(earliestDate: nil, initialRange: nil) { _ in }
}
