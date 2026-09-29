import Foundation
import Testing
@testable import ShotDex

/// The editor's recent-session cache (FS-03.09b AC-5): what a revisit reuses,
/// what eviction may throw away, and what a Save Changes retires.
struct EditingSessionCacheTests {
    private final class Session {
        let name: String
        init(_ name: String) { self.name = name }
    }

    /// FS-03.09b AC-5. A photo saved with Save Changes is no longer served
    /// from the cache — its next open reads PhotoKit again and gets the saved
    /// recipe — but its files stay until the editor closes, because the
    /// canvas may still be drawing from them.
    @Test func savedPhotoIsRetiredNotReused() {
        var cache = EditingSessionCache<Session>(limit: 3)
        let a = Session("A")
        _ = cache.remember(a, id: "A")
        cache.activeID = "A"

        cache.retire("A")
        #expect(cache.cached("A") == nil, "the next open must not reuse the pre-save session")
        #expect(cache.owns(a), "endSession must not delete files the canvas is still reading")

        let released = cache.releaseAll()
        #expect(released.contains { $0 === a }, "closing the editor deletes it")
        #expect(!cache.owns(a))
    }

    /// Retiring a photo that is not cached is a no-op, and retiring twice
    /// keeps one copy for release.
    @Test func retireIsIdempotent() {
        var cache = EditingSessionCache<Session>(limit: 3)
        cache.retire("missing")
        let a = Session("A")
        _ = cache.remember(a, id: "A")
        cache.retire("A")
        cache.retire("A")
        #expect(cache.releaseAll().filter { $0 === a }.count == 1)
    }

    /// A fresh session for the saved photo goes back into the cache as
    /// usual; the retired one is still released separately.
    @Test func reopenAfterSaveCachesTheNewSession() {
        var cache = EditingSessionCache<Session>(limit: 3)
        let before = Session("A-before")
        _ = cache.remember(before, id: "A")
        cache.retire("A")
        let after = Session("A-after")
        _ = cache.remember(after, id: "A")
        #expect(cache.cached("A") === after)
        let released = cache.releaseAll()
        #expect(released.contains { $0 === before } && released.contains { $0 === after })
    }

    /// Past the limit the oldest goes — never the photo on the canvas.
    @Test func evictionSparesTheCanvas() {
        var cache = EditingSessionCache<Session>(limit: 2)
        let a = Session("A"), b = Session("B"), c = Session("C")
        _ = cache.remember(a, id: "A")
        cache.activeID = "A"
        _ = cache.remember(b, id: "B")
        let evicted = cache.remember(c, id: "C")
        #expect(evicted.map(\.name) == ["B"])
        #expect(cache.cached("A") === a)
        #expect(cache.cached("C") === c)
        #expect(!cache.owns(b))
    }

    /// Remembering the same photo again replaces its entry instead of
    /// growing the cache; the one it replaced is handed back to be deleted.
    @Test func rememberingAgainReplaces() {
        var cache = EditingSessionCache<Session>(limit: 3)
        let first = Session("A1"), second = Session("A2")
        _ = cache.remember(first, id: "A")
        #expect(cache.remember(first, id: "A").isEmpty, "the same session again is not a replacement")
        let evicted = cache.remember(second, id: "A")
        #expect(evicted.count == 1 && evicted.first === first)
        #expect(cache.cached("A") === second)
    }
}
