import Foundation

/// What the server form edits (FS-15.01 §3): the row, plus a password that is
/// only sent to the Keychain when the user typed one.
struct FileServerDraft: Identifiable {
    var server: FileServer
    let isNew: Bool
    var password = ""
    /// Whether a password is already saved — the field then reads "Saved"
    /// and leaving it empty keeps it.
    var hasSavedPassword = false
    /// What is in the Port field. Empty means the protocol's default, which
    /// the field shows as its placeholder — nobody has to delete a 445 to
    /// type a 4450.
    var portText = ""

    var id: String { server.id }

    init() {
        server = FileServer(name: "", transferProtocol: .smb, host: "", username: "")
        isNew = true
    }

    init(server: FileServer) {
        self.server = server
        isNew = false
        portText = server.port == server.defaultPort ? "" : String(server.port)
    }

    /// The port the form stands for: typed, or the protocol's default.
    var port: Int? {
        let text = portText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? server.defaultPort : Int(text)
    }

    var canSave: Bool {
        !server.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !server.username.trimmingCharacters(in: .whitespaces).isEmpty
            && port.map { (1...65_535).contains($0) } == true
            // SMB files live inside a shared folder: the first folder of the
            // path (FS-15.01 §3a).
            && (server.transferProtocol != .smb || !ServerUploadPath.normalizedFolder(server.folder.trimmingCharacters(in: .whitespaces)).isEmpty)
    }

    /// The row as saved: trimmed, a blank name falls back to the host; only
    /// WebDAV keeps the share column, as its Path.
    var normalized: FileServer {
        var row = server
        row.port = port ?? row.defaultPort
        row.host = row.host.trimmingCharacters(in: .whitespaces)
        row.username = row.username.trimmingCharacters(in: .whitespaces)
        switch row.transferProtocol {
        case .webdav: row.share = ServerUploadPath.normalizedFolder(row.share)
        case .smb, .sftp: row.share = ""
        case .files: break
        }
        row.folder = ServerUploadPath.normalizedFolder(row.folder.trimmingCharacters(in: .whitespaces))
        let name = row.name.trimmingCharacters(in: .whitespaces)
        row.name = name.isEmpty ? row.host : name
        return row
    }
}
