import Foundation
import GRDB

/// Read-side per-day aggregates for the "On This Day" reminder: how many photos
/// and videos match a calendar day across previous years, and how many bytes of
/// them the index has measured.
///
/// Reads `photo_metadata` only — never PhotoKit — for two reasons. The
/// equivalent PhotoKit fetch (`OnThisDayModel.fetchAssets`) is a compound
/// OR-predicate scan over the whole library, too slow to run seven times per
/// refresh; and going through the database means a background refresh needs no
/// photo authorization in hand. The count is exact once the index's fast pass
/// has run (it writes a row per asset within seconds, and prunes rows for
/// deleted assets); only `fileSize` is a subset, which is why the copy reports
/// a lower bound while reads are outstanding.
struct OnThisDayQueries: Sendable {
    let database: AppDatabase

    /// `mediaType` values matching `PhotoLibraryService.browsableMediaPredicate`
    /// (`PHAssetMediaType.image` / `.video`) — spelled out here so the SQL does
    /// not silently depend on the table containing browsable rows only.
    private static let browsableMediaTypes = "(1, 2)"

    /// Year of the oldest capture date in the index; bounds the year windows so
    /// a day does not build a hundred OR terms that can never match.
    func earliestCreationYear(calendar: Calendar) throws -> Int? {
        let epoch = try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT MIN(creationDate) FROM photo_metadata")
        }
        return epoch.map {
            calendar.component(.year, from: Date(timeIntervalSince1970: TimeInterval($0)))
        }
    }

    /// One tally per requested day, in the order given — a day with nothing to
    /// show still gets an entry, so callers never have to re-align the arrays.
    ///
    /// Each day is one indexed range scan per year window; the windows are built
    /// in Swift by `OnThisDayWindows` rather than with `strftime('%m-%d', …)`,
    /// which would bucket by UTC (putting a 23:30 photo on the wrong day), could
    /// not use the `creationDate` index, and would lose the Feb 29 and DST
    /// handling that function already has.
    func tallies(for days: [Date], calendar: Calendar, now: Date = .now) throws -> [OnThisDayDayTally] {
        guard !days.isEmpty else { return [] }
        let earliestYear = try earliestCreationYear(calendar: calendar)
            ?? calendar.component(.year, from: now)

        return try database.reader.read { db in
            try days.map { day in
                let windows = OnThisDayWindows.windows(
                    for: day, earliestYear: earliestYear, calendar: calendar, now: now
                )
                guard !windows.isEmpty else { return .empty(date: day) }

                let ranges = windows
                    .map { _ in "(creationDate >= ? AND creationDate < ?)" }
                    .joined(separator: " OR ")
                var arguments: [DatabaseValueConvertible] = []
                for window in windows {
                    arguments.append(Int(window.start.timeIntervalSince1970))
                    arguments.append(Int(window.end.timeIntervalSince1970))
                }
                let sql = """
                    SELECT COUNT(*) AS photoCount,
                           COALESCE(SUM(fileSize), 0) AS indexedByteCount,
                           COUNT(fileSize) AS sizedPhotoCount
                    FROM photo_metadata
                    WHERE mediaType IN \(Self.browsableMediaTypes) AND (\(ranges))
                    """
                guard let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments))
                else { return .empty(date: day) }

                return OnThisDayDayTally(
                    date: day,
                    photoCount: row["photoCount"] ?? 0,
                    indexedByteCount: row["indexedByteCount"] ?? 0,
                    sizedPhotoCount: row["sizedPhotoCount"] ?? 0
                )
            }
        }
    }
}
