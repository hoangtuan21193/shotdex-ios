import Foundation
import Testing
@testable import ShotDex

struct PhotoGridSectionBuilderTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func emptyInput() {
        #expect(PhotoGridSectionBuilder.sections(creationDates: [], granularity: .day, calendar: calendar).isEmpty)
    }

    @Test func singlePhoto() {
        let sections = PhotoGridSectionBuilder.sections(
            creationDates: [date(2026, 7, 19)],
            granularity: .day,
            calendar: calendar
        )
        #expect(sections.count == 1)
        #expect(sections[0].range == 0..<1)
        #expect(sections[0].kind == .date(calendar.startOfDay(for: date(2026, 7, 19))))
    }

    @Test func groupsConsecutiveDaysNewestFirst() {
        let dates = [
            date(2026, 7, 19, hour: 20), date(2026, 7, 19, hour: 8),
            date(2026, 7, 18),
            date(2026, 7, 15), date(2026, 7, 15), date(2026, 7, 15),
        ]
        let sections = PhotoGridSectionBuilder.sections(creationDates: dates, granularity: .day, calendar: calendar)
        #expect(sections.map(\.range) == [0..<2, 2..<3, 3..<6])
    }

    @Test func groupsOldestFirstToo() {
        let dates = [date(2026, 7, 15), date(2026, 7, 18), date(2026, 7, 18), date(2026, 7, 19)]
        let sections = PhotoGridSectionBuilder.sections(creationDates: dates, granularity: .day, calendar: calendar)
        #expect(sections.map(\.range) == [0..<1, 1..<3, 3..<4])
    }

    @Test func monthGranularityMergesDays() {
        let dates = [
            date(2026, 7, 19), date(2026, 7, 3),
            date(2026, 6, 30), date(2026, 6, 1),
        ]
        let sections = PhotoGridSectionBuilder.sections(creationDates: dates, granularity: .month, calendar: calendar)
        #expect(sections.count == 2)
        #expect(sections.map(\.range) == [0..<2, 2..<4])
        #expect(sections[0].kind == .date(date(2026, 7, 1, hour: 0)))
    }

    @Test func yearBoundary() {
        let dates = [date(2027, 1, 1), date(2026, 12, 31)]
        let sections = PhotoGridSectionBuilder.sections(creationDates: dates, granularity: .month, calendar: calendar)
        #expect(sections.count == 2)
    }

    @Test func nilDatesFormOneTrailingUndatedSection() {
        let dates: [Date?] = [date(2026, 7, 19), date(2026, 7, 18), nil, nil]
        let sections = PhotoGridSectionBuilder.sections(creationDates: dates, granularity: .day, calendar: calendar)
        #expect(sections.count == 3)
        #expect(sections.last?.kind == .undated)
        #expect(sections.last?.range == 2..<4)
        #expect(sections.last?.id == "undated")
    }

    @Test func sectionIdsAreStableAndUnique() {
        let dates = [date(2026, 7, 19), date(2026, 7, 18), nil]
        let sections = PhotoGridSectionBuilder.sections(creationDates: dates, granularity: .day, calendar: calendar)
        #expect(Set(sections.map(\.id)).count == sections.count)
    }
}
