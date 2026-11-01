import Foundation
import Testing
@testable import ShotDex

@MainActor
struct CollectionsLayoutTests {

    private func makeStore() -> CollectionsLayoutStore {
        CollectionsLayoutStore(
            defaults: UserDefaults(suiteName: "CollectionsLayout-\(UUID().uuidString)")!
        )
    }

    @Test func defaultsToTheAppsOwnOrder() {
        let store = makeStore()
        #expect(store.order == CollectionsSection.allCases)
        #expect(store.visibleOrder == CollectionsSection.allCases)
        #expect(!store.isCustomized)
    }

    @Test func reorderingSticks() {
        let store = makeStore()
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.order.first != .pinned)
        #expect(store.isCustomized)
    }

    @Test func hidingRemovesASectionFromTheTab() {
        let store = makeStore()
        store.setHidden(true, for: .subjects)
        #expect(store.isHidden(.subjects))
        #expect(!store.visibleOrder.contains(.subjects))
        #expect(store.visibleOrder.count == CollectionsSection.allCases.count - 1)
    }

    /// Pinned is what the user explicitly asked to keep in reach, so it may
    /// not be hidden.
    @Test func someSectionsCannotBeHidden() {
        let store = makeStore()
        store.setHidden(true, for: .pinned)
        #expect(!store.isHidden(.pinned))
    }

    @Test func resetGoesBackToTheDefault() {
        let store = makeStore()
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        store.setHidden(true, for: .subjects)
        store.reset()
        #expect(store.order == CollectionsSection.allCases)
        #expect(store.hidden.isEmpty)
        #expect(!store.isCustomized)
    }

    /// A build that adds a section must show it rather than lose it, and a
    /// build that removes one must not choke on the id left behind.
    @Test func anUnknownOrMissingSectionIsHandled() {
        let merged = CollectionsLayoutStore.merged(stored: [
            "mediaTypes", "somethingRemovedInALaterBuild", "subjects",
        ])
        #expect(merged.first == .mediaTypes)
        #expect(merged[1] == .subjects)
        #expect(Set(merged) == Set(CollectionsSection.allCases))
        #expect(merged.count == CollectionsSection.allCases.count)
    }

    @Test func theLayoutSurvivesALaunch() {
        let suite = "CollectionsLayout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = CollectionsLayoutStore(defaults: defaults)
        store.setHidden(true, for: .sharedAlbums)
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let movedOrder = store.order

        let reopened = CollectionsLayoutStore(defaults: defaults)
        #expect(reopened.order == movedOrder)
        #expect(reopened.isHidden(.sharedAlbums))
    }
}
