import Foundation
import GRDB

/// The copy a photo opens, edits and exports from (FS-19.02 §3), and how
/// its editor saves.
struct OpenCopy: Equatable, Sendable {
    let copyId: String
    let sourceId: String
    /// `photos` · `file` · `server`
    let kind: String
    let photoKitId: String?
    let relativePath: String?

    /// A Photos asset saves its edit into Photos on Done; a file or server
    /// copy keeps its recipe as it goes — "Edited · Saved", no Done (D16).
    var savesOnDone: Bool { kind == "photos" }

    static let autosavedLabel = String(localized: "Edited · Saved", comment: "Editor toolbar: a file photo's recipe is saved as it changes")
}

struct OpenCopyQueries: Sendable {
    let database: AppDatabase

    func openCopy(photoId: String) throws -> OpenCopy? {
        try database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id, c.sourceId, c.kind, c.photoKitId, c.relativePath, c.isOnline, c.isCloudPlaceholder, s.kind AS sourceKind
                FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId = ? AND c.missingSince IS NULL AND c.isHidden = 0
                """, arguments: [try PhotoAliasResolver.photoId(db, for: photoId)])
            let candidates = rows.map {
                CopyOrder.Candidate(copyId: $0["id"], kind: $0["kind"], sourceKind: $0["sourceKind"],
                                    isOnline: $0["isOnline"], isCloudPlaceholder: $0["isCloudPlaceholder"])
            }
            guard let first = CopyOrder.sorted(candidates).first,
                  let row = rows.first(where: { $0["id"] as String == first.copyId }) else { return nil }
            return OpenCopy(copyId: row["id"], sourceId: row["sourceId"], kind: row["kind"],
                            photoKitId: row["photoKitId"], relativePath: row["relativePath"])
        }
    }
}
