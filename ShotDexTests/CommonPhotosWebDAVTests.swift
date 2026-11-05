import CoreGraphics
import Foundation
import os
import Testing
@testable import ShotDex

/// Whether the local WebDAV test servers (wsgidav) answer: 127.0.0.1:8096
/// with its defaults, and 127.0.0.1:8097 configured to let dates be set
/// (`docs/_plans/FS1908_6E_LOOP.md`).
enum LocalWebDAVTestServer {
    static let isListening = listens(8096)
    static let takesDates = listens(8097)

    private static func listens(_ port: UInt16) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

/// FS-19.08 §6e on real WebDAV: a server that refuses every way of setting
/// a date says so (and is not asked again), one that takes them keeps the
/// copy's write time. Each skipped when its server is not running.
@Suite(.serialized) struct WebDAVFileInfoTests {
    private func client(port: Int) -> WebDAVFileClient {
        WebDAVFileClient(server: FileServer(name: "Test DAV", transferProtocol: .webdav, host: "127.0.0.1", port: port,
                                            username: "tester", share: "", usesTLS: false),
                         password: "secret")
    }

    private func put(_ dav: WebDAVFileClient, _ path: String) async throws {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello".utf8).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        try await dav.upload(local, to: path, progress: { _ in })
    }

    @Test(.enabled(if: LocalWebDAVTestServer.isListening)) func refusingServerIsUnsupported() async throws {
        let dav = client(port: 8096)
        try await dav.connect()
        let path = "photos/Shared/info-\(UUID().uuidString.prefix(8)).txt"
        try await put(dav, path)
        defer { Task { try? await dav.remove(path) } }
        let info = RemoteFileInfo(modified: Date(timeIntervalSince1970: 1_577_934_245))

        #expect(try await dav.setFileInfo(info, at: path) == .unsupported)
        #expect(try await dav.setFileInfo(info, at: path) == .unsupported)
        #expect(try await dav.fileInfo(at: path)?.hasSameModified(as: info) == false)
    }

    @Test(.enabled(if: LocalWebDAVTestServer.takesDates)) func acceptingServerKeepsTheDate() async throws {
        let dav = client(port: 8097)
        try await dav.connect()
        let path = "photos/Shared/info-\(UUID().uuidString.prefix(8)).txt"
        try await put(dav, path)
        defer { Task { try? await dav.remove(path) } }
        let info = RemoteFileInfo(modified: Date(timeIntervalSince1970: 1_577_934_245))

        #expect(try await dav.setFileInfo(info, at: path) == .applied)
        #expect(try await dav.fileInfo(at: path)?.hasSameModified(as: info) == true)
        let second = RemoteFileInfo(modified: Date(timeIntervalSince1970: 1_546_398_245))
        #expect(try await dav.setFileInfo(second, at: path) == .applied)
        #expect(try await dav.fileInfo(at: path)?.hasSameModified(as: second) == true)
    }
}

/// Every byte a client moves in or out, and an off switch for the server's
/// own copy — the long way, as SMB goes, against the same server.
final class ByteCountingClient: RemoteFileClient, @unchecked Sendable {
    let base: RemoteFileClient
    let copiesOnServer: Bool
    private let total = OSAllocatedUnfairLock(initialState: Int64(0))

    init(_ base: RemoteFileClient, copiesOnServer: Bool) {
        self.base = base
        self.copiesOnServer = copiesOnServer
    }

    var bytes: Int64 { total.withLock { $0 } }

