import Foundation

/// One place photos went (FS-15.02 §8): a connection and a folder on it.
struct UploadDestination: Identifiable, Hashable, Sendable {
    let connectionName: String
    let folder: String
    /// Newest upload first, each photo once.
    let assetIds: [String]

    var id: String { "\(connectionName)\u{1F}\(folder)" }
}

/// Groups the upload history by where the files landed, so Uploaded from
/// This Device answers "where is it?" (FS-15.02 §8).
enum UploadDestinations {
    struct Row: Sendable {
        let connectionName: String
        let remotePath: String
        let assetId: String
        let uploadedAt: Int
    }

    /// A photo whose files went to two places is in both. Places are
    /// ordered by their newest upload; `present` drops photos no longer in
    /// the library, and places left empty.
    static func group(_ rows: [Row], present: Set<String>? = nil) -> [UploadDestination] {
        struct Key: Hashable { let name: String; let folder: String }
        var latest: [Key: [String: Int]] = [:]
        for row in rows {
            if let present, !present.contains(row.assetId) { continue }
            let key = Key(name: row.connectionName, folder: ServerUploadPath.parent(of: ServerUploadPath.normalizedFolder(row.remotePath)))
            latest[key, default: [:]][row.assetId] = max(latest[key]?[row.assetId] ?? .min, row.uploadedAt)
        }
        return latest
            .map { key, times -> (UploadDestination, Int) in
                let ids = times.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
                return (UploadDestination(connectionName: key.name, folder: key.folder, assetIds: ids), times.values.max() ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .map(\.0)
    }
}
