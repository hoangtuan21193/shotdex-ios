import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-22.05 §2: two phones backing up into one NAS folder see each other's
/// files through the shared index, whatever the names and folders.
@Suite @MainActor struct BackupSharedIndexTests {
    private static let size = 3_200

    /// Phone A backs up `IMG_4410.HEIC` into `Family`, organized as given.
    private func phoneA(_ nas: InMemoryRemoteFileClient, organize: BackupOrganize, album: String? = nil) async throws -> BackupFixture {
        var a = try BackupFixture(photos: 0, organize: organize, folder: "Family", client: nas, deviceId: "PHONE-A")
        let (photo, data) = BackupFixture.item(0, name: "IMG_4410.HEIC", bytes: Self.size, seed: 77, album: album)
        a.source.replace([photo])
        a.contents = data
        #expect(await a.runner().run().stop == .finished)
        return a
    }

    /// Phone B has the same bytes as `IMG_9001.HEIC`, its job by date into `Family`.
    private func phoneB(_ nas: InMemoryRemoteFileClient) throws -> BackupFixture {
        var b = try BackupFixture(photos: 0, organize: BackupOrganize(), folder: "Family", client: nas, deviceId: "PHONE-B")
        let (photo, data) = BackupFixture.item(0, name: "IMG_9001.HEIC", bytes: Self.size, seed: 77)
        b.source.replace([photo])
        b.contents = data
        return b
    }

    private func photos(_ nas: InMemoryRemoteFileClient) -> [String] {
        nas.files.keys.filter { !$0.contains("/.shotdex/") && !$0.hasSuffix(ServerUploadPath.partSuffix) }.sorted()
    }

    /// AC-31: A copied `2025/Oct/2025.10.12/IMG_4410.HEIC`; B's run sends no
    /// byte, its ledger says `duplicate` → that file, and the folder still
    /// holds one copy. B learns the hash from A's segment — it reads no
    /// photo on the NAS to hash it.
    @Test func secondPhoneSkipsSameBytesUnderAnotherName() async throws {
        let nas = InMemoryRemoteFileClient()
        _ = try await phoneA(nas, organize: BackupOrganize())
        let target = "Family/2025/Oct/2025.10.12/IMG_4410.HEIC"
        #expect(photos(nas) == [target])
        #expect(nas.files.keys.contains { $0.hasPrefix("Family/.shotdex/backup-index/PHONE-A-") && $0.hasSuffix(".jsonl") })

        let b = try phoneB(nas)
        let uploads = nas.uploadCount
        let hashed = nas.sha256Paths.count
        let result = await b.runner().run()

        #expect(result.stop == .finished)
        #expect(nas.uploadCount == uploads)
        #expect(nas.sha256Paths.count == hashed)
        #expect(photos(nas) == [target])
        let row = try #require(try b.store.duplicateEntries(jobId: b.job.id).first)
        #expect(row.remotePath == target)
        #expect(row.localName == "IMG_9001.HEIC")
    }

    /// AC-32: A organizes by album, so its file is `Trip/IMG_4410.HEIC`; B
    /// organizes by date. B still skips it and makes no date folder for it.
    @Test func matchesInAnotherFolderLayout() async throws {
        let nas = InMemoryRemoteFileClient()
        var byAlbum = BackupOrganize()
        byAlbum.levels = .album
        _ = try await phoneA(nas, organize: byAlbum, album: "Trip")
        #expect(photos(nas) == ["Family/Trip/IMG_4410.HEIC"])

        let b = try phoneB(nas)
        #expect(await b.runner().run().stop == .finished)

        #expect(photos(nas) == ["Family/Trip/IMG_4410.HEIC"])
        #expect(try await !nas.directoryExists("Family/2025"))
        #expect(try b.store.duplicateEntries(jobId: b.job.id).first?.remotePath == "Family/Trip/IMG_4410.HEIC")
    }

    /// What B hashed itself goes back into the index for A — and A, after a
    /// reinstall, reads its own old segments and keeps counting from them.
    @Test func eachPhoneWritesOnlyItsOwnSegments() async throws {
        let nas = InMemoryRemoteFileClient()
        _ = try await phoneA(nas, organize: BackupOrganize())
        nas.put("Family/Old/P1.HEIC", Data(repeating: 4, count: 500))
        var b = try BackupFixture(photos: 0, organize: BackupOrganize(), folder: "Family", client: nas, deviceId: "PHONE-B")
        let (other, data) = BackupFixture.item(0, name: "IMG_1.HEIC", bytes: 500, seed: 3)
        b.source.replace([other])
        b.contents = data
        #expect(await b.runner().run().stop == .finished)

        let segments = nas.files.keys.filter { $0.hasPrefix("Family/.shotdex/backup-index/") }.sorted()
        #expect(segments == [
            "Family/.shotdex/backup-index/PHONE-A-000001.jsonl",
            "Family/.shotdex/backup-index/PHONE-B-000001.jsonl",
        ])
        let lines = BackupContentIndex.decode(nas.files["Family/.shotdex/backup-index/PHONE-B-000001.jsonl"]!)
        #expect(Set(lines.map(\.path)) == ["Old/P1.HEIC", "2025/Oct/2025.10.12/IMG_1.HEIC"])
        #expect(lines.allSatisfy { $0.device == "PHONE-B" })
        #expect(BackupContentIndex.nextNumber(device: "PHONE-A", existing: segments.map { ServerUploadPath.lastComponent(of: $0) }) == 2)
    }
}
