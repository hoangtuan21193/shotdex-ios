#if DEBUG
import Foundation

/// `-ShotDexHashMismatch "Tuấn's MacBook"`: the smart album "On NAS · Shared"
/// over a server source on the local test SMB server (127.0.0.1:4450,
/// share `photos`), with that device caught by the random check — the state
/// boards `*_SmartAlbum` draw with their `mismatch` tweak (FS-19.07 §12.4),
/// which a real run reaches only with two devices and a wrong hash.
/// It writes into the app's own database (and the connection's password
/// into the Keychain) and stays there: run it on a simulator or the Mac
/// demo library (`-ShotDexDemoLibrary`), never on a library you keep.
enum OnServerMismatchDemo {
    static let argument = "-ShotDexHashMismatch"
    static let albumId = "demo-on-nas"
    private static let device = "demo-caught-device"

    static var deviceName: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func seed(database: AppDatabase, servers: FileServerStore, check: OnServerCheck) {
        guard let name = deviceName else { return }
        let sources = SourceStore(database: database)
        let connectionId = "demo-mismatch-smb"
        if (try? servers.fetch(id: connectionId)) ?? nil == nil {
            try? servers.save(FileServer(id: connectionId, name: "NAS Home", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                         username: "tester", share: "photos", folder: "photos"), password: "secret")
        }
        let sourceId = ((try? sources.serverSourceId(connectionId: connectionId)) ?? nil)
            ?? (try? sources.addServer(name: "NAS Home", connectionId: connectionId))
        guard let sourceId else { return }
        try? SmartAlbumStore(database: database).upsert(SmartAlbum(
            id: albumId, name: "On NAS · Shared",
            query: SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, op: .isExactly, text: sourceId, folder: "Shared")]),
            createdAt: 3))
        try? SharedIndexStore(database: database).saveDeviceNames([device: name])
        check.showCaughtForDemo([device])
    }
}
#endif
