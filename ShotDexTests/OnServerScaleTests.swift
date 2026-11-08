import Foundation
import Testing
@testable import ShotDex

/// FS-19.07 §7 at the size of a real library (user 2026-11-08: the Mac froze
/// and no progress line ever showed): the progress line, the grid's glyph
/// read and an Also on Server album count over 30,000 Photos items and
/// 15,000 server files must each come back in seconds, not minutes — a
/// slower read holds a reader of the pool through a whole check batch.
@MainActor
struct OnServerScaleTests {
    static let photos = Int(ProcessInfo.processInfo.environment["ONSERVER_SCALE"] ?? "") ?? 30_000
    static let serverFiles = photos / 2

    /// Photos P0… each with one listed file of its own size; the first half
    /// hashed, and a third of all also on the server with the same bytes;
    /// the server's other files have sizes no photo has.
    static func library() throws -> OnServerFixture {
        let f = try OnServerFixture(photos: photos)
        try f.database.writer.write { db in
            for n in 0..<photos {
                let copy = "photos:P\(n)"
                try db.execute(sql: "INSERT INTO copy_files (copyId, fileKey, role, size, stamp, sha256) VALUES (?, '1:IMG.HEIC', 'photo', ?, 's', ?)",
                               arguments: [copy, 10_000 + n, n < photos / 2 ? "sha\(n)" : nil])
                try db.execute(sql: "INSERT INTO copy_file_listings (copyId, stamp, listedAt) SELECT ?, modificationDate, 1 FROM photo_metadata WHERE assetId = ?",
                               arguments: [copy, "P\(n)"])
            }
            for k in 0..<serverFiles {
                let id = "server:s\(k)"
                let path = "Shared/s\(k).HEIC"
                let matches = k < photos / 3
                try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 1)", arguments: [id])
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size)
                    VALUES (?, ?, ?, 'server', ?, ?, ?)
                    """, arguments: [id, id, f.source, path, path.lowercased(), matches ? 10_000 + k : 5_000_000 + k])
                try db.execute(sql: "INSERT INTO copy_files (copyId, fileKey, role, size, sha256) VALUES (?, 'primary', 'photo', ?, ?)",
                               arguments: [id, matches ? 10_000 + k : 5_000_000 + k, matches && k < photos / 2 ? "sha\(k)" : nil])
            }
        }
        return f
    }

    private static func seconds(_ work: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try work()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test func readsStayFast() async throws {
        let f = try Self.library()
        let queries = OnServerProgressQueries(database: f.database)
        var progress = OnServerProgress()
        let progressTime = try Self.seconds { progress = try queries.progress(sourceId: f.source, folder: nil) }
        var present: Set<String> = []
        let presentTime = try Self.seconds { present = try queries.presentAnywhere() }
        let countStart = ContinuousClock.now
        let count = try await LibraryQueries(database: f.database).count(matching: f.rule(.isExactly))
        let countElapsed = ContinuousClock.now - countStart
        let countTime = Double(countElapsed.components.seconds) + Double(countElapsed.components.attoseconds) / 1e18
        print("OnServerScale: progress \(progressTime)s · presentAnywhere \(presentTime)s · album count \(countTime)s · \(progress)")
        #expect(!present.isEmpty)
        #expect(count > 0)
        #expect(progressTime < 3)
        #expect(presentTime < 3)
        #expect(countTime < 3)
    }
}
