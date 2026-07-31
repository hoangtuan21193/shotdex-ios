import Foundation
import Testing
@testable import ShotDex

struct OnThisDayNotificationCopyTests {
    /// Stubbed so the assertions don't depend on `ByteCountFormatter`'s locale,
    /// while keeping the real "nil at zero bytes" behaviour.
    private func formatBytes(_ bytes: Int) -> String? {
        bytes > 0 ? "1.2 GB" : nil
    }

    private func body(count: Int, bytes: Int, sized: Int) -> String {
        OnThisDayNotificationCopy.body(
            for: OnThisDayDayTally(
                date: .now, photoCount: count, indexedByteCount: bytes, sizedPhotoCount: sized
            ),
            formattingBytes: formatBytes
        )
    }

    @Test func fullyIndexedDayShowsCountAndSize() {
        let text = body(count: 52, bytes: 1_300_000_000, sized: 52)
        #expect(text.contains("52"))
        #expect(text.contains("1.2 GB"))
        #expect(text.contains("·"))
    }

    @Test func partiallyIndexedDayMarksTheSizeAsALowerBound() {
        let complete = body(count: 52, bytes: 1_300_000_000, sized: 52)
        let partial = body(count: 52, bytes: 1_300_000_000, sized: 40)
        #expect(partial.contains("1.2 GB"))
        // Same count and size, but qualified — the exact wording is localized, so
        // assert it differs from the complete form rather than matching a phrase.
        #expect(partial != complete)
        #expect(partial.count > complete.count)
    }

    @Test func dayWithNothingMeasuredShowsTheCountAlone() {
        let text = body(count: 52, bytes: 0, sized: 0)
        #expect(text.contains("52"))
        #expect(!text.contains("·"))
        #expect(!text.contains("1.2 GB"))
    }

    @Test func zeroBytesIsTreatedAsNothingMeasured() {
        // `sizedPhotoCount` can be non-zero with a zero sum only in degenerate
        // data, but the formatter returns nil there and the copy must not trail
        // a separator with nothing after it.
        let text = body(count: 3, bytes: 0, sized: 3)
        #expect(!text.contains("·"))
        #expect(!text.hasSuffix(" "))
    }

    @Test func singleMatchUsesTheSingularPhrase() {
        let single = body(count: 1, bytes: 1_300_000_000, sized: 1)
        let plural = body(count: 2, bytes: 1_300_000_000, sized: 2)
        #expect(single.contains("1"))
        #expect(single != plural)
    }

    @Test func titleIsNotEmpty() {
        #expect(!OnThisDayNotificationCopy.title.isEmpty)
    }
}
