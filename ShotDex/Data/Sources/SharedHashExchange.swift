import Foundation
import GRDB

/// The hashes this device and the others on the same iCloud account trade
/// (FS-19.07 §12.3). `adopt` gives an unhashed file the hash another device
/// worked out when every key still matches — a Photos file by iCloud
/// identifier, resource key, the asset's modification date and size; a
/// server file by the server's identity, path, size and write time — and
/// that device was not caught wrong before it hashed. `recordOwn` queues
/// what this device hashed itself for upload. Moving the rows to and from
/// iCloud is `IndexShareService`'s; nothing here touches the network.
struct SharedHashExchange: Sendable {
    let database: AppDatabase
    /// This device (`BackupDeviceIdentity`).
    let device: String
    /// iCloud identifiers by local asset id; a photo not in iCloud yet has
    /// none and cannot be shared.
    let cloudIds: @Sendable ([String]) async -> [String: String]

    private var copyFiles: CopyFileStore { CopyFileStore(database: database) }
    private var shared: SharedIndexStore { SharedIndexStore(database: database) }

    /// A Photos file and the keys a shared hash must match.
    private struct PhotosFileKey {
        var copyId: String
        var assetId: String
        var fileKey: String
        var size: Int64?
        var assetModified: Int?
        var sha256: String?
        var hashedAt: Int?
    }

    /// Own hashes queued per pass: the rest go on the next.
    static let publishLimit = 2_000

    /// Fills what other devices hashed. Returns how many files it filled.
    @discardableResult
    func adopt(now: Date = Date()) async throws -> Int {
        try await adoptPhotos(copyIds: nil, now: now) + adoptServers(now: now)
    }

    /// The same for these Photos copies only — the ones a hash pass just
    /// listed, before it picks what to download.
    @discardableResult
    func adoptPhotos(copyIds: [String], now: Date = Date()) async throws -> Int {
        try await adoptPhotos(copyIds: Optional(copyIds), now: now)
    }

    /// Queues this device's own hashes — read here, not taken from another
    /// device or from Backup — for the other devices: those not queued yet,
    /// up to `publishLimit` a pass. A photo not in iCloud yet waits.
    @discardableResult
    func recordOwn(now: Date = Date()) async throws -> Int {
        let photos = try photosFiles(hashed: true, limit: Self.publishLimit)
        let ids = await cloudIds(Array(Set(photos.map(\.assetId))))
        var queued: [(copyId: String, fileKey: String)] = []
        let photoHashes = photos.compactMap { file -> SharedPhotoHash? in
            guard let cloudId = ids[file.assetId], let sha256 = file.sha256 else { return nil }
            queued.append((file.copyId, file.fileKey))
            // When it was hashed, not when it is sent: a check that caught
            // this device wrong in between must still drop it (§12.4).
            return SharedPhotoHash(cloudId: cloudId, fileKey: file.fileKey, assetModified: file.assetModified, size: file.size,
                                   sha256: sha256, device: device, hashedAt: file.hashedAt ?? 0)
        }
        var serverHashes: [SharedServerHash] = []
        for (sourceId, server) in try serverSources() {
            guard let key = ServerIdentity.key(server), serverHashes.count < Self.publishLimit else { continue }
            for own in try copyFiles.ownServerHashes(sourceId: sourceId, unshared: true, limit: Self.publishLimit - serverHashes.count) {
                queued.append((own.copyId, own.fileKey))
                serverHashes.append(SharedServerHash(serverKey: key, pathKey: Self.pathKey(server: server, relativePath: own.relativePath),
                                                     size: own.size, modifiedAt: own.modifiedAt, sha256: own.sha256, device: device,
                                                     hashedAt: own.hashedAt))
            }
        }
        try shared.saveLocal(photoHashes: photoHashes, serverHashes: serverHashes, now: now)
        try copyFiles.markShared(queued, at: now)
        return photoHashes.count + serverHashes.count
    }

    // MARK: Photos

    private func adoptPhotos(copyIds: [String]?, now: Date) async throws -> Int {
        let files = try photosFiles(hashed: false, copyIds: copyIds)
        guard !files.isEmpty else { return 0 }
        let ids = await cloudIds(Array(Set(files.map(\.assetId))))
        let byCloud = Dictionary(grouping: try shared.remotePhotoHashes(cloudIds: Array(Set(ids.values))), by: \.cloudId)
        var filled = 0
        for file in files {
            guard let cloudId = ids[file.assetId], let modified = file.assetModified, let size = file.size else { continue }
            let offers = (byCloud[cloudId] ?? [])
                .filter { $0.device != device && $0.fileKey == file.fileKey && $0.assetModified == modified && $0.size == size }
                .sorted { $0.hashedAt > $1.hashedAt }
            if try take(offers.map { ($0.sha256, $0.device, $0.hashedAt) }, copyId: file.copyId, fileKey: file.fileKey, now: now) {
                filled += 1
            }
        }
        return filled
    }

