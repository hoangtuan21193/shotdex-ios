import Foundation
import Testing
@testable import ShotDex

/// Whether the local SMB test server answers on 127.0.0.1:4450.
enum LocalSMBTestServer {
    static let isListening: Bool = {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(4450).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }()
}

/// FS-19.08 end to end against the local SMB test server (impacket on
/// 127.0.0.1:4450, share `photos`, `docs/_plans/FS1908_LOOP.md`). Skipped
/// when nothing listens there, so the suite stays green on any other Mac.
@Suite(.enabled(if: LocalSMBTestServer.isListening), .serialized)
struct CommonPhotosSMBTests {
    private func client() -> SMBFileClient {
        SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                         username: "tester", share: "photos"),
                      password: "secret")
    }

    /// Steps 1–5 on the fixture: 8 of Tuấn's 12 photos sit renamed in Vợ's
    /// `from-tuan`; `edited/IMG_0001.JPG` shares a name but not the bytes.
    @Test func scanFindsTheSharedPhotos() async throws {
        let smb = client()
        try await smb.connect()
        defer { Task { await smb.disconnect() } }
        let scanner = CommonPhotosScanner(client: smb)
        let folders = ["photos/Tuan", "photos/Vo"]

        let listing = try await scanner.list(folders)
        let groups = CommonPhotosMatcher.sizeGroups(listing.files)
        let keys = try await scanner.captureKeys(for: groups, folders: folders)
        let preview = CommonPhotosMatcher.preview(listing.files, captureKeys: keys)

        #expect(listing.files[0].count == 12)
        #expect(listing.files[1].count == 13)
        #expect(preview.candidateCount == 8)
        #expect(preview.likelyCount == 8)

        let photos = try await CommonPhotosVerifier(client: smb).verify(preview, folders: folders)

        #expect(photos.count == 8)
        #expect(photos.allSatisfy { $0.files[1].first?.relativePath.hasPrefix("from-tuan/") == true })
    }

    /// Copy on the real server: the 8 shared photos land in a fresh folder
    /// under `Shared`, each read back; the sources stay; a second run skips
    /// them all as already there.
    @Test func copyLandsVerified() async throws {
        let smb = client()
        try await smb.connect()
        defer { Task { await smb.disconnect() } }
        let folders = ["photos/Tuan", "photos/Vo"]
        let destination = "photos/Shared/e2e-\(UUID().uuidString.prefix(8))"
        let scanner = CommonPhotosScanner(client: smb)
        let listing = try await scanner.list(folders)
        let preview = CommonPhotosMatcher.preview(listing.files)
        let photos = try await CommonPhotosVerifier(client: smb).verify(preview, folders: folders)
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosSMB-\(UUID().uuidString)")
        let runner = CommonPhotosRunner(client: smb, store: store, workDirectory: work)

        for runId in ["first", "second"] {
            try store.start(CommonPhotosRun(id: runId, connectionId: "smb", folders: folders, destination: destination, action: .copy),
                            items: CommonPhotosRunner.items(for: photos, runId: runId, folders: folders,
                                                            files: listing.files, sidecars: listing.sidecars))
            do {
                try await runner.run(runId)
            } catch {
                try? await smb.removeFolderTree(destination)
                throw error
            }
        }

        let landed = try await smb.entries(in: destination).map(\.name)
        #expect(landed.filter { !$0.lowercased().hasSuffix(".xmp") && !$0.hasSuffix(".csv") }.count == 8)
        #expect(landed.filter { $0.hasSuffix(".csv") }.count == 2)
        #expect(!landed.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
        #expect(try store.items(runId: "first").allSatisfy { $0.status == .copied })
        #expect(try store.items(runId: "second").allSatisfy { $0.status == .skipped })
        #expect(try await scanner.list(folders).files.map(\.count) == [12, 13])
        try await smb.removeFolderTree(destination)
    }

    /// Move on the real server, in a scratch folder of its own: 3 photos put
    /// in both `A` and `B` (renamed in `B`) plus one only in `A`; the 3 are
    /// renamed into `C` on the server — no download — and gone from both
    /// sources; the one of its own stays.
    @Test func moveRenamesOnTheServer() async throws {
        let smb = client()
        try await smb.connect()
        defer { Task { await smb.disconnect() } }
        let root = "photos/e2e-move-\(UUID().uuidString.prefix(8))"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosSMB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            try await seedMoveFolders(smb, root: root, work: work)
            let folders = ["\(root)/A", "\(root)/B"]
            let scanner = CommonPhotosScanner(client: smb)
            let listing = try await scanner.list(folders)
            let photos = try await CommonPhotosVerifier(client: smb).verify(CommonPhotosMatcher.preview(listing.files), folders: folders)
            let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
            try store.start(CommonPhotosRun(id: "move", connectionId: "smb", folders: folders, destination: "\(root)/C", action: .move),
                            items: CommonPhotosRunner.items(for: photos, runId: "move", folders: folders,
                                                            files: listing.files, sidecars: listing.sidecars))

            try await CommonPhotosRunner(client: smb, store: store, workDirectory: work).run("move")

            #expect(photos.count == 3)
            #expect(try store.items(runId: "move").allSatisfy { $0.status == .moved })
            #expect(try await smb.entries(in: "\(root)/C").map(\.name).filter { !$0.hasSuffix(".csv") }.sorted()
                    == ["IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG"])
            #expect(try await scanner.list(folders).files.map { $0.map(\.name) } == [["IMG_0004.JPG"], []])
        } catch {
            try? await smb.removeFolderTree(root)
            throw error
        }
        try await smb.removeFolderTree(root)
    }

    /// A scratch tree for a Move: 4 of Tuấn's photos in `A/2025`, the first
    /// 3 also in `B` under other names.
    private func seedMoveFolders(_ smb: SMBFileClient, root: String, work: URL) async throws {
        for index in 1...4 {
            let name = String(format: "IMG_%04d.JPG", index)
            let local = work.appendingPathComponent(name)
            _ = try await smb.download("photos/Tuan/2025/06/\(name)", to: local, progress: { _ in })
            try await smb.createDirectory("\(root)/A/2025")
            try await smb.upload(local, to: "\(root)/A/2025/\(name)", progress: { _ in })
            if index <= 3 {
                try await smb.createDirectory("\(root)/B")
                try await smb.upload(local, to: "\(root)/B/copy of \(name)", progress: { _ in })
            }
        }
    }

    /// AC-134 on the real server: Move, then Undo Move — A's copies renamed
    /// back, B's written back under their own names, `C` left with only the
    /// run's CSV; the tree reads as before the Move.
    @Test func undoMoveOnTheServer() async throws {
        let smb = client()
        try await smb.connect()
        defer { Task { await smb.disconnect() } }
        let root = "photos/e2e-undo-move-\(UUID().uuidString.prefix(8))"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosSMB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            try await seedMoveFolders(smb, root: root, work: work)
            let folders = ["\(root)/A", "\(root)/B"]
            let scanner = CommonPhotosScanner(client: smb)
            let before = try await scanner.list(folders)
            let photos = try await CommonPhotosVerifier(client: smb).verify(CommonPhotosMatcher.preview(before.files), folders: folders)
            let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
            try store.start(CommonPhotosRun(id: "move", connectionId: "smb", folders: folders, destination: "\(root)/C", action: .move),
                            items: CommonPhotosRunner.items(for: photos, runId: "move", folders: folders,
                                                            files: before.files, sidecars: before.sidecars))
            try await CommonPhotosRunner(client: smb, store: store, workDirectory: work).run("move")
            try store.startUndo(of: "move", id: "undo")

            try await CommonPhotosUndoer(client: smb, store: store, workDirectory: work).run("undo")

            #expect(try store.items(runId: "undo").map(\.status) == [.undone, .undone, .undone])
            let left = try await smb.entries(in: "\(root)/C").map(\.name)
            #expect(left.count == 1 && left.allSatisfy { $0.hasSuffix(".csv") })
            let after = try await scanner.list(folders)
            #expect(after.files.map { $0.map(\.relativePath).sorted() } == before.files.map { $0.map(\.relativePath).sorted() })
            let again = try await CommonPhotosVerifier(client: smb).verify(CommonPhotosMatcher.preview(after.files), folders: folders)
            #expect(Set(again.map(\.sha256)) == Set(photos.map(\.sha256)))
        } catch {
            try? await smb.removeFolderTree(root)
            throw error
        }
        try await smb.removeFolderTree(root)
    }

    /// AC-131 on the real server: Copy the 8 shared photos into a fresh
    /// folder, then Undo Copy — the folder holds only the run's CSV, and
    /// Tuấn and Vợ are as they were.
    @Test func undoCopyOnTheServer() async throws {
        let smb = client()
        try await smb.connect()
        defer { Task { await smb.disconnect() } }
        let folders = ["photos/Tuan", "photos/Vo"]
        let destination = "photos/Shared/e2e-undo-\(UUID().uuidString.prefix(8))"
        let scanner = CommonPhotosScanner(client: smb)
        let before = try await scanner.list(folders)
        let photos = try await CommonPhotosVerifier(client: smb).verify(CommonPhotosMatcher.preview(before.files), folders: folders)
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosSMB-\(UUID().uuidString)")
        try store.start(CommonPhotosRun(id: "R1", connectionId: "smb", folders: folders, destination: destination, action: .copy),
                        items: CommonPhotosRunner.items(for: photos, runId: "R1", folders: folders,
                                                        files: before.files, sidecars: before.sidecars))
        do {
            try await CommonPhotosRunner(client: smb, store: store, workDirectory: work).run("R1")
            try store.startUndo(of: "R1", id: "U1")
            try await CommonPhotosUndoer(client: smb, store: store, workDirectory: work).run("U1")
        } catch {
            try? await smb.removeFolderTree(destination)
            throw error
        }

        let left = try await smb.entries(in: destination).map(\.name)
        #expect(left.count == 1 && left.allSatisfy { $0.hasSuffix(".csv") })
        #expect(try store.items(runId: "U1").count == 8)
        #expect(try store.items(runId: "U1").allSatisfy { $0.status == .undone })
        #expect(try store.items(runId: "R1").allSatisfy { $0.status == .undone })
        let after = try await scanner.list(folders)
        #expect(after.files.map { $0.map(\.relativePath).sorted() } == before.files.map { $0.map(\.relativePath).sorted() })
        try await smb.removeFolderTree(destination)
    }
}
