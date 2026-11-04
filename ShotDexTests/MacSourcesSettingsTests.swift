import Foundation
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
