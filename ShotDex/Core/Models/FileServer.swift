import Foundation
import GRDB

/// A file server the user uploads originals to (FS-15.01). Everything but the
/// password: that lives in the Keychain, keyed by `id`, and never in this row.
struct FileServer: Codable, Identifiable, Hashable, Sendable {
    enum TransferProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
        case smb
        case sftp
        case webdav
        case ftps
        case ftp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .smb: "SMB"
            case .sftp: "SFTP"
            case .webdav: "WebDAV"
            case .ftps: "FTPS"
            case .ftp: "FTP"
            }
        }

        /// The port at this protocol's default TLS setting.
        var defaultPort: Int {
            switch self {
            case .smb: 445
            case .sftp: 22
            case .webdav: 443
            case .ftps, .ftp: 21
            }
        }

        /// Protocols the form offers — those with a client behind them.
        static var selectable: [TransferProtocol] {
            allCases.filter { RemoteFileClientFactory.supports($0) }
        }
    }

    /// FTPS: TLS from the first byte (990) or after `AUTH TLS` (21).
    enum TLSMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case explicit
        case implicit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .explicit: String(localized: "Explicit", comment: "FTPS TLS mode: AUTH TLS on port 21")
            case .implicit: String(localized: "Implicit", comment: "FTPS TLS mode: TLS from the start on port 990")
            }
        }
    }

    var id: String
    var name: String
    var transferProtocol: TransferProtocol
    var host: String
    var port: Int
    var username: String
    /// The SMB share, or the WebDAV base path (`remote.php/dav/files/me`).
    /// Empty for SFTP and FTP, which have no such level.
    var share: String
    /// Destination folder inside the share (SMB) or relative to the login's
    /// home (SFTP). Empty means the top.
    var folder: String
    /// The folder the last upload through this connection went to; nil
    /// until the first one, and again after the form's Folder changes — the
    /// sheet then starts at `folder`.
    var uploadFolder: String?
    /// Whether the last upload sorted into year/day folders. Off for a new
    /// connection.
    var usesDateFolders: Bool
    /// The identity the user trusted: the SFTP host key or the TLS
    /// certificate (WebDAV over HTTPS, FTPS), `SHA256:<base64>`. Cleared
    /// whenever the host or port changes.
    var trustedFingerprint: String?
    /// WebDAV: HTTPS (default) or plain HTTP.
    var usesTLS: Bool
    /// FTPS only.
    var tlsMode: TLSMode
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
        uploadFolder: String? = nil,
        usesDateFolders: Bool = false,
        trustedFingerprint: String? = nil,
        usesTLS: Bool = true,
        tlsMode: TLSMode = .explicit,
        lastUsedAt: Int? = nil,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.name = name
        self.transferProtocol = transferProtocol
        self.host = host
        self.usesTLS = usesTLS
        self.tlsMode = tlsMode
        self.port = port ?? Self.defaultPort(transferProtocol, usesTLS: usesTLS, tlsMode: tlsMode)
        self.username = username
        self.share = share
        self.folder = folder
        self.uploadFolder = uploadFolder
        self.usesDateFolders = usesDateFolders
        self.trustedFingerprint = trustedFingerprint
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }

    /// The port this connection uses when none is typed.
    var defaultPort: Int { Self.defaultPort(transferProtocol, usesTLS: usesTLS, tlsMode: tlsMode) }

    static func defaultPort(_ transferProtocol: TransferProtocol, usesTLS: Bool, tlsMode: TLSMode) -> Int {
        switch transferProtocol {
        case .webdav: usesTLS ? 443 : 80
        case .ftps: tlsMode == .implicit ? 990 : 21
        default: transferProtocol.defaultPort
        }
    }

    /// Passwords and photos cross the network in the clear (FS-15.05 §3).
    var isUnencrypted: Bool {
        transferProtocol == .ftp || (transferProtocol == .webdav && !usesTLS)
    }

    /// Whether the connection has a server identity to trust: an SSH host
    /// key, or a TLS certificate.
    var hasTrustedIdentity: Bool {
        switch transferProtocol {
        case .sftp, .ftps: true
        case .webdav: usesTLS
        case .smb, .ftp: false
        }
    }

    /// Where the upload sheet starts: the last folder used, else the form's.
    var startingUploadFolder: String {
        ServerUploadPath.normalizedFolder(uploadFolder ?? folder)
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

/// One server file saved into the library as (part of) an asset (FS-17 §4).
/// Like `ServerUploadRecord`, it keeps the server's name so it survives the
/// server being deleted.
struct ServerDownloadRecord: Codable, Hashable, Sendable {
    var id: Int64?
    var assetId: String
    var serverId: String?
    var serverName: String
    var remotePath: String
    var byteCount: Int64
    /// Lowercase hex, of what was written to the library.
    var sha256: String
    var downloadedAt: Int

    init(
        id: Int64? = nil,
        assetId: String,
        serverId: String?,
        serverName: String,
        remotePath: String,
        byteCount: Int64,
        sha256: String,
        downloadedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.assetId = assetId
        self.serverId = serverId
        self.serverName = serverName
        self.remotePath = remotePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.downloadedAt = downloadedAt
    }
}

extension ServerDownloadRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "server_downloads"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
