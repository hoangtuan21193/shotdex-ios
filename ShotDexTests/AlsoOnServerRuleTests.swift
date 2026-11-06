import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §7 / 07b §5: the Also on Server condition — Yes / No on a server
/// folder, its chip, and the rewrite of albums saved as `Source is <server>`.
@MainActor
struct AlsoOnServerRuleTests {
    private func query(_ f: OnServerFixture, _ yes: Bool, folder: String? = nil, source: String? = nil) -> SmartAlbumQuery {
        SmartAlbumQuery(rules: [SmartAlbumRule(field: .alsoOnServer, text: source ?? f.source, boolValue: yes, folder: folder)])
    }

    private func count(_ f: OnServerFixture, _ query: SmartAlbumQuery) async throws -> Int {
        try await LibraryQueries(database: f.database).count(matching: query)
    }

    /// AC-251: 60 items have every file under `Shared/`, 30 are checked and
    /// miss one, 10 still have a NAS file of their size to hash, and 5 photos
    /// live only on the NAS. Yes = 60, No = 30; the 10 and the 5 are in neither.
    @Test func yesNoUncheckedAndServerOnly() async throws {
        let f = try OnServerFixture(photos: 100)
        for n in 0..<60 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
            try f.server("Shared/2025/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)")
        }
        for n in 60..<90 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        for n in 90..<100 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
            try f.server("Shared/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: nil)
        }
        for n in 0..<5 { try f.server("Shared/Only/NAS_\(n).JPG", size: 5_000 + Int64(n), sha: "nas\(n)") }
        #expect(try await count(f, query(f, true, folder: "Shared")) == 60)
        #expect(try await count(f, query(f, false, folder: "Shared")) == 30)
    }

    /// AC-250's folder and a whole-source condition answer the same as the
    /// Source condition they replace (AC-74, AC-75 data).
    @Test func sameAnswersAsTheSourceCondition() async throws {
        let f = try OnServerFixture(photos: 100)
        for n in 0..<100 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        for n in 0..<40 { try f.server("Shared/2025/\(n % 3)/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)") }
        for n in 40..<65 { try f.server("Tuấn/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)") }
        for (yes, op) in [(true, RuleOperator.isExactly), (false, .isNot)] {
            for folder in [nil, "Shared", "Tuấn"] as [String?] {
                #expect(try await count(f, query(f, yes, folder: folder)) == f.count(op, folder: folder), "\(yes) \(folder ?? "-")")
            }
        }
        #expect(try await count(f, query(f, true)) == 65)
    }

    /// AC-254: a server that is gone matches nothing — Yes, No, and the old
    /// `Source is not <gone>` — so an album to delete from never widens to the
    /// whole library.
    @Test func goneServerMatchesNothing() async throws {
        let f = try OnServerFixture(photos: 10)
        for n in 0..<10 { try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")]) }
        #expect(try await count(f, query(f, true, source: "gone")) == 0)
        #expect(try await count(f, query(f, false, source: "gone")) == 0)
        let old = SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, op: .isNot, text: "gone")])
        #expect(try await count(f, old) == 0)
        // A source that exists still answers *is not*.
        let photos = SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, op: .isNot, text: f.source)])
        #expect(try await count(f, photos) == 10)
    }

    /// AC-249: no server picked → the condition is incomplete and skipped.
    @Test func noServerIsIncomplete() {
        let rule = SmartAlbumRule(field: .alsoOnServer)
        #expect(!rule.isValid)
        #expect(SmartAlbumQuery(rules: [rule]).validRules.isEmpty)
        #expect(SmartAlbumRule(field: .alsoOnServer, text: "S1").isValid)
    }

    /// AC-252, AC-255: the chip names the server and folder, never the field.
    @Test func chipText() {
        let names = ["S1": "NAS Home"]
        let yes = SmartAlbumRule(field: .alsoOnServer, text: "S1", boolValue: true, folder: "Shared")
        let no = SmartAlbumRule(field: .alsoOnServer, text: "S1", boolValue: false, folder: "/Shared/")
        let whole = SmartAlbumRule(field: .alsoOnServer, text: "S1")
        #expect(yes.displaySummary(naming: names) == "Also on NAS Home › Shared")
        #expect(no.displaySummary(naming: names) == "Not on NAS Home › Shared")
        #expect(whole.displaySummary(naming: names) == "Also on NAS Home")
        #expect(yes.compactDisplaySummary(naming: names) == "Also on NAS Home › Shared")
        #expect(SmartAlbumRule(field: .alsoOnServer).displaySummary == "Also on Server")
    }

    /// AC-253: an album saved as `Source is not <server> › Shared` opens as
    /// Also on Server: No on the same folder, and shows the same photos.
    /// Source conditions on Photos or a folder source are left alone.
    @Test func savedSourceServerRuleIsRewritten() async throws {
        let f = try OnServerFixture(photos: 20)
        for n in 0..<20 { try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")]) }
        for n in 0..<8 { try f.server("Shared/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)") }
        let ruleId = UUID()
        let saved = SmartAlbumQuery(rules: [
            SmartAlbumRule(id: ruleId, field: .source, op: .isNot, text: f.source, folder: "Shared"),
            SmartAlbumRule(field: .source, op: .isExactly, text: "photos"),
        ])
        let before = try await count(f, SmartAlbumQuery(rules: [saved.rules[0]]))
        let store = SmartAlbumStore(database: f.database)
        try store.upsert(SmartAlbum(id: "A", name: "Not on NAS", query: saved, createdAt: 1))
        let loaded = try #require(try store.fetchAllOrdered().first)
        let rewritten = loaded.query.rules[0]
        #expect(rewritten.id == ruleId)
        #expect(rewritten.field == .alsoOnServer)
        #expect(rewritten.boolValue == false)
        #expect(rewritten.text == f.source && rewritten.folder == "Shared")
        #expect(loaded.query.rules[1].field == .source)
        #expect(before == 12)
        #expect(try await count(f, SmartAlbumQuery(rules: [rewritten])) == before)
    }
}
