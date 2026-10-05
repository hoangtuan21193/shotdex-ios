import Foundation
import GRDB
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-19 §2 (sidecars and in-file ratings).
@Suite struct SidecarReaderTests {
    private let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))

    /// AC-52: a file photo takes the stars its camera wrote into it; a
    /// Photos asset takes its stars from Photos only. The original carries a
    /// 4-star XMP rating (as a Lightroom export does), and indexing it as an
    /// asset keeps Photos' value — none, or 0 — rather than the file's. An
    /// ARW in a folder whose own XMP says ★3, with no sidecar, is ★3.
    @Test func cameraRatingFilesOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexSidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try MetadataFixture.lightroomJPEG(in: folder)
        #expect(try String(decoding: Data(contentsOf: url), as: UTF8.self).contains("xmp:Rating=\"\(MetadataFixture.rating)\""))

        guard case .success(let exif) = ExifReader.readExif(fromImageAt: url) else {
            Issue.record("fixture did not parse")
            return
        }
        let unrated = AssetInfo(assetId: "A", mediaType: 1, isFavorite: false, rating: nil)
        #expect(composer.compose(asset: unrated, exif: exif, exifStatus: .indexed).rating == nil)
        let zero = AssetInfo(assetId: "B", mediaType: 1, isFavorite: false, rating: 0)
        #expect(composer.compose(asset: zero, exif: exif, exifStatus: .indexed).rating == 0)

        let drive = folder.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        var options = MetadataFixture.Options()
        options.xmp = false
        options.starRating = nil
        let raw = try MetadataFixture.encode(.tiff, options: options)
        try Self.embeddingRating(3, in: raw, type: .tiff).write(to: drive.appendingPathComponent("DSC00001.ARW"))
        #expect(try Self.starsAfterReading(drive) == ["DSC00001.ARW": 3])
    }
}

extension SidecarReaderTests {
    /// A sidecar the way Lightroom Classic writes one beside a RAW: the
    /// standard rating (−1 for Reject), keywords in `dc:subject`, and
    /// develop settings ShotDex does not read.
    static func lightroomSidecar(rating: Int?, keywords: [String] = [], title: String? = nil) -> Data {
        let ratingAttribute = rating.map { "\n    xmp:Rating=\"\($0)\"" } ?? ""
        let subject = keywords.isEmpty ? "" : """

           <dc:subject>
            <rdf:Bag>
        \(keywords.map { "     <rdf:li>\($0)</rdf:li>" }.joined(separator: "\n"))
            </rdf:Bag>
           </dc:subject>
        """
        let titleElement = title.map { """

           <dc:title>
            <rdf:Alt>
             <rdf:li xml:lang="x-default">\($0)</rdf:li>
            </rdf:Alt>
           </dc:title>
        """ } ?? ""
        return Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            xmp:CreatorTool="Adobe Lightroom Classic 14.0"\(ratingAttribute)
            crs:Version="17.0"
            crs:Exposure2012="+1.00">\(subject)\(titleElement)
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
    }

    /// AC-23: 300 RAW files, each with a Lightroom sidecar — 120 rated one
    /// star or more (45 of them three or more), 30 rejected (−1), 80 with
    /// the keyword "Kyoto". After the source is read, ★ ≥ 3 finds 45,
    /// Rejected finds 30, and a search for "Kyoto" finds 80.
    @MainActor
    @Test func lightroomRatingsRejectsKeywords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Lightroom-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = MetadataFixture.Options()
        options.xmp = false
        options.starRating = nil
        for index in 0..<300 {
            options.width = 32 + index
            options.height = 24
            let name = String(format: "DSC%05d", index)
            try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("\(name).ARW"))
            // 0..<45 three to five stars, 45..<120 one or two, 120..<150 rejected.
            let rating: Int? = switch index {
            case 0..<45: 3 + index % 3
            case 45..<120: 1 + index % 2
            case 120..<150: -1
            case 150..<200: 0
            default: nil
            }
            let keywords = index % 300 >= 220 ? ["Kyoto", "Japan"] : []
            try Self.lightroomSidecar(rating: rating, keywords: keywords).write(to: root.appendingPathComponent("\(name).xmp"))
        }

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "Lightroom", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let summary = try FolderSourceIndexer(database: database, composer: composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(summary.photos == 300)

        let library = LibraryQueries(database: database)
        var criteria = FilterCriteria()
        criteria.ratingFilter = .atLeast(3)
        #expect(try library.count(matching: criteria) == 45)
        criteria.ratingFilter = .atLeast(1)
        #expect(try library.count(matching: criteria) == 120)
        criteria = FilterCriteria()
        criteria.flags = [.rejected]
        #expect(try library.count(matching: criteria) == 30)
        criteria = FilterCriteria()
        criteria.searchText = "Kyoto"
        #expect(try library.count(matching: criteria) == 80)
        let counts = try PhotoKeywordStore(database: database).keywordCounts()
        #expect(counts.first { $0.keyword == "Kyoto" }?.count == 80)
    }
}

extension SidecarReaderTests {
    /// A file whose own XMP says `xmp:Rating` = `rating` — the way a camera
    /// (Sony, Fuji) or an app that writes into JPEGs leaves it. Pixels untouched.
    static func embeddingRating(_ rating: Int, in data: Data, type: UTType) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, String(rating) as CFString)
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true]
        #expect(CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil))
        return output as Data
    }

    /// Reads one folder and returns each file photo's stars by file name.
    static func starsAfterReading(_ root: URL) throws -> [String: Int] {
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "Files", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))
        _ = try FolderSourceIndexer(database: database, composer: composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        return try database.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: """
                SELECT c.relativePath, u.rating FROM photo_copies c LEFT JOIN photo_user_marks u ON u.photoId = c.photoId
                WHERE c.sourceId = ?
                """, arguments: [sourceId]).map { ($0["relativePath"] as String, ($0["rating"] as Int?) ?? 0) })
        }
    }

    /// AC-24: a JPEG whose own XMP says ★2 and has no sidecar is ★2; a JPEG
    /// that says ★2 inside and has a sidecar saying ★5 is ★5 — the sidecar
    /// wins.
    @Test func sidecarBeatsEmbedded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Embedded-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = MetadataFixture.Options()
        options.xmp = false
        options.starRating = nil
        let plain = try MetadataFixture.encode(.jpeg, options: options)
        try Self.embeddingRating(2, in: plain, type: .jpeg).write(to: root.appendingPathComponent("A.JPG"))
        options.width += 1
        let other = try MetadataFixture.encode(.jpeg, options: options)
        try Self.embeddingRating(2, in: other, type: .jpeg).write(to: root.appendingPathComponent("B.JPG"))
        try Self.lightroomSidecar(rating: 5).write(to: root.appendingPathComponent("B.xmp"))

        #expect(try Self.starsAfterReading(root) == ["A.JPG": 2, "B.JPG": 5])
    }
}
