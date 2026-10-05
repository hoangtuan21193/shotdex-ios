import Foundation
import GRDB
import ImageIO
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-19.02 §5 — writing `.xmp` sidecars.
@Suite struct SidecarWriterTests {
    /// A Lightroom Classic sidecar with `count` develop settings, Photo
    /// Mechanic's own fields and two keywords — the kind of file whose every
    /// byte ShotDex must leave alone.
    static func lightroomSidecarWithSettings(count: Int) -> String {
        let settings = (0..<count).map { "    crs:Setting\(String(format: "%03d", $0))=\"\(Double($0) / 7)\"" }.joined(separator: "\n")
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            xmlns:photomechanic="http://ns.camerabits.com/photomechanic/1.0/"
            xmp:CreatorTool="Adobe Lightroom Classic 14.0 (Macintosh)"
            xmp:Rating="3"
            photomechanic:ColorClass="2"
            photomechanic:Tagged="True"
            photomechanic:Prefs="0:2:3:005631"
        \(settings)>
           <dc:subject>
            <rdf:Bag>
             <rdf:li>Nara</rdf:li>
             <rdf:li>Japan</rdf:li>
            </rdf:Bag>
           </dc:subject>
           <crs:ToneCurvePV2012>
            <rdf:Seq>
             <rdf:li>0, 0</rdf:li>
             <rdf:li>255, 255</rdf:li>
            </rdf:Seq>
           </crs:ToneCurvePV2012>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    /// The text with one element taken out — what "every other tag is the
    /// same, byte for byte" is compared on.
    static func removing(_ element: String, from xmp: String) -> String {
        guard let start = xmp.range(of: "<\(element)"),
              let end = xmp.range(of: "</\(element)>", range: start.upperBound..<xmp.endIndex) else { return xmp }
        return String(xmp[..<start.lowerBound]) + String(xmp[end.upperBound...])
    }

    /// AC-25: a sidecar holding 214 Lightroom develop settings and Photo
    /// Mechanic's fields gets the keyword "deer" from ShotDex. The sidecar
    /// now lists deer beside its keywords, and everything outside the
    /// keyword list is the same text, byte for byte.
    @Test func preservesForeignTags() throws {
        let original = Self.lightroomSidecarWithSettings(count: 214)
        var patch = XMPPatch()
        patch.keywords = .set(["Nara", "Japan", "deer"])
        let patched = XMPPatcher.apply(patch, to: original)

        #expect(Self.removing("dc:subject", from: patched) == Self.removing("dc:subject", from: original))
        let values = try #require(SidecarReader.values(xmp: Data(patched.utf8)))
        #expect(values.keywords == ["Nara", "Japan", "deer"])
        #expect(values.rating == 3)
        let metadata = try #require(CGImageMetadataCreateFromXMPData(Data(patched.utf8) as CFData))
        #expect(CGImageMetadataCopyStringValueWithPath(metadata, nil, "crs:Setting213" as CFString) as String? == String(213.0 / 7))
        #expect(CGImageMetadataCopyStringValueWithPath(metadata, nil, "photomechanic:Prefs" as CFString) as String? == "0:2:3:005631")
    }

    /// The patcher's other moves, each leaving the rest of the text alone:
    /// a rating changed in place, a title added where there was none, a
    /// keyword list removed, a sidecar made from nothing, and an element-
    /// form rating (`<xmp:Rating>2</xmp:Rating>`) rewritten as it stands.
    @Test func patchesOnlyItsOwnFields() throws {
        let original = Self.lightroomSidecarWithSettings(count: 3)
        var patch = XMPPatch()
        patch.rating = .set(-1)
        patch.title = .set("Deer & <friends>")
        patch.keywords = .remove
        let patched = XMPPatcher.apply(patch, to: original)
        let values = try #require(SidecarReader.values(xmp: Data(patched.utf8)))
        #expect(values.isRejected)
        #expect(values.title == "Deer & <friends>")
        #expect(values.keywords.isEmpty)
        #expect(patched.contains("crs:Setting002=\"\(2.0 / 7)\""))
        #expect(patched.contains("<crs:ToneCurvePV2012>"))

        var fresh = XMPPatch()
        fresh.rating = .set(4)
        fresh.keywords = .set(["Kyoto"])
        fresh.caption = .set("Fushimi Inari")
        let created = try #require(SidecarReader.values(xmp: Data(XMPPatcher.apply(fresh, to: nil).utf8)))
        #expect(created == SidecarValues(rating: 4, keywords: ["Kyoto"], caption: "Fushimi Inari"))

        let elementForm = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
           <xmp:Rating>2</xmp:Rating>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
        var five = XMPPatch()
        five.rating = .set(5)
        let rewritten = XMPPatcher.apply(five, to: elementForm)
        #expect(rewritten == elementForm.replacingOccurrences(of: "<xmp:Rating>2<", with: "<xmp:Rating>5<"))
    }
}

extension SidecarWriterTests {
    /// AC-19: one photo with two identical copies — "2026 Japan" and T7, both
    /// online, sidecars on. ★4 set in ShotDex reaches a `DSC04500.xmp` beside
    /// each copy on its own — the queue writes one second after the last
    /// change, which is the ≤ 2 s; the image files are the same bytes as
    /// before, and nothing waits to go to Photos (a file photo has no Photos
    /// copy). The wall-clock wait allows 10 s: suites run in parallel, and a
    /// neighbour's synchronous file work can hold every cooperative thread
    /// past the timer.
    @MainActor
    @Test func writesEveryOnlineCopyNeverTheImage() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Write-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let japan = base.appendingPathComponent("2026 Japan"), t7 = base.appendingPathComponent("T7")
        for folder in [japan, t7] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var options = MetadataFixture.Options()
        options.starRating = nil
        let bytes = try MetadataFixture.encode(.jpeg, options: options)
        for folder in [japan, t7] { try bytes.write(to: folder.appendingPathComponent("DSC04500.JPG")) }
        let before = try FolderSourceIndexTests.fingerprint(base)

        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let roots = [try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true): japan,
                     try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive"): t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        for (id, root) in roots { _ = try indexer.index(sourceId: id, root: root, includesSubfolders: true, pairsRawAndJpeg: true) }
        let fileURL: @Sendable (String, String) -> URL? = { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }
        _ = try IdentityMergePass(database: database, fileURL: fileURL).run()
        let photoId = try #require(try await database.reader.read { db in try String.fetchOne(db, sql: "SELECT id FROM photos") })

