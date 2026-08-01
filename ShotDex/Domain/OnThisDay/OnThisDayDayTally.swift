import Foundation

/// One calendar day's "On This Day" measurement, taken from the local index.
///
/// `indexedByteCount` covers only rows that already carry a `fileSize`, so
/// `sizedPhotoCount < photoCount` means the size is a lower bound — the fast
/// pass writes a row for every asset within seconds but fills `fileSize` only
/// once the EXIF read reaches it.
struct OnThisDayDayTally: Equatable, Sendable {
    /// Start of the target day, in the calendar the tally was built with.
    let date: Date
    /// Photos and videos matching this day's month/day across previous years.
    let photoCount: Int
    /// Summed `fileSize` of the subset that has one.
    let indexedByteCount: Int
    /// How many of `photoCount` contributed to `indexedByteCount`.
    let sizedPhotoCount: Int

    /// Every matching item has a measured size, so the total is exact.
    var hasCompleteSize: Bool { sizedPhotoCount == photoCount }

    /// Nothing has been measured yet — report the count alone rather than a
    /// size of zero.
    var hasNoSize: Bool { sizedPhotoCount == 0 }

    static func empty(date: Date) -> OnThisDayDayTally {
        OnThisDayDayTally(date: date, photoCount: 0, indexedByteCount: 0, sizedPhotoCount: 0)
    }
}
