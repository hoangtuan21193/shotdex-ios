import Foundation

/// What the "On This Day" reminder says. Split out from the scheduler so the
/// wording is unit-testable without a notification centre, and so the byte
/// formatter can be stubbed (`ByteCountFormatter` is locale-dependent).
enum OnThisDayNotificationCopy {
    static var title: String { String(localized: "On This Day") }

    /// Count plus size. The size is marked as a lower bound while some matching
    /// items are still unread — the index writes a row for every asset long
    /// before it has measured every file, and reporting a partial sum as a total
    /// would understate what deleting the day would free.
    static func body(
        for tally: OnThisDayDayTally,
        formattingBytes formatBytes: (Int) -> String? = MetadataFormatter.fileSize
    ) -> String {
        let count = countPhrase(tally.photoCount)
        // `MetadataFormatter.fileSize` returns nil at zero bytes, which is the
        // same situation as nothing measured yet.
        guard !tally.hasNoSize, let size = formatBytes(tally.indexedByteCount) else {
            return count
        }
        if tally.hasCompleteSize {
            return "\(count) · \(size)"
        }
        return String(localized: "\(count) · at least \(size)")
    }

    private static func countPhrase(_ count: Int) -> String {
        guard count != 1 else { return String(localized: "1 photo or video") }
        return String(localized: "\(count.formatted()) photos and videos")
    }
}
