import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-72: Settings › Sources' Remove… and Grant Access….
@Suite struct MacSourcesSettingsTests {
    /// A folder of 3 photos, read, then removed through Settings' model: the
    /// source and its photos leave the library and the rows; the 3 files stay
    /// on disk, untouched.
    @MainActor
    @Test func removeKeepsFiles() async throws {
        let folder = try Self.folder(photos: 3)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let database = try AppDatabase.makeEmpty()
        let model = Self.model(database)
        await model.addFolder(folder.url, includesSubfolders: true, pairsRawAndJpeg: true)
        let row = try #require(model.rows.first { $0.name == folder.url.lastPathComponent })
        #expect(row.text.count == 3)
        let readsBefore = model.readCount

        await model.remove(sourceId: row.id)

        #expect(!model.rows.contains { $0.id == row.id })
        #expect(model.readCount == readsBefore + 1)
        #expect(model.failure == nil)
        #expect(try SourceStore(database: database).photoCounts()[row.id] == nil)
        for (url, data) in folder.files { #expect(try Data(contentsOf: url) == data) }
    }

    /// AC-73: a folder added twice (Add Folder… then a drop) gives one source;
    /// a folder inside it is refused too, each time with the reason.
    @MainActor
    @Test func addFolderOnce() async throws {
        let folder = try Self.folder(photos: 2)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let inner = folder.url.appendingPathComponent("Selects", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let database = try AppDatabase.makeEmpty()
        let model = Self.model(database)

        await model.addFolder(folder.url, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(model.failure == nil)
        await model.addFolder(folder.url, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(model.failure?.message == "Already part of “\(folder.url.lastPathComponent)”.")
        model.failure = nil
        await model.addFolder(inner, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(model.failure?.message == "Already part of “\(folder.url.lastPathComponent)”.")

        #expect(try SourceStore(database: database).sources().filter { $0.kind != "photos" }.count == 1)
        #expect(model.rows.first { $0.name == folder.url.lastPathComponent }?.text.count == 2)
    }

    /// A folder around a source is refused too, by the model, with the reason.
    @MainActor
    @Test func addFolderAroundASourceIsRefused() async throws {
        let parent = try Self.folder(photos: 0)
        defer { try? FileManager.default.removeItem(at: parent.url) }
        let inner = parent.url.appendingPathComponent("Selects", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let model = Self.model(try AppDatabase.makeEmpty())
        await model.addFolder(inner, includesSubfolders: true, pairsRawAndJpeg: true)
        await model.addFolder(parent.url, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(model.failure?.message == "Contains “Selects”. Remove that source first to add this folder.")
        #expect(model.failure?.title == "Can’t Add This Folder")
    }

    /// A symlink to a source's folder is the same folder.
    @Test func overlapFollowsLinks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("Japan", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(SourceOverlap.check(link.path, against: [.init(name: "Japan", path: real.path)]) == .inside(sourceName: "Japan"))
    }

    /// A drop is one folder, not a file, not while a read goes.
    @Test func dropRefusals() throws {
        let folder = try Self.folder(photos: 1)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let file = try #require(folder.files.keys.first)
        #expect(SourcesModel.dropRefusal([folder.url], isReading: false) == nil)
        #expect(SourcesModel.dropRefusal([folder.url, folder.url], isReading: false) == "Drop one folder at a time.")
        #expect(SourcesModel.dropRefusal([file], isReading: false) == "“\(file.lastPathComponent)” is a file. Drop the folder that holds it.")
        #expect(SourcesModel.dropRefusal([folder.url], isReading: true)?.hasPrefix("Wait for the current read") == true)
    }

    /// Grant Access… on a source that lost its folder: the new bookmark and
    /// name are kept, and the folder is read back to its photos.
    @MainActor
    @Test func grantAccessReadsTheFolderAgain() async throws {
        let folder = try Self.folder(photos: 2)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let database = try AppDatabase.makeEmpty()
        let model = Self.model(database)
        let id = try SourceStore(database: database).addFolder(name: "Lost", bookmark: Data([0]), includesSubfolders: true,
                                                              pairsRawAndJpeg: true)
        _ = try FolderSourceAccess(database: database).open(sourceId: id)
        model.load()
        #expect(model.rows.first { $0.id == id }?.text.status == .needsAccess)

        await model.grantAccess(sourceId: id, folder: folder.url)

        let row = try #require(model.rows.first { $0.id == id })
        #expect(row.name == folder.url.lastPathComponent)
        #expect(row.text.status == .online)
        #expect(row.text.count == 2)
        #expect(model.failure == nil)
    }

    @MainActor
    private static func model(_ database: AppDatabase) -> SourcesModel {
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        return SourcesModel(database: database,
                            runner: FolderSourceRunner(database: database, metadataStore: MetadataStore(database: database), thumbnails: nil),
                            servers: ServerSourceRefresh(database: database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in
                                InMemoryRemoteFileClient()
                            },
                            photoLibrary: PhotoLibraryService())
    }

    private static func folder(photos: Int) throws -> (url: URL, files: [URL: Data]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Sources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL: Data] = [:]
        for n in 0..<photos {
            var options = MetadataFixture.Options()
            options.width += n * 8
            let data = try MetadataFixture.encode(.jpeg, options: options)
            let url = folder.appendingPathComponent("R\(n).JPG")
            try data.write(to: url)
            files[url] = data
        }
        return (folder, files)
    }

    /// AC-80: Clear Local Metadata Index forgets what was read from every
    /// photo and keeps what the user made — an album and its 2 photos, a flag.
    @Test func clearKeepsUserData() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.upsert(Self.row("p1"))
        try store.upsert(Self.row("p2"))
        let albums = ShotDexAlbumStore(database: database)
        let album = try albums.create(name: "Selects")
        try albums.add(photoIds: ["p1", "p2"], to: album)
        let marks = PhotoMarksStore(database: database)
        try marks.setFlag(.pick, ids: ["p1"])

        try store.deleteAll()

        #expect(try store.rowCount() == 0)
        // Members stay; the album lists them again as the index reads them back.
        let members = try database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT photoId FROM shotdex_album_members WHERE albumId = ? ORDER BY photoId", arguments: [album])
        }
        #expect(members == ["p1", "p2"])
        try store.upsert(Self.row("p1"))
        #expect(try albums.photoIds(in: album) == ["p1"])
        #expect(try marks.allFlags()["p1"] == .pick)
    }

    private static func row(_ assetId: String) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId, creationDate: 1_700_000_000, modificationDate: 1_700_000_000, mediaType: MediaKind.photo.storedValue,
            cameraManufacturer: nil, cameraModel: "X-T5", normalizedCameraModel: "X-T5", normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil,
            iso: 800, aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: nil, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: nil, cropFactor: nil, width: 6000, height: 4000, fileSize: 1_000,
            latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_700_000_000, exifStatus: ExifStatus.indexed.rawValue)
    }

    /// A folder photo's row is kept by Clear: only its source's read writes
    /// it, and that read skips a file that did not change (AC-80).
    @Test func clearKeepsFileSourceRows() async throws {
        let folder = try Self.folder(photos: 2)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        let runner = FolderSourceRunner(database: database, metadataStore: store, thumbnails: nil)
        let sourceId = try await runner.add(folder: folder.url, includesSubfolders: true, pairsRawAndJpeg: true)
        _ = try await runner.read(sourceId: sourceId)
        try store.upsert(Self.row("photos-asset"))
        #expect(try store.rowCount() == 3)

        try store.deleteAll()

        #expect(try store.rowCount() == 2)
        #expect(try SourceStore(database: database).photoCounts()[sourceId] == 2)
    }

    /// The confirmation says the photos go and the files stay, by where they live.
    @Test func removeMessageSaysWhatStays() {
        let folder = SourceRowText(kind: .onDevice, status: .online, count: 4_118)
        #expect(folder.removeMessage.contains(4_118.formatted(.number)))
        #expect(folder.removeMessage.hasSuffix("Nothing in the folder is deleted."))
        #expect(SourceRowText(kind: .drive, status: .offline, count: 1).removeMessage.hasSuffix("Nothing on the drive is deleted."))
        #expect(SourceRowText(kind: .server(protocolName: "SMB"), status: .online, count: 1).removeMessage
                .hasSuffix("Nothing on the server is deleted."))
    }

    /// A folder source's bookmark round-trips through `SourceBookmark`.
    @Test func bookmarkRoundTrips() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Bookmark-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var isStale = false
        let resolved = try SourceBookmark.resolve(SourceBookmark.make(for: folder), isStale: &isStale)
        #expect(resolved.standardizedFileURL.resolvingSymlinksInPath() == folder.standardizedFileURL.resolvingSymlinksInPath())
        // A bookmark kept before scoped ones still resolves.
        let legacy = try SourceBookmark.resolve(folder.bookmarkData(), isStale: &isStale)
        #expect(legacy.standardizedFileURL.resolvingSymlinksInPath() == folder.standardizedFileURL.resolvingSymlinksInPath())
    }
}
