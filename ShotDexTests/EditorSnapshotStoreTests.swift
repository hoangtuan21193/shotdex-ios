import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.18 §5 (AC-9): snapshots are kept per photo, newest first, and come
/// back with the recipe they were taken with.
struct EditorSnapshotStoreTests {
    @Test func keepsRecipesPerPhoto() throws {
        let store = EditorSnapshotStore(database: try AppDatabase.makeEmpty())
        var warm = PhotoEditRecipe.identity
        warm.adjustments[.warmth] = 0.3
        var mono = PhotoEditRecipe.identity
        mono.adjustments[.blackAndWhite] = 1
        try store.add(name: "Warm", recipe: warm, photoId: "a", at: Date(timeIntervalSince1970: 100))
        let second = try store.add(name: "Mono", recipe: mono, photoId: "a", at: Date(timeIntervalSince1970: 200))
        try store.add(name: "Other", recipe: warm, photoId: "b")
        let shots = try store.snapshots(photoId: "a")
        #expect(shots.map(\.name) == ["Mono", "Warm"])
        #expect(shots.first?.recipe == mono)
        #expect(shots.last?.recipe == warm)
        try store.delete(id: second.id)
        #expect(try store.snapshots(photoId: "a").map(\.name) == ["Warm"])
        #expect(try store.snapshots(photoId: "b").count == 1)
    }
}
