import Foundation
import GRDB
import ImageIO

/// The read of a folder or drive source (FS-19.01 §4): list what is there,
/// pair RAW with its twin, read EXIF and the fast hash of each new or
/// changed file, and record a photo, its copy and its metadata row. The
/// source folder is only ever read — nothing is written into it.
struct FolderSourceIndexer: Sendable {
    let database: AppDatabase
    let composer: MetadataComposer

    struct Summary: Equatable, Sendable {
        var photos = 0
        var unchanged = 0
        /// Pause stopped the read before the end (FS-19.01 §4).
        var paused = false
    }

    /// `shouldContinue` is asked before each file; false pauses the read.
    /// Every file is recorded in its own transaction, so a pause, a quit or a
    /// crash keeps what was read, and the next read skips it by path, size
    /// and date — Resume, even after a relaunch, reads only what is left.
    func index(sourceId: String, root: URL, includesSubfolders: Bool, pairsRawAndJpeg: Bool,
               now: Date = Date(), shouldContinue: () -> Bool = { true }) throws -> Summary {
        let files = FolderEnumeration.entries(in: root, includeSubfolders: includesSubfolders).filter { !$0.isSidecar }
        let units = PairingRule.units(files, pairs: pairsRawAndJpeg,
                                      name: { ($0.relativePath as NSString).lastPathComponent },
                                      folder: { ($0.relativePath as NSString).deletingLastPathComponent })
        var summary = Summary()
        let stamp = Int(now.timeIntervalSince1970)
        for unit in units {
            try Task.checkCancellation()
            guard shouldContinue() else {
                summary.paused = true
                return summary
            }
            let file = unit.primary
            let key = Self.pathKey(file.relativePath)
            let modified = file.modified.map { Int($0.timeIntervalSince1970) }
            let existing = try database.reader.read { db in
                try Row.fetchOne(db, sql: "SELECT id, photoId, size, modifiedAt FROM photo_copies WHERE sourceId = ? AND relativePathKey = ?",
                                 arguments: [sourceId, key])
            }
            if let existing, existing["size"] as Int64? == file.size, existing["modifiedAt"] as Int? == modified {
                try database.writer.write { db in
                    try db.execute(sql: "UPDATE photo_copies SET lastSeenAt = ?, isOnline = 1 WHERE id = ?",
                                   arguments: [stamp, existing["id"] as String])
                }
                summary.unchanged += 1
                continue
            }

            let url = root.appendingPathComponent(file.relativePath)
            let hash = try ContentHasher.hash(FileBytes(url: url), full: false)
            let photoId: String = existing?["photoId"] ?? UUID().uuidString
            let copyId: String = existing?["id"] ?? UUID().uuidString
            let record = metadata(photoId: photoId, url: url, file: file)

            try database.writer.write { db in
                try db.execute(sql: "INSERT OR IGNORE INTO photos (id, createdAt) VALUES (?, ?)", arguments: [photoId, stamp])
                try db.execute(sql: "UPDATE photos SET orphanedAt = NULL WHERE id = ?", arguments: [photoId])
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, modifiedAt, pairedPath, isOnline, lastSeenAt)
                    VALUES (?, ?, ?, 'file', ?, ?, ?, ?, ?, 1, ?)
                    ON CONFLICT(id) DO UPDATE SET relativePath = excluded.relativePath, size = excluded.size,
                        modifiedAt = excluded.modifiedAt, pairedPath = excluded.pairedPath, isOnline = 1, lastSeenAt = excluded.lastSeenAt
                    """, arguments: [copyId, photoId, sourceId, file.relativePath, key, file.size, modified,
                                     unit.companion?.relativePath, stamp])
                try db.execute(sql: """
                    INSERT INTO content_hashes (copyId, algorithm, algorithmVersion, fastHash, fullHash, hashedAt)
                    VALUES (?, ?, ?, ?, NULL, ?)
                    ON CONFLICT(copyId) DO UPDATE SET algorithm = excluded.algorithm, algorithmVersion = excluded.algorithmVersion,
                        fastHash = excluded.fastHash, fullHash = NULL, hashedAt = excluded.hashedAt
                    """, arguments: [copyId, hash.algorithm, hash.version, hash.fast, stamp])
                try record.upsert(db)
            }
            summary.photos += 1
        }
        return summary
    }

    /// The metadata row of a file photo — the same composer as Photos assets,
    /// fed from the file instead of the asset.
    private func metadata(photoId: String, url: URL, file: FolderEnumeration.Entry) -> PhotoMetadata {
        let isVideo = FolderEnumeration.isMovie(url)
        var exif = RawExif.empty
        var status = ExifStatus.noExif
        var width: Int?, height: Int?
        if !isVideo {
            if case .success(let read) = ExifReader.readExif(fromImageAt: url) {
                exif = read
                status = .indexed
            }
            if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
                height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            }
        }
        let asset = AssetInfo(
            assetId: photoId,
            creationDate: isVideo ? file.modified : (PhotoOriginFile.captureDate(at: url) ?? file.modified),
            modificationDate: file.modified,
            mediaType: (isVideo ? MediaKind.video : MediaKind.photo).storedValue,
            width: width, height: height,
            fileSize: Int(file.size),
            isFavorite: false,
            originalFilename: url.lastPathComponent
        )
        return composer.compose(asset: asset, exif: exif, exifStatus: status)
    }

    /// What makes two paths one file: NFC, case folded.
    static func pathKey(_ relativePath: String) -> String {
        relativePath.precomposedStringWithCanonicalMapping.lowercased()
    }
}
