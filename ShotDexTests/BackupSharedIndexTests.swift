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

    /// AC-38: a new phone C joins `Family`, whose index holds 55,000 lines
    /// from A and B. Reading it takes ≤ 5 s, no NAS file is read to hash it
    /// (every one has a hash in the index), and looking a hash up among
    /// 55,000 rows takes ≤ 10 ms.
    @Test func fiftyFiveThousandLinesReadFast() async throws {
        let nas = InMemoryRemoteFileClient()
        var lines: (a: [BackupContentIndex.Line], b: [BackupContentIndex.Line]) = ([], [])
        var hashes: [String] = []
        var twin = Data()
        for n in 0..<55_000 {
            let path = "\(n % 55)/F_\(n).JPG"
            var data = Data(repeating: UInt8(n % 251), count: 10 + n % 1_000)
            data.replaceSubrange(0..<4, with: withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) })
            nas.put("Family/" + path, data)
            let line = BackupContentIndex.Line(path: path, size: Int64(data.count), modified: nil, sha256: BackupFixture.sha(data), device: n < 30_000 ? "A" : "B", recordedAt: 1)
            if n < 30_000 { lines.a.append(line) } else { lines.b.append(line) }
            hashes.append(line.sha256)
            if n == 12_345 { twin = data }
        }
        nas.put("Family/.shotdex/backup-index/A-000001.jsonl", BackupContentIndex.encode(lines.a))
        nas.put("Family/.shotdex/backup-index/B-000001.jsonl", BackupContentIndex.encode(lines.b))

        var c = try BackupFixture(photos: 0, organize: BackupOrganize(), folder: "Family", client: nas, deviceId: "C")
        // One photo with the bytes of F_12345, one new photo whose size many
        // NAS files share.
        let (same, _) = BackupFixture.item(0, name: "IMG_1.JPG", bytes: twin.count)
        let (new, newData) = BackupFixture.item(1, name: "IMG_2.JPG", bytes: 400, seed: 999_999)
        c.source.replace([same, new])
        c.contents = newData
        c.contents[FakeAssetExporter.key("A0", "1:IMG_1.JPG")] = twin

        #expect(await c.runner().run().stop == .finished)
        #expect(nas.sha256Paths.filter { !$0.hasSuffix(ServerUploadPath.partSuffix) }.isEmpty)
        #expect(try c.store.duplicateEntries(jobId: c.job.id).first?.remotePath == "Family/\(12_345 % 55)/F_12345.JPG")
        #expect(nas.uploadCount == 1)

        // Reading the index alone, as a run does after listing the tree.
        let d = try BackupFixture(photos: 0, organize: BackupOrganize(), folder: "Family", client: nas, deviceId: "D")
        try d.store.applyListing(try await BackupDestinationScan.list(nas, folder: "Family"), jobId: d.job.id)
        let clock = ContinuousClock()
        let reading = try clock.measure {
            for name in ["A-000001.jsonl", "B-000001.jsonl"] {
                let data = try #require(nas.files["Family/.shotdex/backup-index/\(name)"])
                try d.store.mergeIndex(BackupContentIndex.decode(data), jobId: d.job.id, segment: name, size: Int64(data.count))
            }
        }
        #expect(reading <= .seconds(5))

        let lookups = clock.measure {
            for n in stride(from: 0, to: 55_000, by: 550) {
                #expect((try? d.store.destinationFiles(jobId: d.job.id, sha256: hashes[n]).count) == 1)
            }
        }
        #expect(lookups / 100 <= .milliseconds(10))
    }
}
