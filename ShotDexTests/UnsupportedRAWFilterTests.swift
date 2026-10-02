import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-03.04b AC-13: *Unsupported RAW* in the capture-kind submenu, in
/// Library (SQL over the verdicts) and on an album screen (the index's ids).
@MainActor
struct UnsupportedRAWFilterTests {
    typealias F = RAWVerdictFixtures

    /// 8 ARWs of an unreadable camera, 3 of an unknown one, 5 HEICs.
    func library() async throws -> (AppDatabase, UnsupportedRAWIndex) {
        let rows = F.rows("s", 8, ext: "ARW", make: "SONY", model: "ILCE-7M5")
            + F.rows("u", 3, ext: "ARW", make: "SONY", model: "ILCE-9M9")
            + F.rows("h", 5, ext: "HEIC", make: "Apple", model: "iPhone 17 Pro")
        let database = try F.database(rows)
        // The filter's SQL reads the build this device runs.
        let index = UnsupportedRAWIndex(
            store: RAWVerdictStore(database: database),
            probe: FakeRAWProbe(local: Set((1...8).map { "s\($0)" })),
            release: .current
        )
        index.runPass()
        await index.waitForPass()
        return (database, index)
    }

    @Test func libraryKeepsTheEight() async throws {
        let (database, index) = try await library()
        var criteria = FilterCriteria()
        criteria.mediaSubtypes = [.unsupportedRAW]
        #expect(try LibraryQueries(database: database).count(matching: criteria) == 8)
        #expect(index.assetIds.count == 8)
        // Ored with another kind like any other.
        criteria.mediaSubtypes = [.unsupportedRAW, .panorama]
        #expect(try LibraryQueries(database: database).count(matching: criteria) == 8)
    }

    /// An album of 4 of those ARWs and 2 HEICs keeps the 4.
    @Test func albumByIdentifiers() async throws {
        let (_, index) = try await library()
        var criteria = FilterCriteria()
        criteria.mediaSubtypes = [.unsupportedRAW]
        let predicate = try #require(AlbumFilterPredicate.predicate(
            for: criteria, unsupportedRAWIds: Array(index.assetIds)
        ))
        let album: [[String: Any]] = ["s1", "s2", "s3", "s4", "h1", "h2"].map {
            ["localIdentifier": $0, "mediaSubtypes": 0, "favorite": false, "mediaType": PHAssetMediaType.image.rawValue]
        }
        let kept = album.filter { predicate.evaluate(with: $0) }.compactMap { $0["localIdentifier"] as? String }
        #expect(kept == ["s1", "s2", "s3", "s4"])
        // No such photo anywhere: the filter shows nothing, not everything.
        let none = try #require(AlbumFilterPredicate.predicate(for: criteria, unsupportedRAWIds: []))
        #expect(album.allSatisfy { !none.evaluate(with: $0) })
    }

    /// The submenu and the chip are built from `allCases`.
    @Test func inTheMenuAndTheChip() {
        #expect(PhotoMediaSubtype.allCases.last == .unsupportedRAW)
        #expect(PhotoMediaSubtype.unsupportedRAW.title == "Unsupported RAW")
        #expect(!PhotoMediaSubtype.unsupportedRAW.hasSystemBit)
        #expect(PhotoMediaSubtype.allCases.filter { !$0.hasSystemBit } == [.unsupportedRAW])
        #expect(!AlbumFilterPredicate.needsIndex({ var c = FilterCriteria(); c.mediaSubtypes = [.unsupportedRAW]; return c }()))
    }
}
