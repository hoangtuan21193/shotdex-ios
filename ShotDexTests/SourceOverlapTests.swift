import Foundation
import Testing
@testable import ShotDex

/// FS-19.01 §1 — sources never overlap.
@Suite struct SourceOverlapTests {
    /// AC-45: with "2026 Japan" = `~/Pictures/2026 Japan`, adding
    /// `…/2026 Japan/Day 1` is refused as already part of it, and adding
    /// `~/Pictures` as containing it; a sibling folder is fine. Case and
    /// Unicode form do not hide an overlap; a shared name prefix is not one.
    @Test func refusesNestedAndContaining() {
        let sources = [SourceOverlap.Existing(name: "2026 Japan", path: "/Users/me/Pictures/2026 Japan")]

        let inside = SourceOverlap.check("/Users/me/Pictures/2026 Japan/Day 1", against: sources)
        #expect(inside == .inside(sourceName: "2026 Japan"))
        #expect(inside.message == "Already part of “2026 Japan”.")

        let around = SourceOverlap.check("/Users/me/Pictures", against: sources)
        #expect(around == .contains(sourceName: "2026 Japan"))
        #expect(around.message == "Contains “2026 Japan”. Remove that source first to add this folder.")

        #expect(SourceOverlap.check("/Users/me/Pictures/2026 Japan", against: sources) == .inside(sourceName: "2026 Japan"))
        #expect(SourceOverlap.check("/users/ME/pictures/2026 JAPAN/day 2", against: sources) == .inside(sourceName: "2026 Japan"))
        #expect(SourceOverlap.check("/Users/me/Pictures/2026 Japan Extras", against: sources) == .none)
        #expect(SourceOverlap.check("/Users/me/Pictures/2025 Korea", against: sources).message == nil)

        let decomposed = [SourceOverlap.Existing(name: "Đà Lạt", path: "/Volumes/T7/\u{0110}a\u{0300} La\u{0323}t")]
        #expect(SourceOverlap.check("/Volumes/T7/Đà Lạt/2026", against: decomposed) == .inside(sourceName: "Đà Lạt"))
    }
}
