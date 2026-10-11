import Foundation
import Testing
@testable import ShotDex

/// FS-19.01 §5 — new files in a watched folder.
@Suite struct FolderWatchTests {
    /// AC-8 (the part a test can hold): 12 JPGs copied in by Finder over 3 s,
    /// each growing as it copies. None is read while it still grows; all 12
    /// are ready 2 s after the last byte — well inside the 10 s budget. A
    /// copy cancelled halfway is never read.
    @Test func newFilesAppearAfterSettle() {
        var settle = FolderWatchSettle()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        let names = (1...12).map { "DSC\($0).JPG" }
        // Each file appears small, then grows to full size half a second
        // later; files start every 0.25 s.
        for (n, name) in names.enumerated() {
            settle.observe(path: name, size: 4_096, at: at(Double(n) * 0.25))
            settle.observe(path: name, size: 12_000_000, at: at(Double(n) * 0.25 + 0.5))
        }
        settle.observe(path: "partial.JPG", size: 1_000_000, at: at(1))
        settle.observe(path: "partial.JPG", size: 2_000_000, at: at(2))

        #expect(settle.settled(at: at(2)).isEmpty)
        // The last copy finished at 3.25 s; nothing earlier than 2 s after
        // each file stopped growing.
        let early = settle.settled(at: at(3.0))
        #expect(early.allSatisfy { name in names.firstIndex(of: name).map { Double($0) * 0.25 + 0.5 + 2 <= 3.0 } ?? false })
        settle.remove(path: "partial.JPG")
        let rest = settle.settled(at: at(5.25))
        #expect(Set(early + rest) == Set(names))
        #expect(settle.isEmpty)
        #expect(settle.nextCheck == nil)

        // Unchanged size keeps the clock: a repeated event is not a change.
        settle.observe(path: "A.JPG", size: 10, at: at(10))
        settle.observe(path: "A.JPG", size: 10, at: at(11))
        #expect(settle.nextCheck == at(12))
        #expect(settle.settled(at: at(12)) == ["A.JPG"])
    }
}
