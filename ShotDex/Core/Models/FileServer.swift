import Foundation
import GRDB

/// A file server the user uploads originals to (FS-15.01). Everything but the
/// password: that lives in the Keychain, keyed by `id`, and never in this row.
struct FileServer: Codable, Identifiable, Hashable, Sendable {
    enum TransferProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
        case smb
        case sftp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .smb: "SMB"
            case .sftp: "SFTP"
            }
        }

        var defaultPort: Int {
            switch self {
            case .smb: 445
            case .sftp: 22
            }
        }
    }

    var id: String
    var name: String
    var transferProtocol: TransferProtocol
    var host: String
    var port: Int
    var username: String
    /// The SMB share. Empty for SFTP, which has no such level.
    var share: String
    /// Destination folder inside the share (SMB) or relative to the login's
    /// home (SFTP). Empty means the top.
    var folder: String
    /// SFTP only: the host key the user trusted, `SHA256:<base64>`. Cleared
    /// whenever the host or port changes.
    var hostKeyFingerprint: String?
    /// Epoch seconds of the last upload — the prepare step picks the most
    /// recent one.
    var lastUsedAt: Int?
    var createdAt: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        transferProtocol: TransferProtocol,
        host: String,
        port: Int? = nil,
        username: String,
        share: String = "",
        folder: String = "",
        hostKeyFingerprint: String? = nil,
        lastUsedAt: Int? = nil,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.name = name
        self.transferProtocol = transferProtocol
        self.host = host
        self.port = port ?? transferProtocol.defaultPort
        self.username = username
        self.share = share
        self.folder = folder
        self.hostKeyFingerprint = hostKeyFingerprint
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }

    /// `host/share/folder` for the list row.
    var locationDescription: String {
        [host, share, ServerUploadPath.normalizedFolder(folder)]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}

extension FileServer: FetchableRecord, PersistableRecord {
    static let databaseTableName = "file_servers"
}

/// One file that reached a server with its checksum matched (FS-15 §4).
///
/// Rows outlive both the server (its id goes null, its name stays) and the
/// photo: this table is the evidence that a file is safe elsewhere, and
/// deleting the thing it describes is exactly when that evidence matters.
struct ServerUploadRecord: Codable, Hashable, Sendable {
    var id: Int64?
    var assetId: String
    /// `AssetUploadFile.key` — which of the asset's files this was.
    var fileKey: String
    var serverId: String?
    var serverName: String
    var remotePath: String
    var byteCount: Int64
    /// Lowercase hex.
    var sha256: String
    var uploadedAt: Int

    init(
        id: Int64? = nil,
        assetId: String,
        fileKey: String,
        serverId: String?,
        serverName: String,
        remotePath: String,
        byteCount: Int64,
        sha256: String,
        uploadedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.assetId = assetId
        self.fileKey = fileKey
        self.serverId = serverId
        self.serverName = serverName
        self.remotePath = remotePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.uploadedAt = uploadedAt
    }
}

extension ServerUploadRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "server_uploads"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
