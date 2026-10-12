import Foundation
import GRDB

/// Runs a Hide command (FS-19.04 §3). Hiding in Photos is PhotoKit's
/// `isHidden`, injected; everything else is ShotDex's own copy flag.
struct HideService: Sendable {
    let database: AppDatabase
    /// Puts these Photos assets in Photos' Hidden album.
    let hideInPhotos: @Sendable ([String]) async throws -> Void

    /// Where each photo has copies, for `HideCommandPlan`. In chunks: a
    /// selection can be the whole library, past SQLite's argument limit.
    func photos(_ photoIds: [String]) throws -> [HideCommandPlan.Photo] {
        var result: [HideCommandPlan.Photo] = []
        for chunk in photoIds.chunked(into: Self.chunkSize) {
            let kinds = try database.reader.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT photoId, MAX(kind = 'photos') AS photos, MAX(kind != 'photos') AS other FROM photo_copies
                    WHERE photoId IN (\(databaseQuestionMarks(count: chunk.count))) AND missingSince IS NULL
                    GROUP BY photoId
                    """, arguments: StatementArguments(Array(chunk)))
            }
            result += kinds.map { HideCommandPlan.Photo(hasPhotosCopy: $0["photos"], hasOtherCopy: $0["other"]) }
        }
        return result
    }

    func commands(for photoIds: [String]) throws -> [HideCommand] {
        HideCommandPlan.commands(for: try photos(photoIds))
    }

    private static let chunkSize = 500

    func run(_ command: HideCommand, photoIds: [String]) async throws {
        for chunk in photoIds.chunked(into: Self.chunkSize) {
            try await run(command, chunk: Array(chunk))
        }
    }

    private func run(_ command: HideCommand, chunk photoIds: [String]) async throws {
        let assets = try await database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT photoKitId FROM photo_copies
                WHERE kind = 'photos' AND missingSince IS NULL AND photoId IN (\(databaseQuestionMarks(count: photoIds.count)))
                """, arguments: StatementArguments(photoIds))
        }
        switch command {
        case .hideInShotDexOnly:
            try HiddenCopyStore(database: database).hide(photoIds: photoIds)
        case .hide, .hideInPhotos:
            // A Photos item hides in Photos, as it always has; whatever else
            // the photo has, ShotDex hides. Its Photos copy is flagged too so
            // the grid does not wait for the next library change.
            if !assets.isEmpty { try await hideInPhotos(assets) }
            try HiddenCopyStore(database: database).hide(photoIds: photoIds)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
