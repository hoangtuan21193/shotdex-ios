import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: Compare's whole-file loads.
@Suite struct CommonPhotosCompareLoaderTests {
    private func fixture() -> (InMemoryRemoteFileClient, CompareFileCache, Data, String) {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data((0..<48_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        nas.put("A/DSC04388.ARW", bytes)
        let sha = FileChecksum.hex(SHA256.hash(data: bytes))
        return (nas, CompareFileCache(), bytes, sha)
    }

    /// AC-182, AC-184: a copy the index has no picture of is read whole, in
    /// chunks of one call each (the connection free between them), its bytes
    /// checked; shown again, it comes from the cache — nothing read twice.
    @Test func downloadsOnceThenCaches() async throws {
        let (nas, cache, bytes, sha) = fixture()
        defer { cache.removeAll() }
        var loader = CommonPhotosCompareLoader(client: nas, cache: cache)
        loader.chunkBytes = 10_000

        let first = try await loader.load(path: "A/DSC04388.ARW", sha256: sha, size: Int64(bytes.count))
        let again = try await loader.load(path: "A/DSC04388.ARW", sha256: sha, size: Int64(bytes.count))

        guard case .file(let url) = first else { Issue.record("not loaded: \(first)"); return }
        #expect(try Data(contentsOf: url) == bytes)
        #expect(again == first)
        #expect(nas.rangeReadPaths.count == 5)
        // No part file left beside it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.directory.path).count == 1)
    }

    /// The bytes changed on the server since the scan: no file kept.
    @Test func changedIsNotKept() async throws {
        let (nas, cache, bytes, _) = fixture()
        defer { cache.removeAll() }
        let loader = CommonPhotosCompareLoader(client: nas, cache: cache)

        let outcome = try await loader.load(path: "A/DSC04388.ARW", sha256: "other", size: Int64(bytes.count))

        #expect(outcome == .changed)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path))?.isEmpty ?? true)
    }

    /// AC-183: the server goes away mid-download — the error reaches Compare
    /// (Try Again), and no part of the file stays.
    @Test func lostConnectionLeavesNothing() async throws {
        let (nas, cache, bytes, sha) = fixture()
        defer { cache.removeAll() }
        nas.failRangeReadsAfter = 2
        var loader = CommonPhotosCompareLoader(client: nas, cache: cache)
        loader.chunkBytes = 10_000

        await #expect(throws: RemoteFileError.unreachable(host: "nas.local")) {
            try await loader.load(path: "A/DSC04388.ARW", sha256: sha, size: Int64(bytes.count))
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path))?.isEmpty ?? true)
    }

    /// AC-182: the row changes mid-read (the load cancelled) — no file, no
    /// part, nothing in the cache.
    @Test func cancelledLeavesNothing() async throws {
        let (nas, cache, bytes, sha) = fixture()
        defer { cache.removeAll() }
        var loader = CommonPhotosCompareLoader(client: nas, cache: cache)
        loader.chunkBytes = 10_000
        let load = Task { try await loader.load(path: "A/DSC04388.ARW", sha256: sha, size: Int64(bytes.count)) }
        load.cancel()

        await #expect(throws: CancellationError.self) { try await load.value }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path))?.isEmpty ?? true)
        #expect(cache.cached(path: "A/DSC04388.ARW", sha256: sha) == nil)
    }

    /// A crash's leftover folders go at launch; other folders stay.
    @Test func sweepsLeftovers() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        let left = parent.appendingPathComponent("ShotDexCompare-old")
        let other = parent.appendingPathComponent("Keep")
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        CompareFileCache.sweepLeftovers(in: parent)

        #expect(!FileManager.default.fileExists(atPath: left.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    /// No room for the file and the margin: nothing downloaded.
    @Test func noRoomDownloadsNothing() async throws {
        let (nas, cache, bytes, sha) = fixture()
        defer { cache.removeAll() }
        let loader = CommonPhotosCompareLoader(client: nas, cache: cache, freeBytes: { 1_000 }, margin: 0)

        let outcome = try await loader.load(path: "A/DSC04388.ARW", sha256: sha, size: Int64(bytes.count))

        #expect(outcome == .noRoom)
        #expect(nas.rangeReadPaths.isEmpty)
    }
}