    /// Photos files with their listing's modification date — unhashed ones
    /// to fill (all, or of these copies), or this device's own hashes not
    /// yet queued for the others.
    private func photosFiles(hashed: Bool, copyIds: [String]? = nil, limit: Int = .max) throws -> [PhotosFileKey] {
        try database.reader.read { db in
            var out: [PhotosFileKey] = []
            // One query for all, or one per chunk of copies.
            let chunks: [[String]?] = copyIds.map { ids in
                stride(from: 0, to: ids.count, by: 500).map { Array(ids[$0..<min($0 + 500, ids.count)]) }
            } ?? [nil]
            for chunk in chunks {
                var arguments = StatementArguments(chunk ?? [])
                arguments += [min(limit, Int(Int32.max))]
                out += try Row.fetchAll(db, sql: """
                    SELECT f.copyId, c.photoKitId, f.fileKey, f.size, f.sha256, f.hashedAt, l.stamp FROM copy_files f
                    JOIN photo_copies c ON c.id = f.copyId AND c.kind = 'photos' AND c.photoKitId IS NOT NULL
                    JOIN copy_file_listings l ON l.copyId = f.copyId
                    WHERE \(hashed ? "f.sha256 IS NOT NULL AND f.origin = 'hashed' AND f.sharedAt IS NULL" : "f.sha256 IS NULL")
                      \(chunk.map { "AND f.copyId IN (\(databaseQuestionMarks(count: $0.count)))" } ?? "")
                    LIMIT ?
                    """, arguments: arguments).map {
                    PhotosFileKey(copyId: $0["copyId"], assetId: $0["photoKitId"], fileKey: $0["fileKey"], size: $0["size"],
                                  assetModified: $0["stamp"], sha256: $0["sha256"], hashedAt: $0["hashedAt"])
                }
            }
            return out
        }
    }

    // MARK: Servers

    private func adoptServers(now: Date) async throws -> Int {
        var filled = 0
        for (sourceId, server) in try serverSources() {
            guard let key = ServerIdentity.key(server) else { continue }
            let files = try copyFiles.unhashedServerFiles(sourceId: sourceId).filter { $0.modifiedAt != nil }
            guard !files.isEmpty else { continue }
            let paths = files.map { Self.pathKey(server: server, relativePath: $0.relativePath) }
            let byPath = Dictionary(grouping: try shared.remoteServerHashes(serverKey: key, pathKeys: Array(Set(paths))), by: \.pathKey)
            for (file, path) in zip(files, paths) {
                let offers = (byPath[path] ?? [])
                    .filter { $0.device != device && $0.size == file.size && $0.modifiedAt == file.modifiedAt }
                    .sorted { $0.hashedAt > $1.hashedAt }
                if try take(offers.map { ($0.sha256, $0.device, $0.hashedAt) }, copyId: file.copyId, fileKey: file.fileKey, now: now) {
                    filled += 1
                }
            }
        }
        return filled
    }

    /// Server sources with their connection.
    private func serverSources() throws -> [(String, FileServer)] {
        try database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, connectionId FROM sources WHERE kind = 'server' AND connectionId IS NOT NULL")
            return try rows.compactMap { row in
                guard let server = try FileServer.fetchOne(db, key: row["connectionId"] as String) else { return nil }
                return (row["id"], server)
            }
        }
    }

    /// The path on the server, as another device's connection to the same
    /// files names it: the connection's folder joined with the path under it.
    static func pathKey(server: FileServer, relativePath: String) -> String {
        FolderSourceIndexer.pathKey(ServerUploadPath.join(server.folder, relativePath))
    }

    // MARK: Taking one

    /// The newest offer from a device not caught wrong before it hashed.
    private func take(_ offers: [(sha256: String, device: String, hashedAt: Int)], copyId: String, fileKey: String,
                      now: Date) throws -> Bool {
        for offer in offers {
            let made = Date(timeIntervalSince1970: TimeInterval(offer.hashedAt))
            guard try copyFiles.accepts(device: offer.device, hashedAt: made, now: now) else { continue }
            // False when the file was hashed here meanwhile: that hash stays.
            return try copyFiles.saveHash(offer.sha256.lowercased(), copyId: copyId, fileKey: fileKey, origin: .shared,
                                          sharedFrom: offer.device, hashedAt: made, at: now)
        }
        return false
    }
}