        #expect(SidecarWriteQueue.defaultDelay == .seconds(1))
        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database, fileURL: fileURL))
        let marks = PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue)
        let started = Date()
        await marks.setRating(4, ids: [photoId])
        let sidecars = [japan, t7].map { $0.appendingPathComponent("DSC04500.xmp") }
        while sidecars.contains(where: { SidecarReader.read(sidecarAt: $0)?.rating != 4 }), Date().timeIntervalSince(started) < 10 {
            try await Task.sleep(for: .milliseconds(50))
        }
        for sidecar in sidecars {
            #expect(SidecarReader.read(sidecarAt: sidecar)?.rating == 4, "\(sidecar.path)")
        }
        #expect(marks.rating(for: photoId) == 4)
        let after = try FolderSourceIndexTests.fingerprint(base).filter { !$0.key.hasSuffix(".xmp") }
        #expect(after == before)
        let pending = try await database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_photo_rating") }
        #expect(pending == 0)
        var criteria = FilterCriteria()
        criteria.ratingFilter = .atLeast(4)
        #expect(try LibraryQueries(database: database).count(matching: criteria) == 1)
    }
}

extension SidecarWriterTests {
    private static func standardRating(_ sidecar: URL) -> String? {
        guard let data = try? Data(contentsOf: sidecar),
              let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else { return nil }
        return CGImageMetadataCopyStringValueWithPath(metadata, nil, "xmp:Rating" as CFString) as String?
    }

    /// Reads `root` into a fresh library — another device plugging in T7.
    private static func readElsewhere(_ root: URL) throws -> (rating: Int?, favorite: Bool?, flag: String?, recipe: PhotoEditRecipe?) {
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true,
                                                                     pairsRawAndJpeg: true, kind: "drive")
        let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))
        _ = try FolderSourceIndexer(database: database, composer: composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        return try database.reader.read { db in
            let marks = try Row.fetchOne(db, sql: "SELECT rating, isFavorite FROM photo_user_marks")
            let recipe = try Data.fetchOne(db, sql: "SELECT recipe FROM photo_recipes")
            return (marks?["rating"], marks?["isFavorite"], try String.fetchOne(db, sql: "SELECT flag FROM photo_flag"),
                    try recipe.map { try JSONDecoder().decode(PhotoEditRecipe.self, from: $0) })
        }
    }

    /// AC-54: A is ★4 on T7. X (Reject): the standard field says −1 and
    /// ShotDex's namespace keeps ★4. U (unflag): the standard field is 4
    /// again. Favorite and an Exposure +0.5 recipe go into ShotDex's
    /// namespace. Another device reading T7 gets ★4, the favorite and the
    /// recipe — and, while A was Rejected, the Reject with its ★4.
    @MainActor
    @Test func rejectPickFavoriteRecipe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = MetadataFixture.Options()
        options.starRating = nil
        try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("A.ARW"))
        let sidecar = root.appendingPathComponent("A.xmp")
        try SidecarReaderTests.lightroomSidecar(rating: 4).write(to: sidecar)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: sidecar.path)

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true,
                                                                     pairsRawAndJpeg: true, kind: "drive")
        _ = try FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let photoId = try #require(try await database.reader.read { db in try String.fetchOne(db, sql: "SELECT id FROM photos") })
        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database) { _, path in root.appendingPathComponent(path) })
        let marks = PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue)

        await marks.setFlag(.reject, ids: [photoId])
        await queue.flush()
        #expect(Self.standardRating(sidecar) == "-1")
        #expect(SidecarReader.read(sidecarAt: sidecar) == SidecarValues(rating: 4, isRejected: true))
        let rejected = try Self.readElsewhere(root)
        #expect(rejected.rating == 4)
        #expect(rejected.flag == PhotoFlag.reject.rawValue)

        await marks.setFlag(nil, ids: [photoId])
        await queue.flush()
        #expect(Self.standardRating(sidecar) == "4")

        var recipe = PhotoEditRecipe()
        recipe.adjustments.exposure = 0.5
        try PhotoUserMarksStore(database: database).setFavorite(true, ids: [photoId])
        try await database.writer.write { [recipe] db in
            try db.execute(sql: "INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, ?, ?)",
                           arguments: [photoId, try JSONEncoder().encode(recipe), Int(Date().timeIntervalSince1970)])
        }
        await queue.schedule([photoId])
        await queue.flush()
        let elsewhere = try Self.readElsewhere(root)
        #expect(elsewhere.rating == 4)
        #expect(elsewhere.favorite == true)
        #expect(elsewhere.flag == nil)
        #expect(elsewhere.recipe == recipe)
    }
}