    /// Wraps a call's running count; adds what it reached when it ends.
    private func counted<T>(_ body: (@escaping @Sendable (Int64) -> Void) async throws -> T,
                            forward: @escaping @Sendable (Int64) -> Void) async throws -> T {
        let reached = OSAllocatedUnfairLock(initialState: Int64(0))
        defer { let moved = reached.withLock { $0 }; total.withLock { $0 += moved } }
        return try await body { bytes in
            reached.withLock { $0 = max($0, bytes) }
            forward(bytes)
        }
    }

    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func fileSize(at path: String) async throws -> Int64? { try await base.fileSize(at: path) }
    func directoryExists(_ path: String) async throws -> Bool { try await base.directoryExists(path) }
    func fileNames(in directory: String) async throws -> Set<String> { try await base.fileNames(in: directory) }
    func folderNames(in directory: String) async throws -> Set<String> { try await base.folderNames(in: directory) }
    func createDirectory(_ path: String) async throws { try await base.createDirectory(path) }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        try await base.upload(localURL, to: path, progress: progress)
        total.withLock { $0 += size }
    }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await counted({ try await self.base.sha256(of: path, progress: $0) }, forward: progress)
    }
    func entries(in directory: String) async throws -> [RemoteEntry] { try await base.entries(in: directory) }
    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        let data = try await base.readRange(path, offset: offset, length: length)
        total.withLock { $0 += Int64(data.count) }
        return data
    }
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await counted({ try await self.base.download(path, to: localURL, progress: $0) }, forward: progress)
    }
    func move(_ source: String, to destination: String) async throws { try await base.move(source, to: destination) }
    func copyOnServer(_ source: String, to destination: String) async throws -> Bool {
        copiesOnServer ? try await base.copyOnServer(source, to: destination) : false
    }
    func remove(_ path: String) async throws { try await base.remove(path) }
    func removeEmptyDirectory(_ path: String) async throws { try await base.removeEmptyDirectory(path) }
    func removeFolderTree(_ path: String) async throws { try await base.removeFolderTree(path) }
    func fileInfo(at path: String) async throws -> RemoteFileInfo? { try await base.fileInfo(at: path) }
    func sourceInfo(at path: String) async throws -> RemoteFileInfo? { try await base.sourceInfo(at: path) }
    func setFileInfo(_ info: RemoteFileInfo, at path: String) async throws -> FileInfoSupport {
        try await base.setFileInfo(info, at: path)
    }
}

/// FS-19.08 AC-191 end to end against a real WebDAV server: wsgidav on
/// 127.0.0.1:8096 serving `build/dav-share`, whose `photos/A` and
/// `photos/B` hold the same 20 files of 50 MB (1 GB in common, B's renamed).
/// Skipped when nothing listens there.
@Suite(.enabled(if: LocalWebDAVTestServer.isListening), .serialized)
struct CommonPhotosWebDAVTests {
    private func client() -> WebDAVFileClient {
        WebDAVFileClient(server: FileServer(name: "Test DAV", transferProtocol: .webdav, host: "127.0.0.1", port: 8096,
                                            username: "tester", share: "", usesTLS: false),
                         password: "secret")
    }

    /// Copy of 1 GB in common: with COPY, the NAS copies and only the
    /// read-back crosses (≤ 1.1 GB); the long way moves ≈ 3 GB. Both land
    /// every photo, verified.
    @Test func serverCopyMovesOneThird() async throws {
        let dav = client()
        try await dav.connect()
        let folders = ["photos/A", "photos/B"]
        let scanner = CommonPhotosScanner(client: dav)
        let listing = try await scanner.list(folders)
        let photos = try await CommonPhotosVerifier(client: dav).verify(CommonPhotosMatcher.preview(listing.files), folders: folders)
        let common = photos.reduce(Int64(0)) { $0 + $1.size }
        #expect(photos.count == 20)
        #expect(common >= 1_000_000_000)

        var moved: [Bool: Int64] = [:]
        for serverCopy in [true, false] {
            let destination = "photos/Shared/e2e-\(serverCopy ? "copy" : "long")-\(UUID().uuidString.prefix(8))"
            let counting = ByteCountingClient(dav, copiesOnServer: serverCopy)
            let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosDAV-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: work) }
            try store.start(CommonPhotosRun(id: "R", connectionId: "dav", folders: folders, destination: destination, action: .copy),
                            items: CommonPhotosRunner.items(for: photos, runId: "R", folders: folders,
                                                            files: listing.files, sidecars: listing.sidecars))
            do {
                try await CommonPhotosRunner(client: counting, store: store, workDirectory: work).run("R")
            } catch {
                try? await dav.removeFolderTree(destination)
                throw error
            }
            moved[serverCopy] = counting.bytes
            let landed = try await dav.entries(in: destination).filter { !$0.name.hasSuffix(".csv") }
            #expect(landed.count == 20)
            #expect(!landed.contains { $0.name.hasSuffix(ServerUploadPath.partSuffix) })
            #expect(try store.items(runId: "R").allSatisfy { $0.status == .copied })
            try await dav.removeFolderTree(destination)
        }
        let withCopy = try #require(moved[true]), longWay = try #require(moved[false])
        print("AC-191 common \(common) B · with COPY \(withCopy) B (\(Double(withCopy) / Double(common))×) · long way \(longWay) B (\(Double(longWay) / Double(common))×)")
        #expect(Double(withCopy) <= 1.1 * Double(common))
        #expect(Double(longWay) >= 2.9 * Double(common))
    }
}
