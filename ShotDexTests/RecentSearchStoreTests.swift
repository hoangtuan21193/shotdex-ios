import Testing
@testable import ShotDex

/// The list rule only — `UserDefaults` reading and writing is two lines of
/// framework call, the ordering is where a recents list actually goes wrong.
struct RecentSearchStoreTests {
    @Test func newestFirst() {
        var list = RecentSearchStore.merged([], with: "fukuoka")
        list = RecentSearchStore.merged(list, with: "f > 1.2")
        #expect(list == ["f > 1.2", "fukuoka"])
    }

    @Test func rerunMovesToTopInsteadOfDuplicating() {
        let list = RecentSearchStore.merged(["f > 1.2", "fukuoka"], with: "fukuoka")
        #expect(list == ["fukuoka", "f > 1.2"])
    }

    @Test func duplicateIgnoresCaseAndKeepsWhatWasJustTyped() {
        let list = RecentSearchStore.merged(["Fukuoka"], with: "fukuoka")
        #expect(list == ["fukuoka"])
    }

    @Test func trimsAndDropsBlankQueries() {
        #expect(RecentSearchStore.merged([], with: "  osaka  ") == ["osaka"])
        #expect(RecentSearchStore.merged(["osaka"], with: "   ") == ["osaka"])
    }

    @Test func staysWithinLimit() {
        var list: [String] = []
        for index in 0..<(RecentSearchStore.limit + 5) {
            list = RecentSearchStore.merged(list, with: "query \(index)")
        }
        #expect(list.count == RecentSearchStore.limit)
        #expect(list.first == "query \(RecentSearchStore.limit + 4)")
    }
}
