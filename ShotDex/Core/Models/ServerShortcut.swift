import Foundation
import GRDB

/// A folder on a server kept as a tile in Collections → Network
/// (FS-17.04). Its own table: the user made it.
struct ServerShortcut: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var serverId: String
    /// From the machine's root, like every connection path.
    var path: String
    var name: String
    /// A ≤320 px JPEG of the folder's first photo, taken the last time the
    /// tile was opened; nil until then.
    var coverJPEG: Data?
    var createdAt: Int

    init(
        id: String = UUID().uuidString,
        serverId: String,
        path: String,
        name: String,
        coverJPEG: Data? = nil,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.serverId = serverId
        self.path = ServerUploadPath.normalizedFolder(path)
        self.name = name
        self.coverJPEG = coverJPEG
        self.createdAt = createdAt
    }
}

extension ServerShortcut: FetchableRecord, PersistableRecord {
    static let databaseTableName = "server_shortcuts"
}
