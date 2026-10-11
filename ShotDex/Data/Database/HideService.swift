import Foundation
import GRDB

/// Runs a Hide command (FS-19.04 §3). Hiding in Photos is PhotoKit's
/// `isHidden`, injected; everything else is ShotDex's own copy flag.
struct HideService: Sendable {
    let database: AppDatabase
    /// Puts these Photos assets in Photos' Hidden album.
    let hideInPhotos: @Sendable ([String]) async throws -> Void

    /// Where each photo has copies, for `HideCommandPlan`.
    func photos(_ photoIds: [String]) throws -> [HideCommandPlan.Photo] {
        guard !photoIds.isEmpty else { return [] }
        let kinds = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT photoId, MAX(kind = 'photos') AS photos, MAX(kind != 'photos') AS other FROM photo_copies
                WHERE photoId IN (\(databaseQuestionMarks(count: photoIds.count))) AND missingSince IS NULL
                GROUP BY photoId
                """, arguments: StatementArguments(photoIds))
        }
        return kinds.map { HideCommandPlan.Photo(hasPhotosCopy: $0["photos"], hasOtherCopy: $0["other"]) }
    }

    func commands(for photoIds: [String]) throws -> [HideCommand] {
        HideCommandPlan.commands(for: try photos(photoIds))
    }

    func run(_ command: HideCommand, photoIds: [String]) async throws {
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
