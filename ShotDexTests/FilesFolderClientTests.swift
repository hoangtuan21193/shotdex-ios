import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-17.05 — a Files-app folder as a connection, tried on a real folder on
/// disk with a real bookmark (the simulator has no Dropbox; the client code
/// is the same for every provider).
@Suite @MainActor struct FilesFolderClientTests {
    private func makeFolder() throws -> (url: URL, server: FileServer) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cloud-\(UUID().uuidString)/Trip", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("x"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: url.appendingPathComponent("a.JPG"))
        try Data([4, 5]).write(to: url.appendingPathComponent("b.CR3"))
        try Data([6]).write(to: url.appendingPathComponent(".hidden"))
        let described = FilesFolderClient.describe(url)
        let server = FileServer(name: "Trip", transferProtocol: .files, host: described.service, username: "",
                                share: described.folder, bookmark: try url.bookmarkData())
        return (url, server)
    }

    /// AC-46.
    @Test func bookmarkRoundTrip() async throws {
        let (url, server) = try makeFolder()
        let database = try AppDatabase.makeEmpty()
        let passwords = InMemoryPasswordStore()
        let store = FileServerStore(database: database, passwords: passwords)
        try store.save(server, password: nil)
        let saved = try #require(try store.fetch(id: server.id))
        #expect(saved.transferProtocol == .files)
        #expect(saved.bookmark == server.bookmark)
        #expect(passwords.password(for: server.id) == nil)
        #expect(saved.folderDescription.hasSuffix("Trip"))

        let client = FilesFolderClient(server: saved)
        try await client.connect()
        #expect(try client.url("").standardizedFileURL.path == url.standardizedFileURL.path)
        await client.disconnect()
    }

    /// AC-47.
    @Test func listsAndEdits() async throws {
        let (url, server) = try makeFolder()
        let client = FilesFolderClient(server: server)
        try await client.connect()

        let contents = ServerFolderListing.contents(of: try await client.entries(in: ""))
        #expect(contents.folders == ["x"])
        #expect(Set(contents.photos.map(\.id)) == ["a.JPG", "b.CR3"])

        try await client.createDirectory("New/Deep")
        #expect(try await client.directoryExists("New/Deep"))
        try await client.move("a.JPG", to: "Beach.JPG")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("Beach.JPG").path))
        try await client.removeFolderTree("New")
        #expect(!(try await client.directoryExists("New")))
        try await client.remove("b.CR3")
        try await client.remove("missing.JPG")
        #expect(try await client.fileNames(in: "") == ["Beach.JPG", ".hidden"])
        #expect(client.peeksWithSystemThumbnails)
    }

    /// AC-48.
    @Test func staysInsideTheFolder() async throws {
        let (_, server) = try makeFolder()
        let client = FilesFolderClient(server: server)
        try await client.connect()
        #expect(throws: RemoteFileError.self) { try client.url("../outside") }
        #expect(throws: RemoteFileError.self) { try client.url("/etc/hosts") }
        #expect(throws: RemoteFileError.self) { try client.url("x/./y") }
        await #expect(throws: RemoteFileError.self) { try await client.removeFolderTree("") }
    }

    /// AC-50: the upload flow's steps — part file, read back, rename.
    @Test func uploadVerifiesAndRenames() async throws {
        let (url, server) = try makeFolder()
        let client = FilesFolderClient(server: server)
        try await client.connect()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("up-\(UUID().uuidString).CR3")
        let data = Data((0..<50_000).map { UInt8($0 % 251) })
        try data.write(to: local)

        let part = "x/IMG_1.CR3" + ServerUploadPath.partSuffix
        try await client.upload(local, to: part) { _ in }
        let hash = try await client.sha256(of: part) { _ in }
        #expect(hash == FileChecksum.hex(SHA256.hash(data: data)))
        try await client.move(part, to: "x/IMG_1.CR3")
        #expect(try await client.fileNames(in: "x") == ["IMG_1.CR3"])
        #expect(try Data(contentsOf: url.appendingPathComponent("x/IMG_1.CR3")) == data)
        await #expect(throws: RemoteFileError.self) { try await client.upload(local, to: "nope/IMG.CR3") { _ in } }
    }

    @Test func describesTheService() {
        let base = "/private/var/mobile/Library/CloudStorage"
        #expect(FilesFolderClient.describe(URL(fileURLWithPath: "\(base)/Dropbox/Photos/Trip")).service == "Dropbox")
        #expect(FilesFolderClient.describe(URL(fileURLWithPath: "\(base)/GoogleDrive-me@example.com/My Drive/Trip")).service == "Google Drive")
        #expect(FilesFolderClient.describe(URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Trip")).service == "iCloud Drive")
        #expect(FilesFolderClient.describe(URL(fileURLWithPath: "\(base)/Dropbox/Photos/Trip")).folder == "Trip")
    }
}
